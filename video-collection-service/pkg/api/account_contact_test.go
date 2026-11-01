package api

import (
	"bytes"
	"context"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"video-collection-service/pkg/auth"
	"video-collection-service/pkg/store"
)

// pngHeader 是一段足够让 http.DetectContentType 识别为 image/png 的最小前缀。
var pngHeader = []byte{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D}

// accountEnv 开启验证码联调模式，并把上传目录指到临时目录。
func accountEnv(t *testing.T) {
	t.Helper()
	t.Setenv("ACCOUNT_DEV_CODE", "1")
	t.Setenv("UPLOAD_DIR", t.TempDir())
}

// sendCode 触发发送验证码并取回 dev_code。
func sendCode(t *testing.T, f *contentFixture, token, channel, target, purpose string) string {
	t.Helper()
	body := `{"channel":"` + channel + `","target":"` + target + `","purpose":"` + purpose + `"}`
	w := f.doWithToken("POST", "/api/auth/send-code", body, token)
	if w.Code != http.StatusOK {
		t.Fatalf("发送验证码失败: %d %s", w.Code, w.Body.String())
	}
	var resp struct {
		DevCode string `json:"dev_code"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if len(resp.DevCode) != 6 {
		t.Fatalf("联调模式应返回 6 位验证码，实际 %q (%s)", resp.DevCode, w.Body.String())
	}
	return resp.DevCode
}

func decodeBody(t *testing.T, w *httptest.ResponseRecorder) map[string]any {
	t.Helper()
	var out map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil {
		t.Fatalf("响应不是合法 JSON: %v (%s)", err, w.Body.String())
	}
	return out
}

// 未开启联调模式且未配置通道时，发送验证码应直接提示通道缺失，而不是静默失败。
func TestSendCodeWithoutChannel(t *testing.T) {
	t.Setenv("ACCOUNT_DEV_CODE", "")
	t.Setenv("SMTP_HOST", "")
	t.Setenv("SMS_WEBHOOK_URL", "")
	f := newContentFixture(t)

	w := f.doWithToken("POST", "/api/auth/send-code", `{"channel":"email","target":"a@b.com","purpose":"reset"}`, "")
	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("未配置通道应返回 503，实际 %d: %s", w.Code, w.Body.String())
	}
}

// 邮箱绑定 → 读取 → 解绑，覆盖鉴权、验证码与密码二次确认。
func TestBindEmailFlow(t *testing.T) {
	accountEnv(t)
	f := newContentFixture(t)
	_, token, _ := accountFixture(t, f, "bind_user", "bindpass123")

	// 未登录不能绑定
	if w := f.doWithToken("POST", "/api/me/contact/bind", `{"channel":"email","target":"x@y.com","code":"123456"}`, ""); w.Code != http.StatusUnauthorized {
		t.Fatalf("未登录绑定应返回 401，实际 %d", w.Code)
	}

	code := sendCode(t, f, token, "email", "  Bind@Example.COM ", "bind")
	if w := f.doWithToken("POST", "/api/me/contact/bind", `{"channel":"email","target":"bind@example.com","code":"000000"}`, token); w.Code != http.StatusBadRequest {
		t.Fatalf("错误验证码应返回 400，实际 %d: %s", w.Code, w.Body.String())
	}

	w := f.doWithToken("POST", "/api/me/contact/bind", `{"channel":"email","target":"bind@example.com","code":"`+code+`"}`, token)
	if w.Code != http.StatusOK {
		t.Fatalf("绑定失败: %d %s", w.Code, w.Body.String())
	}
	if data, _ := decodeBody(t, w)["data"].(map[string]any); data["email"] != "bind@example.com" || data["email_verified"] != true {
		t.Fatalf("绑定结果不符合预期: %v", data)
	}

	// 验证码一次性：重复使用同一验证码应失败
	if w := f.doWithToken("POST", "/api/me/contact/bind", `{"channel":"email","target":"bind@example.com","code":"`+code+`"}`, token); w.Code != http.StatusBadRequest {
		t.Fatalf("验证码应一次性使用，实际 %d: %s", w.Code, w.Body.String())
	}

	w = f.doWithToken("GET", "/api/me/contact", "", token)
	if w.Code != http.StatusOK {
		t.Fatalf("读取绑定信息失败: %d", w.Code)
	}
	if data, _ := decodeBody(t, w)["data"].(map[string]any); data["email"] != "bind@example.com" {
		t.Fatalf("绑定信息未落库: %v", data)
	}

	// 解绑需要正确密码
	if w := f.doWithToken("POST", "/api/me/contact/unbind", `{"channel":"email","password":"wrong"}`, token); w.Code != http.StatusBadRequest {
		t.Fatalf("密码错误应拒绝解绑，实际 %d", w.Code)
	}
	w = f.doWithToken("POST", "/api/me/contact/unbind", `{"channel":"email","password":"bindpass123"}`, token)
	if w.Code != http.StatusOK {
		t.Fatalf("解绑失败: %d %s", w.Code, w.Body.String())
	}
	if data, _ := decodeBody(t, w)["data"].(map[string]any); data["email"] != "" {
		t.Fatalf("解绑后邮箱应为空: %v", data)
	}
}

// 同一邮箱不能被两个账号绑定。
func TestBindContactConflict(t *testing.T) {
	accountEnv(t)
	f := newContentFixture(t)
	_, tokenA, _ := accountFixture(t, f, "conflict_a", "conflictpass1")
	_, tokenB, _ := accountFixture(t, f, "conflict_b", "conflictpass2")

	codeA := sendCode(t, f, tokenA, "email", "shared@example.com", "bind")
	if w := f.doWithToken("POST", "/api/me/contact/bind", `{"channel":"email","target":"shared@example.com","code":"`+codeA+`"}`, tokenA); w.Code != http.StatusOK {
		t.Fatalf("第一个账号绑定失败: %d %s", w.Code, w.Body.String())
	}

	// 第二个账号连发送都会被拒绝（占用检查在发码阶段完成）
	w := f.doWithToken("POST", "/api/auth/send-code", `{"channel":"email","target":"shared@example.com","purpose":"bind"}`, tokenB)
	if w.Code != http.StatusConflict {
		t.Fatalf("重复绑定应返回 409，实际 %d: %s", w.Code, w.Body.String())
	}
}

// 通过邮箱验证码重置密码：旧密码失效、全部设备下线。
func TestResetPasswordByEmail(t *testing.T) {
	accountEnv(t)
	f := newContentFixture(t)
	u, token, other := accountFixture(t, f, "reset_user", "resetpass123")

	code := sendCode(t, f, token, "email", "reset@example.com", "bind")
	if w := f.doWithToken("POST", "/api/me/contact/bind", `{"channel":"email","target":"reset@example.com","code":"`+code+`"}`, token); w.Code != http.StatusOK {
		t.Fatalf("绑定失败: %d %s", w.Code, w.Body.String())
	}

	resetCode := sendCode(t, f, "", "email", "reset@example.com", "reset")
	if w := f.doWithToken("POST", "/api/auth/reset-password", `{"channel":"email","target":"reset@example.com","code":"111111","new_password":"brandnew123"}`, ""); w.Code != http.StatusBadRequest {
		t.Fatalf("错误验证码应返回 400，实际 %d", w.Code)
	}

	w := f.doWithToken("POST", "/api/auth/reset-password", `{"channel":"email","target":"reset@example.com","code":"`+resetCode+`","new_password":"brandnew123"}`, "")
	if w.Code != http.StatusOK {
		t.Fatalf("重置密码失败: %d %s", w.Code, w.Body.String())
	}
	if n, _ := decodeBody(t, w)["revoked_sessions"].(float64); n != 2 {
		t.Fatalf("重置密码应下线全部 2 条会话，实际 %v", decodeBody(t, w)["revoked_sessions"])
	}
	if w := f.doWithToken("GET", "/api/me", "", token); w.Code != http.StatusUnauthorized {
		t.Fatalf("重置后原会话应失效，实际 %d", w.Code)
	}
	if w := f.doWithToken("GET", "/api/me", "", other); w.Code != http.StatusUnauthorized {
		t.Fatalf("重置后其他会话应失效，实际 %d", w.Code)
	}

	if w := f.doWithToken("POST", "/api/login", `{"username":"reset_user","password":"resetpass123"}`, ""); w.Code != http.StatusUnauthorized {
		t.Fatalf("旧密码应失效，实际 %d", w.Code)
	}
	if w := f.doWithToken("POST", "/api/login", `{"username":"reset_user","password":"brandnew123"}`, ""); w.Code != http.StatusOK {
		t.Fatalf("新密码应可登录，实际 %d: %s", w.Code, w.Body.String())
	}
	cleanupLoginToken(t, w)

	// 验证码不可重放
	if w := f.doWithToken("POST", "/api/auth/reset-password", `{"channel":"email","target":"reset@example.com","code":"`+resetCode+`","new_password":"another123"}`, ""); w.Code != http.StatusBadRequest {
		t.Fatalf("验证码应一次性，实际 %d", w.Code)
	}
	_ = u
}

// 未绑定账号的联系方式不应暴露账号是否存在。
func TestResetPasswordDoesNotLeakAccount(t *testing.T) {
	accountEnv(t)
	f := newContentFixture(t)

	w := f.doWithToken("POST", "/api/auth/send-code", `{"channel":"email","target":"nobody@example.com","purpose":"reset"}`, "")
	if w.Code != http.StatusOK {
		t.Fatalf("未绑定邮箱也应返回 200 避免枚举，实际 %d: %s", w.Code, w.Body.String())
	}
	if _, ok := decodeBody(t, w)["dev_code"]; ok {
		t.Fatal("账号不存在时不应真的下发验证码")
	}
}

// 验证码连续错误 5 次后作废，需重新获取。
func TestVerifyCodeAttemptLimit(t *testing.T) {
	accountEnv(t)
	f := newContentFixture(t)
	_, token, _ := accountFixture(t, f, "attempt_user", "attemptpass1")

	code := sendCode(t, f, token, "email", "attempt@example.com", "bind")
	wrong := "000000"
	if code == wrong {
		wrong = "000001"
	}
	for i := 0; i < 5; i++ { // 与 store 内部上限一致：5 次错误即作废
		if w := f.doWithToken("POST", "/api/me/contact/bind", `{"channel":"email","target":"attempt@example.com","code":"`+wrong+`"}`, token); w.Code != http.StatusBadRequest {
			t.Fatalf("第 %d 次错误验证码应返回 400，实际 %d", i+1, w.Code)
		}
	}
	// 错误次数耗尽后，正确验证码也应作废
	if w := f.doWithToken("POST", "/api/me/contact/bind", `{"channel":"email","target":"attempt@example.com","code":"`+code+`"}`, token); w.Code != http.StatusBadRequest {
		t.Fatalf("错误次数耗尽后正确验证码也应失效，实际 %d: %s", w.Code, w.Body.String())
	}
}

// 注销账号：密码错误拒绝；成功后匿名化、清空联系方式、下线全部设备。
func TestDeleteAccount(t *testing.T) {
	accountEnv(t)
	f := newContentFixture(t)
	u, token, other := accountFixture(t, f, "gone_user", "gonepass123")

	if w := f.doWithToken("POST", "/api/me/delete", `{"password":"wrong"}`, token); w.Code != http.StatusBadRequest {
		t.Fatalf("密码错误应拒绝注销，实际 %d", w.Code)
	}

	w := f.doWithToken("POST", "/api/me/delete", `{"password":"gonepass123"}`, token)
	if w.Code != http.StatusOK {
		t.Fatalf("注销失败: %d %s", w.Code, w.Body.String())
	}
	if w := f.doWithToken("GET", "/api/me", "", token); w.Code != http.StatusUnauthorized {
		t.Fatalf("注销后当前会话应失效，实际 %d", w.Code)
	}
	if w := f.doWithToken("GET", "/api/me", "", other); w.Code != http.StatusUnauthorized {
		t.Fatalf("注销后其他会话应失效，实际 %d", w.Code)
	}
	if w := f.doWithToken("POST", "/api/login", `{"username":"gone_user","password":"gonepass123"}`, ""); w.Code == http.StatusOK {
		t.Fatal("注销后不应还能登录")
	}

	gone, err := f.s.GetUserByID(context.Background(), u.ID)
	if err != nil || gone == nil {
		t.Fatalf("注销应保留用户行以便内容作者占位: %v", err)
	}
	if gone.Status != 2 || gone.Nickname != "已注销用户" || gone.Username != "deleted_"+strconv.Itoa(u.ID) {
		t.Fatalf("注销后信息未匿名化: %+v", gone)
	}
	contact, _ := f.s.GetUserContact(context.Background(), u.ID)
	if contact == nil || contact.Email != "" || contact.Phone != "" {
		t.Fatalf("注销后联系方式应清空: %+v", contact)
	}
}

// 管理员账号不允许自助注销。
func TestDeleteAccountRejectsStaff(t *testing.T) {
	accountEnv(t)
	f := newContentFixture(t)
	hash, _ := auth.HashPassword("adminpass123")
	staff := &store.User{Username: "ops_staff", Nickname: "运维", Role: "operator", Status: 1, PasswordHash: hash}
	if err := f.s.CreateUser(context.Background(), staff); err != nil {
		t.Fatal(err)
	}
	token := auth.DefaultSessionManager.CreateSession(staff, auth.SessionMeta{IP: "127.0.0.1", UserAgent: "test"})
	t.Cleanup(func() { auth.DefaultSessionManager.DeleteSession(token) })

	if w := f.doWithToken("POST", "/api/me/delete", `{"password":"adminpass123"}`, token); w.Code != http.StatusForbidden {
		t.Fatalf("管理员自助注销应返回 403，实际 %d: %s", w.Code, w.Body.String())
	}
}

// 头像上传：识别魔数、落盘、回写资料，并拒绝非图片。
func TestUploadAvatar(t *testing.T) {
	accountEnv(t)
	f := newContentFixture(t)
	_, token, _ := accountFixture(t, f, "avatar_user", "avatarpass1")

	upload := func(content []byte, filename string) *httptest.ResponseRecorder {
		var buf bytes.Buffer
		mw := multipart.NewWriter(&buf)
		fw, err := mw.CreateFormFile("file", filename)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := fw.Write(content); err != nil {
			t.Fatal(err)
		}
		_ = mw.Close()

		r := httptest.NewRequest("POST", "/api/me/avatar", &buf)
		r.Header.Set("Content-Type", mw.FormDataContentType())
		r.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		f.mux.ServeHTTP(w, r)
		return w
	}

	if w := upload([]byte("<?php echo 1; ?>"), "shell.png"); w.Code != http.StatusBadRequest {
		t.Fatalf("非图片应被拒绝，实际 %d: %s", w.Code, w.Body.String())
	}

	w := upload(pngHeader, "avatar.png")
	if w.Code != http.StatusOK {
		t.Fatalf("上传头像失败: %d %s", w.Code, w.Body.String())
	}
	url, _ := decodeBody(t, w)["url"].(string)
	if !strings.HasPrefix(url, "/uploads/avatars/") || !strings.HasSuffix(url, ".png") {
		t.Fatalf("头像 URL 不符合预期: %q", url)
	}

	// 文件确实落盘，且能通过静态路由访问
	disk := filepath.Join(os.Getenv("UPLOAD_DIR"), "avatars", strings.TrimPrefix(url, "/uploads/avatars/"))
	if _, err := os.Stat(disk); err != nil {
		t.Fatalf("头像未落盘: %v", err)
	}
	if resp := f.doWithToken("GET", url, "", ""); resp.Code != http.StatusOK {
		t.Fatalf("静态头像应可访问，实际 %d", resp.Code)
	}

	me := f.doWithToken("GET", "/api/me", "", token)
	if data, _ := decodeBody(t, me)["data"].(map[string]any); data["profile_avatar"] != url {
		t.Fatalf("头像未写回资料: %v", data["profile_avatar"])
	}

	// 再传一张：旧头像不再被删除，而是保留在历史里以便随时切回
	first := disk
	w2 := upload(pngHeader, "avatar2.png")
	if w2.Code != http.StatusOK {
		t.Fatalf("二次上传失败: %d", w2.Code)
	}
	second, _ := decodeBody(t, w2)["url"].(string)
	if second == url {
		t.Fatal("二次上传应生成新的头像地址")
	}
	if _, err := os.Stat(first); err != nil {
		t.Fatalf("旧头像应保留在历史中，stat err=%v", err)
	}

	list := f.doWithToken("GET", "/api/me/avatars", "", token)
	if list.Code != http.StatusOK {
		t.Fatalf("读取头像历史失败: %d", list.Code)
	}
	items, _ := decodeBody(t, list)["data"].([]any)
	if len(items) != 2 {
		t.Fatalf("应有 2 条历史头像，实际 %d", len(items))
	}
	if cur, _ := items[0].(map[string]any); cur["url"] != second || cur["current"] != true {
		t.Fatalf("最新一条应为当前头像: %v", items[0])
	}
	oldID := int(items[1].(map[string]any)["id"].(float64))

	// 当前头像不可删除
	if w := f.doWithToken("DELETE", "/api/me/avatars?id="+strconv.Itoa(int(items[0].(map[string]any)["id"].(float64))), "", token); w.Code != http.StatusBadRequest {
		t.Fatalf("删除当前头像应返回 400，实际 %d", w.Code)
	}

	// 删除历史头像时源文件一并清理
	if w := f.doWithToken("DELETE", "/api/me/avatars?id="+strconv.Itoa(oldID), "", token); w.Code != http.StatusOK {
		t.Fatalf("删除历史头像失败: %d %s", w.Code, w.Body.String())
	}
	if _, err := os.Stat(first); !os.IsNotExist(err) {
		t.Fatalf("删除历史头像应同时删掉源文件，stat err=%v", err)
	}
}

// 历史头像可以直接切回，切换后 current 标记随之变化。
func TestSwitchToHistoryAvatar(t *testing.T) {
	accountEnv(t)
	f := newContentFixture(t)
	_, token, _ := accountFixture(t, f, "history_user", "historypass1")

	upload := func() string {
		var buf bytes.Buffer
		mw := multipart.NewWriter(&buf)
		fw, _ := mw.CreateFormFile("file", "a.png")
		_, _ = fw.Write(pngHeader)
		_ = mw.Close()
		r := httptest.NewRequest("POST", "/api/me/avatar", &buf)
		r.Header.Set("Content-Type", mw.FormDataContentType())
		r.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		f.mux.ServeHTTP(w, r)
		if w.Code != http.StatusOK {
			t.Fatalf("上传失败: %d %s", w.Code, w.Body.String())
		}
		url, _ := decodeBody(t, w)["url"].(string)
		return url
	}

	first := upload()
	second := upload()

	items, _ := decodeBody(t, f.doWithToken("GET", "/api/me/avatars", "", token))["data"].([]any)
	oldID := int(items[1].(map[string]any)["id"].(float64))

	w := f.doWithToken("POST", "/api/me/avatars/use", `{"id":`+strconv.Itoa(oldID)+`}`, token)
	if w.Code != http.StatusOK {
		t.Fatalf("切换历史头像失败: %d %s", w.Code, w.Body.String())
	}
	me := f.doWithToken("GET", "/api/me", "", token)
	if data, _ := decodeBody(t, me)["data"].(map[string]any); data["profile_avatar"] != first {
		t.Fatalf("应切回第一张头像，实际 %v", data["profile_avatar"])
	}

	// 切回后第二张变成「可删除」，且 current 标记同步
	items, _ = decodeBody(t, f.doWithToken("GET", "/api/me/avatars", "", token))["data"].([]any)
	for _, raw := range items {
		item := raw.(map[string]any)
		if item["url"] == first && item["current"] != true {
			t.Fatalf("切回后第一张应标记为当前: %v", item)
		}
		if item["url"] == second && item["current"] == true {
			t.Fatalf("第二张不应再是当前: %v", item)
		}
	}
	if w := f.doWithToken("DELETE", "/api/me/avatars?id="+strconv.Itoa(int(items[0].(map[string]any)["id"].(float64))), "", token); w.Code != http.StatusOK {
		t.Fatalf("非当前头像应可删除，实际 %d: %s", w.Code, w.Body.String())
	}
}

// 上传目录不允许列目录。
func TestUploadDirNoListing(t *testing.T) {
	accountEnv(t)
	f := newContentFixture(t)

	if w := f.doWithToken("GET", "/uploads/avatars/", "", ""); w.Code != http.StatusNotFound {
		t.Fatalf("目录列表应返回 404，实际 %d", w.Code)
	}
}

// 非法联系方式格式应在入口拦截。
func TestContactValidation(t *testing.T) {
	accountEnv(t)
	f := newContentFixture(t)
	_, token, _ := accountFixture(t, f, "valid_user", "validpass123")

	cases := []string{
		`{"channel":"email","target":"not-an-email","purpose":"bind"}`,
		`{"channel":"phone","target":"12345","purpose":"bind"}`,
		`{"channel":"wechat","target":"x","purpose":"bind"}`,
		`{"channel":"email","target":"a@b.com","purpose":"unknown"}`,
	}
	for _, body := range cases {
		if w := f.doWithToken("POST", "/api/auth/send-code", body, token); w.Code != http.StatusBadRequest {
			t.Fatalf("%s 应返回 400，实际 %d: %s", body, w.Code, w.Body.String())
		}
	}
}

// cleanupLoginToken 解析登录响应里的 token 并登记清理，避免污染全局会话表。
func cleanupLoginToken(t *testing.T, w *httptest.ResponseRecorder) {
	t.Helper()
	var resp struct {
		Token string `json:"token"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil || resp.Token == "" {
		return
	}
	t.Cleanup(func() { auth.DefaultSessionManager.DeleteSession(resp.Token) })
}
