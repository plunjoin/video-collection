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

	return &Client{
		cfg: cfg,
		httpClient: &http.Client{
			Timeout: timeout,
		},
		filter: NewFilterEngine(cfg),
	}
}

// FetchRawResponse 请求接口并反序列化为统一响应格式
func (c *Client) FetchRawResponse(ctx context.Context, params QueryParams) (*MacCmsResponse, error) {
	protoType := strings.ToLower(strings.TrimSpace(c.cfg.Type))

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

	retries := c.cfg.RetryCount
	if retries <= 0 {
		retries = 1
	}

	for i := 0; i < retries; i++ {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
		if err != nil {
			return nil, fmt.Errorf("create request error: %w", err)
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
			time.Sleep(500 * time.Millisecond)
			continue
		}

		respBody, err = io.ReadAll(resp.Body)
		_ = resp.Body.Close()

		if err != nil {
			reqErr = err
			time.Sleep(500 * time.Millisecond)
			continue
		}

		if resp.StatusCode != http.StatusOK {
			reqErr = fmt.Errorf("http status not 200: %d", resp.StatusCode)
			time.Sleep(500 * time.Millisecond)
			continue
		}

		reqErr = nil
		break
	}

	if reqErr != nil {
		return nil, fmt.Errorf("request to %s failed after %d retries: %w", reqURL, retries, reqErr)
	}

	// 清理 BOM
	respBody = bytes.TrimPrefix(respBody, []byte("\xef\xbb\xbf"))
	trimmed := bytes.TrimSpace(respBody)

	// 智能多格式分流解析
	// 1. 如果明确指定为 xml / rss，或者响应以 '<' 开头，使用 XML/RSS 解析器
	if protoType == "xml" || protoType == "maccms_xml" || protoType == "rss" || protoType == "rss_feed" || (len(trimmed) > 0 && trimmed[0] == '<') {
		xmlResp, xmlErr := ParseXmlResponse(trimmed)
		if xmlErr == nil {
			return xmlResp, nil
		}
		// 如果 XML 解析失败但内容不是以 '<' 开头，继续尝试 JSON
		if len(trimmed) > 0 && trimmed[0] == '<' {
			return nil, fmt.Errorf("xml/rss parse failed: %w", xmlErr)
		}
	}

	// 2. 如果指定为自定义 JSON 映射
	mapping := c.cfg.CustomMapping
	if mapping.ListPath == "" && c.cfg.Filter.CustomMapping != nil {
		mapping = *c.cfg.Filter.CustomMapping
	}
	if protoType == "custom_json" {
		return ParseCustomJsonResponse(trimmed, mapping)
	}

	// 3. 默认 MacCMS JSON 解析
	var cmsResp MacCmsResponse
	if err := json.Unmarshal(trimmed, &cmsResp); err != nil {
		// 回退尝试自定义 JSON 解析器 (针对某些非标准但类似 JSON 的返回)
		if customResp, cErr := ParseCustomJsonResponse(trimmed, mapping); cErr == nil && len(customResp.List) > 0 {
			return customResp, nil
		}
		return nil, fmt.Errorf("unmarshal json response failed: %w, raw response: %s", err, string(trimmed))
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
	u, err := url.Parse(c.cfg.API)
	if err != nil {
		return "", fmt.Errorf("invalid api url: %w", err)
	}

	protoType := strings.ToLower(strings.TrimSpace(c.cfg.Type))
	q := u.Query()

	// 针对 RSS 订阅源，通常 API 地址即完整 Feed URL，不需要强加 MacCMS 参数
	if protoType == "rss" || protoType == "rss_feed" {
		// 附加自定义 Query 参数
		c.appendCustomParams(&q)
		u.RawQuery = q.Encode()
		return u.String(), nil
	}

	action := params.Action
	if action == "" {
		if protoType == "xml" || protoType == "maccms_xml" {
			action = "videolist"
		} else {
			action = "detail"
		}
	}
	q.Set("ac", action)

	if params.Page > 0 {
		q.Set("pg", strconv.Itoa(params.Page))
	}

	if params.TypeID > 0 {
		q.Set("t", strconv.Itoa(params.TypeID))
	}

	// 仅在非全量模式且有 hours 时添加 h 参数
	if !params.IsAll {
		hours := params.Hours
		if hours == 0 && c.cfg.CollectHours > 0 {
			hours = c.cfg.CollectHours
		}
		if hours > 0 {
			q.Set("h", strconv.Itoa(hours))
		}
	}

	if params.WD != "" {
		q.Set("wd", params.WD)
	}

	if params.IDs != "" {
		q.Set("ids", params.IDs)
	}

	// 针对 MacCMS JSON 格式强制参数
	if protoType == "json" || protoType == "maccms_json" || protoType == "" {
		q.Set("out", "json")
	}

	// 注入自定义 URL Query 参数 (如 token=xxx)
	c.appendCustomParams(&q)

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
