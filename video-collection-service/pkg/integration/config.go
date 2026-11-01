// Package integration 集中管理「外部服务接入」配置：邮件、短信、对象存储。
//
// 配置全部落在 settings 表（key 前缀 integration_），因此可在后台页面修改、
// 无需重启；环境变量仅作为首次部署的兜底默认值。
package integration

import (
	"context"
	"os"
	"strconv"
	"strings"
)

// SettingsReader 配置中心只需要读全量设置。
type SettingsReader interface {
	GetAllSettings(ctx context.Context) (map[string]string, error)
}

// SettingsWriter 保存配置。
type SettingsWriter interface {
	SetSettings(ctx context.Context, settings map[string]string) error
}

// MailTemplate 邮件正文模板，支持 {{site}} / {{code}} / {{purpose}} / {{expires}} 占位符。
type MailTemplate struct {
	Subject string `json:"subject"`
	Body    string `json:"body"`
}

// Mail SMTP 邮件通道配置。
type Mail struct {
	Enabled    bool         `json:"enabled"`
	Host       string       `json:"host"`
	Port       string       `json:"port"`
	User       string       `json:"user"`
	Pass       string       `json:"pass"`
	From       string       `json:"from"`
	FromName   string       `json:"from_name"`
	Encryption string       `json:"encryption"` // ssl | starttls | none
	Template   MailTemplate `json:"template"`
}

// SMS 短信通道配置。provider 目前支持 webhook（POST JSON 到自建网关）。
type SMS struct {
	Enabled    bool   `json:"enabled"`
	Provider   string `json:"provider"` // webhook | none
	WebhookURL string `json:"webhook_url"`
	Token      string `json:"token"` // 以 Authorization: Bearer 发送
	Template   string `json:"template"`
}

// Storage 对象存储配置。provider 支持 local（服务端磁盘）与 s3（S3 兼容协议）。
type Storage struct {
	Provider  string `json:"provider"` // local | s3
	Endpoint  string `json:"endpoint"` // 如 https://oss-cn-hangzhou.aliyuncs.com
	Region    string `json:"region"`   // 如 cn-hangzhou；部分服务可留空
	Bucket    string `json:"bucket"`
	AccessKey string `json:"access_key"`
	SecretKey string `json:"secret_key"`
	Domain    string `json:"domain"`     // 自定义加速域名，留空则拼 endpoint/bucket
	Prefix    string `json:"prefix"`     // 对象键前缀，如 bllii/
	PathStyle bool   `json:"path_style"` // true 走 endpoint/bucket/key，false 走 bucket.endpoint/key
}

// Config 全部接入配置。
type Config struct {
	Mail    Mail    `json:"mail"`
	SMS     SMS     `json:"sms"`
	Storage Storage `json:"storage"`
}

// 默认邮件模板。
const (
	DefaultMailSubject = "{{site}} {{purpose}}验证码"
	DefaultMailBody    = "您好：\r\n\r\n您正在进行{{purpose}}操作，验证码为 {{code}}，{{expires}} 分钟内有效。\r\n如非本人操作，请忽略本邮件并及时修改密码。\r\n\r\n—— {{site}}"
	DefaultSMSTemplate = "您正在进行{{purpose}}操作，验证码 {{code}}，{{expires}} 分钟内有效。"
)

const keyPrefix = "integration_"

func key(name string) string { return keyPrefix + name }

// Load 从 settings 表读取配置，缺失项用环境变量兜底（便于老部署平滑迁移）。
func Load(ctx context.Context, r SettingsReader) Config {
	settings, _ := r.GetAllSettings(ctx)
	if settings == nil {
		settings = map[string]string{}
	}
	get := func(name, fallback string) string {
		if v, ok := settings[key(name)]; ok && strings.TrimSpace(v) != "" {
			return v
		}
		return fallback
	}
	getBool := func(name string, fallback bool) bool {
		v, ok := settings[key(name)]
		if !ok {
			return fallback
		}
		return v == "1" || strings.EqualFold(v, "true")
	}

	cfg := Config{
		Mail: Mail{
			Enabled:    getBool("mail_enabled", false),
			Host:       get("mail_host", Env("SMTP_HOST")),
			Port:       get("mail_port", EnvDefault("SMTP_PORT", "587")),
			User:       get("mail_user", Env("SMTP_USER")),
			Pass:       get("mail_pass", Env("SMTP_PASS")),
			From:       get("mail_from", Env("SMTP_FROM")),
			FromName:   get("mail_from_name", EnvDefault("SITE_NAME", "")),
			Encryption: get("mail_encryption", EnvDefault("SMTP_ENCRYPTION", "starttls")),
			Template: MailTemplate{
				Subject: get("mail_subject", DefaultMailSubject),
				Body:    get("mail_body", DefaultMailBody),
			},
		},
		SMS: SMS{
			Enabled:    getBool("sms_enabled", false),
			Provider:   get("sms_provider", EnvDefault("SMS_PROVIDER", "webhook")),
			WebhookURL: get("sms_webhook_url", Env("SMS_WEBHOOK_URL")),
			Token:      get("sms_token", Env("SMS_TOKEN")),
			Template:   get("sms_template", DefaultSMSTemplate),
		},
		Storage: Storage{
			Provider:  get("storage_provider", EnvDefault("STORAGE_PROVIDER", "local")),
			Endpoint:  get("storage_endpoint", Env("OSS_ENDPOINT")),
			Region:    get("storage_region", Env("OSS_REGION")),
			Bucket:    get("storage_bucket", Env("OSS_BUCKET")),
			AccessKey: get("storage_access_key", Env("OSS_ACCESS_KEY")),
			SecretKey: get("storage_secret_key", Env("OSS_SECRET_KEY")),
			Domain:    get("storage_domain", Env("OSS_DOMAIN")),
			Prefix:    get("storage_prefix", "uploads/"),
			PathStyle: getBool("storage_path_style", true),
		},
	}
	if cfg.Mail.Encryption == "" {
		cfg.Mail.Encryption = "starttls"
	}
	if cfg.Storage.Provider == "" {
		cfg.Storage.Provider = "local"
	}
	return cfg
}

// Masked 返回可安全下发给前端的副本：密钥字段只保留「是否已配置」。
func (c Config) Masked() map[string]any {
	mail := c.Mail
	sms := c.SMS
	storage := c.Storage

	out := map[string]any{
		"mail": map[string]any{
			"enabled":    mail.Enabled,
			"host":       mail.Host,
			"port":       mail.Port,
			"user":       mail.User,
			"pass":       "",
			"pass_set":   mail.Pass != "",
			"from":       mail.From,
			"from_name":  mail.FromName,
			"encryption": mail.Encryption,
			"configured": mail.Configured(),
			"template":   mail.Template,
		},
		"sms": map[string]any{
			"enabled":     sms.Enabled,
			"provider":    sms.Provider,
			"webhook_url": sms.WebhookURL,
			"token":       "",
			"token_set":   sms.Token != "",
			"template":    sms.Template,
			"configured":  sms.Configured(),
		},
		"storage": map[string]any{
			"provider":   storage.Provider,
			"endpoint":   storage.Endpoint,
			"region":     storage.Region,
			"bucket":     storage.Bucket,
			"access_key": storage.AccessKey,
			"secret_key": "",
			"secret_set": storage.SecretKey != "",
			"domain":     storage.Domain,
			"prefix":     storage.Prefix,
			"path_style": storage.PathStyle,
			"configured": storage.Configured(),
		},
	}
	return out
}

// Configured 判断邮件通道是否可用。
func (m Mail) Configured() bool {
	return m.Enabled && m.Host != "" && m.From != ""
}

// Configured 判断短信通道是否可用。
func (s SMS) Configured() bool {
	return s.Enabled && s.Provider != "" && s.Provider != "none" && s.WebhookURL != ""
}

// Configured 判断存储是否可用；local 恒可用。
func (s Storage) Configured() bool {
	if s.Provider == "" || s.Provider == "local" {
		return true
	}
	return s.Endpoint != "" && s.Bucket != "" && s.AccessKey != "" && s.SecretKey != ""
}

// NormalizedPrefix 返回不带前导斜杠、以 / 结尾的对象键前缀。
func (s Storage) NormalizedPrefix() string {
	p := strings.TrimSpace(s.Prefix)
	p = strings.TrimPrefix(p, "/")
	if p != "" && !strings.HasSuffix(p, "/") {
		p += "/"
	}
	return p
}

// Save 把前端提交的配置写回 settings。密钥字段为空表示「保持原值」，
// 避免前端拿到脱敏值后一保存就把密钥清空。
func Save(ctx context.Context, w SettingsWriter, incoming Config) error {
	current := Config{}
	if reader, ok := w.(SettingsReader); ok {
		current = Load(ctx, reader)
	}

	pass := strings.TrimSpace(incoming.Mail.Pass)
	if pass == "" {
		pass = current.Mail.Pass
	}
	smsToken := strings.TrimSpace(incoming.SMS.Token)
	if smsToken == "" {
		smsToken = current.SMS.Token
	}
	secret := strings.TrimSpace(incoming.Storage.SecretKey)
	if secret == "" {
		secret = current.Storage.SecretKey
	}

	subject := strings.TrimSpace(incoming.Mail.Template.Subject)
	if subject == "" {
		subject = DefaultMailSubject
	}
	body := strings.TrimSpace(incoming.Mail.Template.Body)
	if body == "" {
		body = DefaultMailBody
	}
	smsTpl := strings.TrimSpace(incoming.SMS.Template)
	if smsTpl == "" {
		smsTpl = DefaultSMSTemplate
	}
	encryption := strings.TrimSpace(incoming.Mail.Encryption)
	if encryption == "" {
		encryption = "starttls"
	}
	provider := strings.TrimSpace(incoming.Storage.Provider)
	if provider == "" {
		provider = "local"
	}

	values := map[string]string{
		key("mail_enabled"):       boolString(incoming.Mail.Enabled),
		key("mail_host"):          strings.TrimSpace(incoming.Mail.Host),
		key("mail_port"):          strings.TrimSpace(incoming.Mail.Port),
		key("mail_user"):          strings.TrimSpace(incoming.Mail.User),
		key("mail_pass"):          pass,
		key("mail_from"):          strings.TrimSpace(incoming.Mail.From),
		key("mail_from_name"):     strings.TrimSpace(incoming.Mail.FromName),
		key("mail_encryption"):    encryption,
		key("mail_subject"):       subject,
		key("mail_body"):          body,
		key("sms_enabled"):        boolString(incoming.SMS.Enabled),
		key("sms_provider"):       strings.TrimSpace(incoming.SMS.Provider),
		key("sms_webhook_url"):    strings.TrimSpace(incoming.SMS.WebhookURL),
		key("sms_token"):          smsToken,
		key("sms_template"):       smsTpl,
		key("storage_provider"):   provider,
		key("storage_endpoint"):   strings.TrimSpace(incoming.Storage.Endpoint),
		key("storage_region"):     strings.TrimSpace(incoming.Storage.Region),
		key("storage_bucket"):     strings.TrimSpace(incoming.Storage.Bucket),
		key("storage_access_key"): strings.TrimSpace(incoming.Storage.AccessKey),
		key("storage_secret_key"): secret,
		key("storage_domain"):     strings.TrimSpace(incoming.Storage.Domain),
		key("storage_prefix"):     strings.TrimSpace(incoming.Storage.Prefix),
		key("storage_path_style"): boolString(incoming.Storage.PathStyle),
	}
	return w.SetSettings(ctx, values)
}

func boolString(v bool) string {
	if v {
		return "1"
	}
	return "0"
}

// Env 读取环境变量（空串表示未设置）。
func Env(name string) string { return strings.TrimSpace(os.Getenv(name)) }

// EnvDefault 读取环境变量并提供默认值。
func EnvDefault(name, fallback string) string {
	if v := Env(name); v != "" {
		return v
	}
	return fallback
}

// ParsePort 把端口字符串转成整数，非法时返回默认值。
func ParsePort(raw string, fallback int) int {
	if n, err := strconv.Atoi(strings.TrimSpace(raw)); err == nil && n > 0 && n < 65536 {
		return n
	}
	return fallback
}
