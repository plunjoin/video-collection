package maccms

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"video-collection-api/config"
)

// Client 多协议多格式智能采集客户端
type Client struct {
	cfg        config.SourceConfig
	httpClient *http.Client
	filter     *FilterEngine
	rule       *config.CollectionRule
	ruleErr    error
}

// QueryParams 采集查询参数
type QueryParams struct {
	Action string // "list" 或 "detail" (默认为 "detail")
	Page   int    // 页码 pg
	TypeID int    // 分类ID t
	Hours  int    // 最近几小时内更新 h (0 或 -1 表示全量不带 h 参数)
	IsAll  bool   // 是否为全量采集 (若为 true 则绝对不带 h 参数)
	WD     string // 关键字 wd
	IDs    string // 多个ID逗号隔开 ids
}

// NewClient 创建客户端
func NewClient(cfg config.SourceConfig) *Client {
	timeout := time.Duration(cfg.TimeoutSec) * time.Second
	if timeout <= 0 {
		timeout = 15 * time.Second
	}

	rule, ruleErr := config.ResolveCollectionRule(cfg)
	return &Client{
		rule: rule, ruleErr: ruleErr,
		cfg: cfg,
		httpClient: &http.Client{
			Timeout: timeout,
		},
		filter: NewFilterEngine(cfg),
	}
}

// FetchRawResponse 请求接口并反序列化为统一响应格式
func (c *Client) FetchRawResponse(ctx context.Context, params QueryParams) (*MacCmsResponse, error) {
	if c.ruleErr != nil {
		return nil, c.ruleErr
	}
	protoType := c.rule.Format

	// 针对纯网页 RSS 订阅源，第二页以后无需重复拉取
	if (protoType == "rss" || protoType == "rss_feed") && params.Page > 1 {
		return &MacCmsResponse{
			Code:      1,
			Msg:       "RSS Feed 仅有首页数据",
			Page:      FlexInt(params.Page),
			PageCount: 1,
			Total:     0,
			List:      nil,
		}, nil
	}

	reqURL, err := c.buildURL(params)
	if err != nil {
		return nil, err
	}

	var respBody []byte
	var reqErr error

	retries := c.cfg.RetryCount + 1

	for i := 0; i < retries; i++ {
		if i > 0 {
			timer := time.NewTimer(500 * time.Millisecond)
			select {
			case <-ctx.Done():
				timer.Stop()
				return nil, ctx.Err()
			case <-timer.C:
			}
		}
		req, err := http.NewRequestWithContext(ctx, c.rule.Method, reqURL, strings.NewReader(c.rule.Body))
		if err != nil {
			return nil, fmt.Errorf("create request error: %w", err)
		}

		if c.rule.Method == "POST" {
			req.Header.Set("Content-Type", "application/json")
		}
		// 默认请求头
		req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
		req.Header.Set("Accept", "*/*")

		// 注入自定义 Header 头配置 (如 Authorization、Referer、Cookie 等)
		headers := c.cfg.Headers
		if len(headers) == 0 && c.cfg.Filter.Headers != nil {
			headers = c.cfg.Filter.Headers
		}
		for k, v := range headers {
			if strings.TrimSpace(k) != "" && strings.TrimSpace(v) != "" {
				req.Header.Set(strings.TrimSpace(k), strings.TrimSpace(v))
			}
		}

		resp, err := c.httpClient.Do(req)
		if err != nil {
			reqErr = err
			continue
		}

		respBody, err = io.ReadAll(io.LimitReader(resp.Body, 8*1024*1024+1))
		_ = resp.Body.Close()

		if err != nil {
			reqErr = err
			continue
		}

		if len(respBody) > 8*1024*1024 {
			return nil, fmt.Errorf("单次响应超过 8 MB 上限")
		}
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			reqErr = fmt.Errorf("http status not 200: %d", resp.StatusCode)
			continue
		}

		reqErr = nil
		break
	}

	if reqErr != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("上游请求失败 (%d 次尝试)", retries)
	}

	respBody = bytes.TrimPrefix(respBody, []byte("\xef\xbb\xbf"))
	trimmed := bytes.TrimSpace(respBody)
	switch protoType {
	case "maccms_xml", "rss":
		return ParseXmlResponse(trimmed)
	case "custom_json":
		return ParseCustomJsonResponse(trimmed, c.rule.Mapping)
	}
	var cmsResp MacCmsResponse
	if err := json.Unmarshal(trimmed, &cmsResp); err != nil {
		return nil, fmt.Errorf("JSON 响应解析失败: %w", err)
	}
	if cmsResp.Code != 1 {
		return nil, fmt.Errorf("上游报告采集失败")
	}

	return &cmsResp, nil
}

// GetClassList 获取采集源的所有分类 (用于配置分类映射)
func (c *Client) GetClassList(ctx context.Context) ([]ClassItem, error) {
	resp, err := c.FetchRawResponse(ctx, QueryParams{Action: "list", Page: 1})
	if err != nil {
		return nil, err
	}
	return resp.Class, nil
}

// CollectPage 拉取单页数据并进行规则过滤清洗
func (c *Client) CollectPage(ctx context.Context, params QueryParams) ([]CleanedVod, *MacCmsResponse, error) {
	if params.Action == "" {
		params.Action = "detail"
	}
	rawResp, err := c.FetchRawResponse(ctx, params)
	if err != nil {
		return nil, nil, err
	}

	var cleanedList []CleanedVod
	for _, rawItem := range rawResp.List {
		cleaned, ok := c.filter.CleanAndTransform(rawItem)
		if ok && cleaned != nil {
			cleanedList = append(cleanedList, *cleaned)
		}
	}

	return cleanedList, rawResp, nil
}

// BuildURL 公开构造请求 URL
func (c *Client) BuildURL(params QueryParams) string {
	u, _ := c.buildURL(params)
	return u
}

// buildURL 构造符合协议规范的请求 URL (智能支持 MacCMS、XML、RSS Feed 及附加参数)
func (c *Client) buildURL(params QueryParams) (string, error) {
	if c.ruleErr != nil {
		return "", c.ruleErr
	}
	u, err := url.Parse(c.cfg.API)
	if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") {
		return "", fmt.Errorf("invalid api url")
	}
	q := u.Query()
	action := params.Action
	if action == "" {
		action = "detail"
	}
	hours := params.Hours
	if hours == 0 && !params.IsAll {
		hours = c.cfg.CollectHours
	}
	positive := func(n int) string {
		if n > 0 {
			return strconv.Itoa(n)
		}
		return ""
	}
	values := map[string]string{"{page}": positive(params.Page), "{hours}": positive(hours), "{action}": action, "{type_id}": positive(params.TypeID), "{keyword}": params.WD, "{ids}": params.IDs}
	if params.IsAll {
		values["{hours}"] = ""
	}
	c.appendCustomParams(&q)
	for key, template := range c.rule.Query {
		value := template
		omit := false
		for token, replacement := range values {
			if strings.Contains(value, token) && replacement == "" {
				omit = true
			}
			value = strings.ReplaceAll(value, token, replacement)
		}
		if omit {
			q.Del(key)
		} else {
			q.Set(key, value)
		}
	}
	u.RawQuery = q.Encode()
	return u.String(), nil
}

func (c *Client) appendCustomParams(q *url.Values) {
	params := c.cfg.CustomParams
	if len(params) == 0 && c.cfg.Filter.CustomParams != nil {
		params = c.cfg.Filter.CustomParams
	}
	for k, v := range params {
		k = strings.TrimSpace(k)
		if k != "" {
			q.Set(k, strings.TrimSpace(v))
		}
	}
}
