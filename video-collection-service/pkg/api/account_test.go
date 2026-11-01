package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"video-collection-service/pkg/auth"
	"video-collection-service/pkg/store"
)

// accountFixture 创建一个带真实密码的用户，并返回其两条独立会话（模拟两台设备）。
func accountFixture(t *testing.T, f *contentFixture, username, password string) (*store.User, string, string) {
	t.Helper()
	hash, err := auth.HashPassword(password)
	if err != nil {
		t.Fatal(err)
	}
	u := &store.User{Username: username, Nickname: username, Role: "user", Status: 1, PasswordHash: hash}
	if err := f.s.CreateUser(context.Background(), u); err != nil {
		t.Fatal(err)
	}
	primary := auth.DefaultSessionManager.CreateSession(u, auth.SessionMeta{IP: "10.0.0.1", UserAgent: "device-a"})
	other := auth.DefaultSessionManager.CreateSession(u, auth.SessionMeta{IP: "10.0.0.2", UserAgent: "device-b"})
	t.Cleanup(func() {
		auth.DefaultSessionManager.DeleteSession(primary)
		auth.DefaultSessionManager.DeleteSession(other)
	})
	return u, primary, other
}

func (f *contentFixture) doWithToken(method, path, body, token string) *httptest.ResponseRecorder {
	f.t.Helper()
	r := httptest.NewRequest(method, path, strings.NewReader(body))
	if token != "" {
		r.Header.Set("Authorization", "Bearer "+token)
	}
	w := httptest.NewRecorder()
	f.mux.ServeHTTP(w, r)
	return w
}

func TestChangePasswordRevokesOtherSessions(t *testing.T) {
	f := newContentFixture(t)
	u, primary, other := accountFixture(t, f, "pwd_user", "oldpass123")

	if w := f.doWithToken("POST", "/api/me/password", `{"old_password":"wrong-pass","new_password":"newpass123"}`, primary); w.Code != http.StatusBadRequest {
		t.Fatalf("原密码错误应返回 400，实际 %d: %s", w.Code, w.Body.String())
	}
	if w := f.doWithToken("POST", "/api/me/password", `{"old_password":"oldpass123","new_password":"oldpass123"}`, primary); w.Code != http.StatusBadRequest {
		t.Fatalf("新旧密码相同应返回 400，实际 %d: %s", w.Code, w.Body.String())
	}
	if w := f.doWithToken("POST", "/api/me/password", `{"old_password":"oldpass123","new_password":"12345"}`, primary); w.Code != http.StatusBadRequest {
		t.Fatalf("过短密码应返回 400，实际 %d: %s", w.Code, w.Body.String())
	}

	w := f.doWithToken("POST", "/api/me/password", `{"old_password":"oldpass123","new_password":"newpass123"}`, primary)
	if w.Code != http.StatusOK {
		t.Fatalf("改密失败: %d %s", w.Code, w.Body.String())
	}
	var result map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if n, _ := result["revoked_sessions"].(float64); n != 1 {
		t.Fatalf("应吊销 1 条其他会话，实际 %v", result["revoked_sessions"])
	}

	if w := f.doWithToken("GET", "/api/me", "", other); w.Code != http.StatusUnauthorized {
		t.Fatalf("其他设备应被下线，实际 %d", w.Code)
	}
	if w := f.doWithToken("GET", "/api/me", "", primary); w.Code != http.StatusOK {
		t.Fatalf("当前设备应保持登录，实际 %d", w.Code)
	}

	if w := f.doWithToken("POST", "/api/login", `{"username":"pwd_user","password":"oldpass123"}`, ""); w.Code != http.StatusUnauthorized {
		t.Fatalf("旧密码应失效，实际 %d", w.Code)
	}
	loginResp := f.doWithToken("POST", "/api/login", `{"username":"pwd_user","password":"newpass123"}`, "")
	if loginResp.Code != http.StatusOK {
		t.Fatalf("新密码应可登录，实际 %d: %s", loginResp.Code, loginResp.Body.String())
	}
	var loginBody struct {
		Token string `json:"token"`
	}
	_ = json.Unmarshal(loginResp.Body.Bytes(), &loginBody)
	if loginBody.Token != "" {
		t.Cleanup(func() { auth.DefaultSessionManager.DeleteSession(loginBody.Token) })
	}

	updated, err := f.s.GetUserByID(context.Background(), u.ID)
	if err != nil || updated == nil || !auth.CheckPassword(updated.PasswordHash, "newpass123") {
		t.Fatalf("数据库中的密码未更新: %v", err)
	}
}

func TestUserSessionListAndRevoke(t *testing.T) {
	f := newContentFixture(t)
	_, primary, other := accountFixture(t, f, "sess_user", "pass123456")

	w := f.doWithToken("GET", "/api/me/sessions", "", primary)
	if w.Code != http.StatusOK {
		t.Fatalf("会话列表失败: %d %s", w.Code, w.Body.String())
	}
	var payload struct {
		Data []auth.SessionView `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if len(payload.Data) != 2 {
		t.Fatalf("应有 2 条会话，实际 %d", len(payload.Data))
	}
	currentID := auth.SessionID(primary)
	otherID := auth.SessionID(other)
	currents := 0
	for _, s := range payload.Data {
		if s.Current {
			currents++
			if s.ID != currentID {
				t.Fatalf("当前会话 ID 不匹配: %s", s.ID)
			}
		}
		if s.UserAgent == "" || s.IP == "" {
			t.Fatalf("会话缺少设备信息: %+v", s)
		}
	}
	if currents != 1 {
		t.Fatalf("应恰好有 1 条当前会话，实际 %d", currents)
	}

	if w := f.doWithToken("DELETE", "/api/me/sessions?id="+currentID, "", primary); w.Code != http.StatusBadRequest {
		t.Fatalf("不允许下线当前设备，实际 %d", w.Code)
	}
	if w := f.doWithToken("DELETE", "/api/me/sessions?id="+otherID, "", primary); w.Code != http.StatusOK {
		t.Fatalf("下线其他设备失败: %d %s", w.Code, w.Body.String())
	}
	if w := f.doWithToken("GET", "/api/me", "", other); w.Code != http.StatusUnauthorized {
		t.Fatalf("被下线的设备应失效，实际 %d", w.Code)
	}
	if w := f.doWithToken("DELETE", "/api/me/sessions?id="+otherID, "", primary); w.Code != http.StatusNotFound {
		t.Fatalf("重复下线应返回 404，实际 %d", w.Code)
	}
}

func TestLoginRateLimit(t *testing.T) {
	f := newContentFixture(t)
	hash, err := auth.HashPassword("rightpass123")
	if err != nil {
		t.Fatal(err)
	}
	u := &store.User{Username: "limit_user", Nickname: "limit_user", Role: "user", Status: 1, PasswordHash: hash}
	if err := f.s.CreateUser(context.Background(), u); err != nil {
		t.Fatal(err)
	}
	key := "limit_user|192.0.2.1"
	t.Cleanup(func() { loginGuard.Reset(key) })

	for i := 0; i < 5; i++ {
		if w := f.doWithToken("POST", "/api/login", `{"username":"limit_user","password":"bad-pass"}`, ""); w.Code != http.StatusUnauthorized {
			t.Fatalf("第 %d 次失败登录应返回 401，实际 %d", i+1, w.Code)
		}
	}
	if w := f.doWithToken("POST", "/api/login", `{"username":"limit_user","password":"rightpass123"}`, ""); w.Code != http.StatusTooManyRequests {
		t.Fatalf("锁定期间应返回 429，实际 %d: %s", w.Code, w.Body.String())
	}

	loginGuard.Reset(key)
	okResp := f.doWithToken("POST", "/api/login", `{"username":"limit_user","password":"rightpass123"}`, "")
	if okResp.Code != http.StatusOK {
		t.Fatalf("解除限制后应可登录，实际 %d: %s", okResp.Code, okResp.Body.String())
	}
	var okBody struct {
		Token string `json:"token"`
	}
	_ = json.Unmarshal(okResp.Body.Bytes(), &okBody)
	if okBody.Token != "" {
		auth.DefaultSessionManager.DeleteSession(okBody.Token)
	}
}

func TestStaffCanEditOwnAccount(t *testing.T) {
	f := newContentFixture(t)
	admin := f.staff("admin")

	body := fmt.Sprintf(`{"id":%d,"nickname":"运维小助手","role":"admin","status":1}`, admin.ID)
	f.request("POST", "/api/admin/users", body, admin, http.StatusOK)

	updated, err := f.s.GetUserByID(context.Background(), admin.ID)
	if err != nil || updated == nil || updated.Nickname != "运维小助手" {
		t.Fatalf("昵称未更新: %+v %v", updated, err)
	}

	// 仍然禁止非超管给自己提权或改角色。
	escalate := fmt.Sprintf(`{"id":%d,"nickname":"运维小助手","role":"super_admin","status":1}`, admin.ID)
	f.request("POST", "/api/admin/users", escalate, admin, http.StatusForbidden)
}
