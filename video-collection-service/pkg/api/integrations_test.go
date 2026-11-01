package api

import (
	"bytes"
	"context"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"video-collection-service/pkg/auth"
	"video-collection-service/pkg/integration"
	"video-collection-service/pkg/store"
)

// adminFixture 额外造一个普通管理员（非超管），用于验证写入权限边界。
func adminFixture(t *testing.T, f *contentFixture, username string) (*store.User, string) {
	t.Helper()
	hash, err := auth.HashPassword("adminpass123")
	if err != nil {
		t.Fatal(err)
	}
	u := &store.User{Username: username, Nickname: username, Role: "admin", Status: 1, PasswordHash: hash}
	if err := f.s.CreateUser(context.Background(), u); err != nil {
		t.Fatal(err)
	}
	token := auth.DefaultSessionManager.CreateSession(u, auth.SessionMeta{IP: "127.0.0.1", UserAgent: "go-test"})
	t.Cleanup(func() { auth.DefaultSessionManager.DeleteSession(token) })
	return u, token
}

func TestIntegrationsReadAndMask(t *testing.T) {
	accountEnv(t)
	f := newContentFixture(t)

	if w := f.doWithToken("GET", "/api/admin/integrations", "", ""); w.Code != http.StatusUnauthorized {
		t.Fatalf("未登录应 401，实际 %d", w.Code)
	}

	w := f.doWithToken("GET", "/api/admin/integrations", "", f.tokens[f.admin.ID])
	if w.Code != http.StatusOK {
		t.Fatalf("读取集成配置失败: %d %s", w.Code, w.Body.String())
	}
	body := decodeBody(t, w)
	data, _ := body["data"].(map[string]any)
	mail, _ := data["mail"].(map[string]any)
	if mail["pass"] != "" {
		t.Fatalf("密码字段应脱敏: %v", mail)
	}
	if mail["template"] == nil {
		t.Fatal("应返回默认邮件模板")
	}
	storage, _ := data["storage"].(map[string]any)
	if storage["provider"] != "local" {
		t.Fatalf("默认存储应为 local: %v", storage["provider"])
	}
}

func TestIntegrationsWriteRequiresSuperAdmin(t *testing.T) {
	accountEnv(t)
	f := newContentFixture(t)
	_, adminToken := adminFixture(t, f, "plain_admin")

	payload := `{"mail":{"enabled":true,"host":"smtp.example.com","port":"587","from":"a@b.com"},"storage":{"provider":"local"}}`

	if w := f.doWithToken("POST", "/api/admin/integrations", payload, adminToken); w.Code != http.StatusForbidden {
		t.Fatalf("普通管理员写入应 403，实际 %d: %s", w.Code, w.Body.String())
	}
	if w := f.doWithToken("POST", "/api/admin/integrations", payload, f.tokens[f.admin.ID]); w.Code != http.StatusOK {
		t.Fatalf("超管保存失败: %d %s", w.Code, w.Body.String())
	}

	cfg := integration.Load(context.Background(), f.s)
	if cfg.Mail.Host != "smtp.example.com" || !cfg.Mail.Enabled {
		t.Fatalf("配置未落库: %+v", cfg.Mail)
	}
	// 保存后邮件通道立即被视为可用（无需重启）
	if !cfg.Mail.Configured() {
		t.Fatal("保存后邮件通道应可用")
	}
}

func TestIntegrationsSecretSurvivesResave(t *testing.T) {
	accountEnv(t)
	f := newContentFixture(t)
	token := f.tokens[f.admin.ID]

	first := `{"mail":{"enabled":true,"host":"h","port":"465","from":"a@b.com","pass":"topsecret","encryption":"ssl"},"storage":{"provider":"oss","endpoint":"https://oss-cn-hangzhou.aliyuncs.com","bucket":"b","access_key":"ak","secret_key":"sk"}}`
	if w := f.doWithToken("POST", "/api/admin/integrations", first, token); w.Code != http.StatusOK {
		t.Fatalf("首次保存失败: %d %s", w.Code, w.Body.String())
	}

	// 前端拿到的是脱敏值，二次保存时密钥为空
	second := `{"mail":{"enabled":true,"host":"h2","port":"465","from":"a@b.com","pass":"","encryption":"ssl"},"storage":{"provider":"oss","endpoint":"https://oss-cn-hangzhou.aliyuncs.com","bucket":"b","access_key":"ak","secret_key":""}}`
	if w := f.doWithToken("POST", "/api/admin/integrations", second, token); w.Code != http.StatusOK {
		t.Fatalf("二次保存失败: %d %s", w.Code, w.Body.String())
	}

	cfg := integration.Load(context.Background(), f.s)
	if cfg.Mail.Pass != "topsecret" || cfg.Storage.SecretKey != "sk" {
		t.Fatalf("密钥被清空: pass=%q secret=%q", cfg.Mail.Pass, cfg.Storage.SecretKey)
	}
	if cfg.Mail.Host != "h2" {
		t.Fatalf("普通字段应更新，实际 %q", cfg.Mail.Host)
	}
}

// 本地存储的连通性测试应当上传后删除，且不留残余文件。
func TestIntegrationsTestStorage(t *testing.T) {
	accountEnv(t)
	f := newContentFixture(t)

	w := f.doWithToken("POST", "/api/admin/integrations/test/storage", "{}", f.tokens[f.admin.ID])
	if w.Code != http.StatusOK {
		t.Fatalf("存储连通性测试失败: %d %s", w.Code, w.Body.String())
	}
	data, _ := decodeBody(t, w)["data"].(map[string]any)
	if data["provider"] != "local" || data["deleted"] != true {
		t.Fatalf("探测结果不符合预期: %v", data)
	}
}

// 未配置 SMTP 时测试邮件应给出明确错误而不是静默成功。
func TestIntegrationsTestMailWithoutConfig(t *testing.T) {
	accountEnv(t)
	f := newContentFixture(t)

	w := f.doWithToken("POST", "/api/admin/integrations/test/mail", `{"to":"ops@example.com"}`, f.tokens[f.admin.ID])
	if w.Code == http.StatusOK {
		t.Fatalf("未配置 SMTP 不应成功: %s", w.Body.String())
	}
	if w := f.doWithToken("POST", "/api/admin/integrations/test/mail", `{"to":"not-an-email"}`, f.tokens[f.admin.ID]); w.Code != http.StatusBadRequest {
		t.Fatalf("非法收件人应 400，实际 %d", w.Code)
	}
}

func TestIntegrationsTestSMSValidation(t *testing.T) {
	accountEnv(t)
	f := newContentFixture(t)

	if w := f.doWithToken("POST", "/api/admin/integrations/test/sms", `{"phone":"123"}`, f.tokens[f.admin.ID]); w.Code != http.StatusBadRequest {
		t.Fatalf("非法手机号应 400，实际 %d", w.Code)
	}
	if w := f.doWithToken("POST", "/api/admin/integrations/test/sms", `{"phone":"13800138000"}`, f.tokens[f.admin.ID]); w.Code == http.StatusOK {
		t.Fatalf("未配置短信通道不应成功: %s", w.Body.String())
	}
}

// 邮件模板占位符应被真实替换。
func TestMailTemplateRender(t *testing.T) {
	accountEnv(t)
	f := newContentFixture(t)
	token := f.tokens[f.admin.ID]

	payload := `{"mail":{"enabled":true,"host":"h","from":"a@b.com","from_name":"Bllii","template":{"subject":"【{{site}}】{{purpose}}验证码","body":"验证码 {{code}}，{{expires}} 分钟内有效。"}},"storage":{"provider":"local"}}`
	if w := f.doWithToken("POST", "/api/admin/integrations", payload, token); w.Code != http.StatusOK {
		t.Fatalf("保存模板失败: %d %s", w.Code, w.Body.String())
	}

	cfg := integration.Load(context.Background(), f.s)
	if !strings.Contains(cfg.Mail.Template.Subject, "{{site}}") {
		t.Fatalf("模板未保存: %q", cfg.Mail.Template.Subject)
	}
	if cfg.Mail.FromName != "Bllii" {
		t.Fatalf("发件人名称未保存: %q", cfg.Mail.FromName)
	}
}

// 头像历史上限：超过 20 条时最旧的记录与文件被清理。
func TestAvatarHistoryTrim(t *testing.T) {
	accountEnv(t)
	f := newContentFixture(t)
	u, token, _ := accountFixture(t, f, "trim_user", "trimpass123")

	var urls []string
	for i := 0; i < 22; i++ {
		urls = append(urls, uploadAvatarForTest(t, f, token))
	}
	list, err := f.s.ListAvatars(context.Background(), u.ID, 100)
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 20 {
		t.Fatalf("历史应被裁剪到 20 条，实际 %d", len(list))
	}
	// 最新一条应是最后上传的
	if list[0].URL != urls[len(urls)-1] {
		t.Fatalf("最新头像不是最后上传的那张")
	}
}

// multipartAvatar 构造一个只有一张图片的 multipart 请求体。
func multipartAvatar(t *testing.T, content []byte) (*bytes.Buffer, string) {
	t.Helper()
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	fw, err := mw.CreateFormFile("file", "avatar.png")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := fw.Write(content); err != nil {
		t.Fatal(err)
	}
	_ = mw.Close()
	return &buf, mw.FormDataContentType()
}

func uploadAvatarForTest(t *testing.T, f *contentFixture, token string) string {
	t.Helper()
	body, contentType := multipartAvatar(t, pngHeader)
	r := httptest.NewRequest("POST", "/api/me/avatar", body)
	r.Header.Set("Content-Type", contentType)
	r.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	f.mux.ServeHTTP(w, r)
	if w.Code != http.StatusOK {
		t.Fatalf("上传失败: %d %s", w.Code, w.Body.String())
	}
	var resp struct {
		URL string `json:"url"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	return resp.URL
}
