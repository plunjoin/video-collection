package integration

import (
	"context"
	"strings"
	"testing"
)

// memStore 内存版 settings 存储，用于验证读写与脱敏。
type memStore struct {
	values map[string]string
}

func (m *memStore) GetAllSettings(context.Context) (map[string]string, error) {
	out := make(map[string]string, len(m.values))
	for k, v := range m.values {
		out[k] = v
	}
	return out, nil
}

func (m *memStore) SetSettings(_ context.Context, values map[string]string) error {
	for k, v := range values {
		m.values[k] = v
	}
	return nil
}

func TestSaveKeepsExistingSecrets(t *testing.T) {
	store := &memStore{values: map[string]string{}}
	ctx := context.Background()

	if err := Save(ctx, store, Config{
		Mail:    Mail{Enabled: true, Host: "smtp.example.com", Port: "465", From: "a@b.com", Pass: "s3cret", Encryption: "ssl"},
		Storage: Storage{Provider: "oss", Endpoint: "https://oss-cn-hangzhou.aliyuncs.com", Bucket: "b", AccessKey: "ak", SecretKey: "sk"},
	}); err != nil {
		t.Fatal(err)
	}

	// 前端回传的是脱敏值（密钥为空），保存后不应把密钥清空
	if err := Save(ctx, store, Config{
		Mail:    Mail{Enabled: true, Host: "smtp2.example.com", Port: "465", From: "a@b.com", Pass: "", Encryption: "ssl"},
		Storage: Storage{Provider: "oss", Endpoint: "https://oss-cn-hangzhou.aliyuncs.com", Bucket: "b", AccessKey: "ak", SecretKey: ""},
	}); err != nil {
		t.Fatal(err)
	}

	cfg := Load(ctx, store)
	if cfg.Mail.Pass != "s3cret" {
		t.Fatalf("邮箱密码应保持原值，实际 %q", cfg.Mail.Pass)
	}
	if cfg.Storage.SecretKey != "sk" {
		t.Fatalf("存储密钥应保持原值，实际 %q", cfg.Storage.SecretKey)
	}
	if cfg.Mail.Host != "smtp2.example.com" {
		t.Fatalf("非密钥字段应更新，实际 %q", cfg.Mail.Host)
	}
}

func TestMaskedHidesSecrets(t *testing.T) {
	cfg := Config{
		Mail:    Mail{Enabled: true, Host: "h", From: "f", Pass: "topsecret"},
		SMS:     SMS{Enabled: true, Provider: "webhook", WebhookURL: "https://x", Token: "tok"},
		Storage: Storage{Provider: "oss", Endpoint: "e", Bucket: "b", AccessKey: "ak", SecretKey: "sk"},
	}
	masked := cfg.Masked()

	mail := masked["mail"].(map[string]any)
	if mail["pass"] != "" || mail["pass_set"] != true {
		t.Fatalf("邮件密码应脱敏但保留已配置标记: %v", mail)
	}
	sms := masked["sms"].(map[string]any)
	if sms["token"] != "" || sms["token_set"] != true {
		t.Fatalf("短信令牌应脱敏: %v", sms)
	}
	storage := masked["storage"].(map[string]any)
	if storage["secret_key"] != "" || storage["secret_set"] != true {
		t.Fatalf("存储密钥应脱敏: %v", storage)
	}
	// AccessKey 不是密钥，保留明文方便核对
	if storage["access_key"] != "ak" {
		t.Fatalf("AccessKey 应明文返回: %v", storage["access_key"])
	}
}

func TestDefaultsApplied(t *testing.T) {
	store := &memStore{values: map[string]string{}}
	cfg := Load(context.Background(), store)

	if cfg.Mail.Template.Subject != DefaultMailSubject {
		t.Fatalf("默认邮件标题未生效: %q", cfg.Mail.Template.Subject)
	}
	if cfg.SMS.Template != DefaultSMSTemplate {
		t.Fatalf("默认短信模板未生效: %q", cfg.SMS.Template)
	}
	if cfg.Storage.Provider != "local" {
		t.Fatalf("默认存储应为 local，实际 %q", cfg.Storage.Provider)
	}
	if cfg.Mail.Configured() {
		t.Fatal("未填写 host 时邮件通道不应视为可用")
	}
	if !cfg.Storage.Configured() {
		t.Fatal("local 存储应恒为可用")
	}
}

func TestStoragePrefixNormalized(t *testing.T) {
	cases := map[string]string{
		"":          "",
		"/":         "",
		"uploads":   "uploads/",
		"/uploads/": "uploads/",
		"a/b":       "a/b/",
	}
	for input, want := range cases {
		if got := (Storage{Prefix: input}).NormalizedPrefix(); got != want {
			t.Errorf("prefix %q => %q, 期望 %q", input, got, want)
		}
	}
}

func TestParsePort(t *testing.T) {
	if got := ParsePort("465", 587); got != 465 {
		t.Fatalf("合法端口解析错误: %d", got)
	}
	for _, bad := range []string{"", "0", "-1", "70000", "abc"} {
		if got := ParsePort(bad, 587); got != 587 {
			t.Errorf("非法端口 %q 应回落到 587，实际 %d", bad, got)
		}
	}
	if !strings.Contains(DefaultMailBody, "{{code}}") {
		t.Fatal("默认邮件正文应包含验证码占位符")
	}
}
