package api

import (
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"video-collection-service/pkg/auth"
)

const (
	passwordMinLen = 6
	// bcrypt 只使用前 72 字节，超出部分会被静默忽略，因此在入口处直接拒绝。
	passwordMaxLen = 72
)

// handleChangePassword 自助修改密码：校验原密码 → 校验新密码 → 落库 → 吊销其他设备会话。
func (srv *Server) handleChangePassword(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	u := auth.GetCurrentUser(r, srv.store)
	if u == nil {
		errorResponse(w, http.StatusUnauthorized, "请先登录")
		return
	}

	guardKey := strconv.Itoa(u.ID)
	if ok, wait := passwordGuard.Allow(guardKey); !ok {
		errorResponse(w, http.StatusTooManyRequests, "原密码校验失败次数过多，请 "+waitMinutes(wait)+"后再试")
		return
	}

	var req struct {
		OldPassword string `json:"old_password"`
		NewPassword string `json:"new_password"`
	}
	if !contentBody(w, r, &req) {
		return
	}

	oldPassword := strings.TrimSpace(req.OldPassword)
	newPassword := strings.TrimSpace(req.NewPassword)

	if oldPassword == "" {
		errorResponse(w, http.StatusBadRequest, "请输入原密码")
		return
	}
	if !auth.CheckPassword(u.PasswordHash, oldPassword) {
		passwordGuard.Fail(guardKey)
		errorResponse(w, http.StatusBadRequest, "原密码不正确")
		return
	}
	if msg, ok := validateNewPassword(newPassword, oldPassword); !ok {
		errorResponse(w, http.StatusBadRequest, msg)
		return
	}

	hash, err := auth.HashPassword(newPassword)
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "密码加密失败")
		return
	}
	if err := srv.store.UpdatePassword(r.Context(), u.ID, hash); err != nil {
		errorResponse(w, http.StatusInternalServerError, "密码保存失败，请稍后重试")
		return
	}
	passwordGuard.Reset(guardKey)

	// 改密后让其他设备下线，避免旧凭据在别处继续有效。
	revoked := auth.DefaultSessionManager.RevokeOtherSessions(u.ID, auth.TokenFromRequest(r))

	name := strings.TrimSpace(u.Nickname)
	if name == "" {
		name = u.Username
	}
	srv.logSystemActor(r, u.ID, name, "info", "auth", "修改密码成功", map[string]any{
		"username":         u.Username,
		"revoked_sessions": revoked,
	})

	jsonResponse(w, http.StatusOK, map[string]any{
		"code":             1,
		"msg":              "密码已更新",
		"revoked_sessions": revoked,
	})
}

// validateNewPassword 校验新密码强度，返回可直接展示给用户的提示。
func validateNewPassword(newPassword, oldPassword string) (string, bool) {
	if newPassword == "" {
		return "请输入新密码", false
	}
	if utf8.RuneCountInString(newPassword) < passwordMinLen {
		return "新密码长度不能少于 6 位", false
	}
	if len(newPassword) > passwordMaxLen {
		return "新密码不能超过 72 字节", false
	}
	if newPassword == oldPassword {
		return "新密码不能与原密码相同", false
	}
	if isRepeatedChar(newPassword) {
		return "新密码不能是单一字符重复", false
	}
	return "", true
}

func isRepeatedChar(s string) bool {
	if len(s) < 2 {
		return false
	}
	first := s[0]
	for i := 1; i < len(s); i++ {
		if s[i] != first {
			return false
		}
	}
	return true
}

func waitMinutes(d time.Duration) string {
	m := int(math.Ceil(d.Minutes()))
	if m < 1 {
		m = 1
	}
	return strconv.Itoa(m) + " 分钟"
}

// handleUserSessions 登录设备管理：GET 列出当前账号的会话，DELETE 吊销指定会话。
func (srv *Server) handleUserSessions(w http.ResponseWriter, r *http.Request) {
	u := auth.GetCurrentUser(r, srv.store)
	if u == nil {
		errorResponse(w, http.StatusUnauthorized, "请先登录")
		return
	}
	currentID := auth.SessionID(auth.TokenFromRequest(r))

	switch r.Method {
	case http.MethodGet:
		list := auth.DefaultSessionManager.ListUserSessions(u.ID)
		for i := range list {
			list[i].Current = list[i].ID == currentID
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": list})

	case http.MethodDelete:
		id := strings.TrimSpace(r.URL.Query().Get("id"))
		if id == "" {
			errorResponse(w, http.StatusBadRequest, "缺少会话 id")
			return
		}
		if id == currentID {
			errorResponse(w, http.StatusBadRequest, "不能下线当前设备，请直接退出登录")
			return
		}
		if !auth.DefaultSessionManager.RevokeSession(u.ID, id) {
			errorResponse(w, http.StatusNotFound, "会话不存在或已失效")
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "该设备已下线"})

	default:
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	}
}
