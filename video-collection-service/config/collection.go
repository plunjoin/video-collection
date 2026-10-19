package config

import (
	_ "embed"
	"fmt"
	"net/url"
	"os"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// CollectionRule is saved with each source. Templates are copied on selection,
// so changing a template never silently changes an existing source.
type CollectionRule struct {
	Version int               `json:"version" yaml:"version"`
	Format  string            `json:"format" yaml:"format"`
	Method  string            `json:"method" yaml:"method"`
	Body    string            `json:"body" yaml:"body"`
	Query   map[string]string `json:"query" yaml:"query"`
	Mapping CustomMapping     `json:"mapping" yaml:"mapping"`
}

type CollectionTemplate struct {
	ID          string         `json:"id" yaml:"id"`
	Name        string         `json:"name" yaml:"name"`
	Description string         `json:"description" yaml:"description"`
	Aliases     []string       `json:"aliases" yaml:"aliases"`
	Rule        CollectionRule `json:"rule" yaml:"rule"`
}

//go:embed collection_templates.yaml
var defaultTemplates []byte

// LoadCollectionTemplates reloads the external file on each request. An explicit
// path must exist; a missing default file uses the bundled YAML definitions.
func LoadCollectionTemplates() ([]CollectionTemplate, error) {
	path := os.Getenv("COLLECTION_TEMPLATES_PATH")
	explicit := path != ""
	if !explicit {
		path = "config/collection_templates.yaml"
	}
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) && !explicit {
		data, err = defaultTemplates, nil
	}
	if err != nil {
		return nil, err
	}
	var templates []CollectionTemplate
	if err := yaml.Unmarshal(data, &templates); err != nil {
		return nil, err
	}
	seen := map[string]bool{}
	for _, t := range templates {
		if t.ID == "" || t.Name == "" || seen[t.ID] {
			return nil, fmt.Errorf("规则模板 ID / 名称为空或 ID 重复")
		}
		seen[t.ID] = true
		if err := ValidateCollectionRule(t.Rule); err != nil {
			return nil, fmt.Errorf("模板 %s: %w", t.ID, err)
		}
	}
	return templates, nil
}

func ResolveCollectionRule(src SourceConfig) (*CollectionRule, error) {
	if src.Filter.Collector != nil {
		return src.Filter.Collector, ValidateCollectionRule(*src.Filter.Collector)
	}
	templates, err := LoadCollectionTemplates()
	if err != nil {
		return nil, err
	}
	kind := strings.ToLower(strings.TrimSpace(src.Type))
	if kind == "" {
		kind = "json"
	} // compatibility with saved sources
	for _, t := range templates {
		for _, alias := range t.Aliases {
			if alias == kind {
				rule := t.Rule
				if rule.Format == "custom_json" {
					if src.CustomMapping != (CustomMapping{}) {
						rule.Mapping = src.CustomMapping
					} else if src.Filter.CustomMapping != nil && *src.Filter.CustomMapping != (CustomMapping{}) {
						rule.Mapping = *src.Filter.CustomMapping
					}
				}
				return &rule, nil
			}
		}
	}
	return nil, fmt.Errorf("未知采集类型 %q，请选择或配置采集规则", src.Type)
}

func ValidateCollectionRule(rule CollectionRule) error {
	if rule.Version != 1 {
		return fmt.Errorf("采集规则 version 必须为 1")
	}
	switch rule.Format {
	case "video_json", "standard_json", "maccms_json", "json", "video_xml", "standard_xml", "maccms_xml", "xml", "rss", "rss_feed", "custom_json":
	default:
		return fmt.Errorf("不支持的响应格式 %q", rule.Format)
	}
	if rule.Method != "GET" && rule.Method != "POST" {
		return fmt.Errorf("请求方法须为 GET 或 POST")
	}
	for key, value := range rule.Query {
		if strings.TrimSpace(key) == "" {
			return fmt.Errorf("请求参数名称不能为空")
		}
		for _, token := range []string{"{page}", "{hours}", "{action}", "{type_id}", "{keyword}", "{ids}"} {
			value = strings.ReplaceAll(value, token, "")
		}
		if strings.ContainsAny(value, "{}") {
			return fmt.Errorf("未知参数变量: %s", key)
		}
	}
	return nil
}

// ParseWebhookSecretExpiry 解析 custom_params.webhook_secret_expires_at。
// 支持 RFC3339 / RFC3339Nano，以及常见的 "2006-01-02 15:04:05"、"2006-01-02T15:04:05"、纯日期 "2006-01-02"（按当日结束 UTC）。
func ParseWebhookSecretExpiry(raw string) (time.Time, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return time.Time{}, fmt.Errorf("为空")
	}
	layouts := []string{
		time.RFC3339Nano,
		time.RFC3339,
		"2006-01-02T15:04:05Z07:00",
		"2006-01-02T15:04:05",
		"2006-01-02 15:04:05",
		"2006-01-02",
	}
	var lastErr error
	for _, layout := range layouts {
		t, err := time.Parse(layout, raw)
		if err == nil {
			if layout == "2006-01-02" {
				// 纯日期：视为当天 23:59:59 UTC
				t = t.Add(24*time.Hour - time.Second)
			}
			return t, nil
		}
		lastErr = err
	}
	return time.Time{}, lastErr
}

// IsWebhookSource 判断是否为推送型 Webhook 采集源（不主动拉取）。
func IsWebhookSource(src SourceConfig) bool {
	kind := strings.ToLower(strings.TrimSpace(src.Type))
	api := strings.ToLower(strings.TrimSpace(src.API))
	return kind == "webhook" || strings.HasPrefix(api, "webhook://")
}

func ValidateCollectionSource(src SourceConfig) error {
	if IsWebhookSource(src) {
		api := strings.TrimSpace(src.API)
		if api == "" {
			return fmt.Errorf("Webhook 源请填写 api，例如 webhook://collector")
		}
		u, err := url.Parse(api)
		if err != nil || u.Scheme != "webhook" {
			return fmt.Errorf("Webhook 源 api 须为 webhook://... 形式")
		}
		if src.CustomParams != nil {
			if exp := strings.TrimSpace(src.CustomParams["webhook_secret_expires_at"]); exp != "" {
				if _, err := ParseWebhookSecretExpiry(exp); err != nil {
					return fmt.Errorf("webhook_secret_expires_at 无效: %w", err)
				}
			}
		}
		return nil
	}
	u, err := url.Parse(src.API)
	if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") || u.User != nil {
		return fmt.Errorf("请输入不含用户名密码的 HTTP(S) 地址")
	}
	if src.CollectHours < 0 || src.PageLimit < 0 || src.PageLimit > 10000 || src.TimeoutSec < 0 || src.TimeoutSec > 60 || src.RetryCount < 0 || src.RetryCount > 3 || src.IntervalMs < 0 || src.IntervalMs > 10000 {
		return fmt.Errorf("采集范围或请求限制无效")
	}
	_, err = ResolveCollectionRule(src)
	return err
}
