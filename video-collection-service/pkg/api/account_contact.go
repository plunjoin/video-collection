package api

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"regexp"
	"strings"
	"time"

	"video-collection-service/pkg/auth"
	"video-collection-service/pkg/notify"
	"video-collection-service/pkg/store"
)

const (
	verifyCodeTTL    = 10 * time.Minute
	verifyCodeLength = 6
	contactMaxEmail  = 120
	contactMaxPhone  = 20
)

var (
	emailPattern = regexp.MustCompile(`^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$`)
	phonePattern = regexp.MustCompile(`^1[3-9]\d{9}$`)
)

// normalizeContact 规范化并校验邮箱 / 手机号，返回可直接落库的值。
// 邮箱统一小写（唯一索引按原值比较）；手机号去掉常见分隔符。
func normalizeContact(channel, raw string) (string, string) {
	value := strings.TrimSpace(raw)
	switch channel {
	case notify.ChannelEmail:
		value = strings.ToLower(value)
		if value == "" {
			return "", "请输入邮箱地址"
		}
		if len(value) > contactMaxEmail || !emailPattern.MatchString(value) {
			return "", "邮箱格式不正确"
		}
		return value, ""
	case notify.ChannelPhone:
		value = strings.NewReplacer(" ", "", "-", "", "(", "", ")", "").Replace(value)
		if value == "" {
			return "", "请输入手机号"
		}
		if len(value) > contactMaxPhone || !phonePattern.MatchString(value) {
			return "", "请输入 11 位中国大陆手机号"
		}
		return value, ""
	}
	return "", "channel 只能是 email 或 phone"
}

func channelLabel(channel string) string {
	if channel == notify.ChannelPhone {
		return "短信"
	}
	return "邮件"
}

// hashCode 验证码只存哈希，且绑定目标值，避免同一验证码跨账号复用。
func hashCode(target, code string) string {
	sum := sha256.Sum256([]byte(target + ":" + code))
	return hex.EncodeToString(sum[:])
}

func generateCode() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

func digitsOnly(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return len(s) > 0
}

// handleSendCode 发送验证码。purpose=reset 面向未登录用户（忘记密码），
// purpose=bind 需要登录（绑定邮箱 / 手机）。
func (srv *Server) handleSendCode(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	var req struct {
		Channel string `json:"channel"`
		Target  string `json:"target"`
		Purpose string `json:"purpose"`
	}
	if !contentBody(w, r, &req) {
		return
	}

	channel := strings.TrimSpace(req.Channel)
	purpose := strings.TrimSpace(req.Purpose)
	if purpose == "" {
		purpose = notify.PurposeReset
	}
	if channel != notify.ChannelEmail && channel != notify.ChannelPhone {
		errorResponse(w, http.StatusBadRequest, "channel 只能是 email 或 phone")
		return
	}
	if purpose != notify.PurposeBind && purpose != notify.PurposeReset {
		errorResponse(w, http.StatusBadRequest, "purpose 只能是 bind 或 reset")
		return
	}
	value, msg := normalizeContact(channel, req.Target)
	if msg != "" {
		errorResponse(w, http.StatusBadRequest, msg)
		return
	}

	var current *store.User
	if purpose == notify.PurposeBind {
		current = auth.GetCurrentUser(r, srv.store)
		if current == nil {
			errorResponse(w, http.StatusUnauthorized, "请先登录")
			return
		}
	}

	guardKey := channel + "|" + value
	if ok, wait := codeGuard.Allow(guardKey); !ok {
		errorResponse(w, http.StatusTooManyRequests, "验证码发送过于频繁，请 "+waitMinutes(wait)+"后再试")
		return
	}
	if !srv.notifier.Configured(channel) && !notify.DevCodeEnabled() {
		errorResponse(w, http.StatusServiceUnavailable, channelLabel(channel)+"通道未配置，请联系管理员")
		return
	}

	if purpose == notify.PurposeReset {
		// 不暴露账号是否存在：查不到同样返回成功文案。
		existing, err := srv.store.GetUserByContact(r.Context(), channel, value)
		if err != nil {
			errorResponse(w, http.StatusInternalServerError, "服务暂时不可用，请稍后重试")
			return
		}
		if existing == nil || existing.Status != 1 {
			codeGuard.Fail(guardKey)
			jsonResponse(w, http.StatusOK, map[string]any{
				"code": 1,
				"msg":  "如果该联系方式已绑定可用账号，验证码已发送",
			})
			return
		}
		current = existing
	} else {
		// 绑定场景：该值已被他人占用时直接拒绝；本人重复绑定同一值视为幂等。
		existing, err := srv.store.GetUserByContact(r.Context(), channel, value)
		if err != nil {
			errorResponse(w, http.StatusInternalServerError, "服务暂时不可用，请稍后重试")
			return
		}
		if existing != nil && existing.ID != current.ID {
			errorResponse(w, http.StatusConflict, "该"+channelLabel(channel)+"已被其他账号绑定")
			return
		}
	}

	code, err := generateCode()
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "验证码生成失败，请稍后重试")
		return
	}
	vc := &store.VerifyCode{
		Target:    value,
		Channel:   channel,
		Purpose:   purpose,
		CodeHash:  hashCode(value, code),
		ExpiresAt: time.Now().Add(verifyCodeTTL),
	}
	if err := srv.store.CreateVerifyCode(r.Context(), vc); err != nil {
		errorResponse(w, http.StatusInternalServerError, "验证码保存失败，请稍后重试")
		return
	}
	if err := srv.notifier.Send(r.Context(), channel, value, code, purpose); err != nil && !errors.Is(err, notify.ErrNotConfigured) {
		errorResponse(w, http.StatusBadGateway, "验证码发送失败，请稍后重试")
		return
	}
	codeGuard.Fail(guardKey)

	resp := map[string]any{
		"code":       1,
		"msg":        "验证码已发送，10 分钟内有效",
		"expires_in": int(verifyCodeTTL.Seconds()),
	}
	if notify.DevCodeEnabled() {
		// 联调环境显式开启，方便无邮件 / 短信通道时自测。
		resp["dev_code"] = code
	}
	jsonResponse(w, http.StatusOK, resp)
}

// handleResetPassword 忘记密码：验证码校验通过后直接重置密码并下线全部设备。
func (srv *Server) handleResetPassword(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	var req struct {
		Channel     string `json:"channel"`
		Target      string `json:"target"`
		Code        string `json:"code"`
		NewPassword string `json:"new_password"`
	}
	if !contentBody(w, r, &req) {
		return
	}

	channel := strings.TrimSpace(req.Channel)
	if channel != notify.ChannelEmail && channel != notify.ChannelPhone {
		errorResponse(w, http.StatusBadRequest, "channel 只能是 email 或 phone")
		return
	}
	value, msg := normalizeContact(channel, req.Target)
	if msg != "" {
		errorResponse(w, http.StatusBadRequest, msg)
		return
	}
	code := strings.TrimSpace(req.Code)
	if len(code) != verifyCodeLength || !digitsOnly(code) {
		errorResponse(w, http.StatusBadRequest, "请输入 6 位数字验证码")
		return
	}

	guardKey := channel + "|" + value
	if ok, wait := resetGuard.Allow(guardKey); !ok {
		errorResponse(w, http.StatusTooManyRequests, "验证码校验失败次数过多，请 "+waitMinutes(wait)+"后再试")
		return
	}

	matched, err := srv.store.ConsumeVerifyCode(r.Context(), value, channel, notify.PurposeReset, hashCode(value, code))
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "服务暂时不可用，请稍后重试")
		return
	}
	if !matched {
		resetGuard.Fail(guardKey)
		errorResponse(w, http.StatusBadRequest, "验证码错误或已过期")
		return
	}
	resetGuard.Reset(guardKey)

	u, err := srv.store.GetUserByContact(r.Context(), channel, value)
	if err != nil || u == nil {
		errorResponse(w, http.StatusBadRequest, "验证码错误或已过期")
		return
	}
	if u.Status != 1 {
		errorResponse(w, http.StatusForbidden, "该账号当前不可用，请联系管理员")
		return
	}
	if msg, ok := validateNewPassword(strings.TrimSpace(req.NewPassword), ""); !ok {
		errorResponse(w, http.StatusBadRequest, msg)
		return
	}
	hash, err := auth.HashPassword(strings.TrimSpace(req.NewPassword))
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "密码加密失败")
		return
	}
	if err := srv.store.UpdatePassword(r.Context(), u.ID, hash); err != nil {
		errorResponse(w, http.StatusInternalServerError, "密码保存失败，请稍后重试")
		return
	}
	// 找回密码视为账号可能已泄露，全部设备强制下线。
	revoked := auth.DefaultSessionManager.RevokeOtherSessions(u.ID, "")

	name := strings.TrimSpace(u.Nickname)
	if name == "" {
		name = u.Username
	}
	srv.logSystemActor(r, u.ID, name, "warn", "auth", "通过验证码重置密码", map[string]any{
		"username":         u.Username,
		"channel":          channel,
		"revoked_sessions": revoked,
	})

	jsonResponse(w, http.StatusOK, map[string]any{
		"code":             1,
		"msg":              "密码已重置，请使用新密码登录",
		"revoked_sessions": revoked,
	})
}

// handleUserContact GET 读取当前账号绑定的邮箱 / 手机。
func (srv *Server) handleUserContact(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodGet) {
		return
	}
	u := auth.GetCurrentUser(r, srv.store)
	if u == nil {
		errorResponse(w, http.StatusUnauthorized, "请先登录")
		return
	}
	c, err := srv.store.GetUserContact(r.Context(), u.ID)
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "读取绑定信息失败，请稍后重试")
		return
	}
	if c == nil {
		c = &store.UserContact{}
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": c})
}

// handleBindContact 绑定邮箱 / 手机：校验验证码 → 落库。
func (srv *Server) handleBindContact(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	u := auth.GetCurrentUser(r, srv.store)
	if u == nil {
		errorResponse(w, http.StatusUnauthorized, "请先登录")
		return
	}
	var req struct {
		Channel string `json:"channel"`
		Target  string `json:"target"`
		Code    string `json:"code"`
	}
	if !contentBody(w, r, &req) {
		return
	}

	channel := strings.TrimSpace(req.Channel)
	value, msg := normalizeContact(channel, req.Target)
	if msg != "" {
		errorResponse(w, http.StatusBadRequest, msg)
		return
	}
	code := strings.TrimSpace(req.Code)
	if len(code) != verifyCodeLength || !digitsOnly(code) {
		errorResponse(w, http.StatusBadRequest, "请输入 6 位数字验证码")
		return
	}

	matched, err := srv.store.ConsumeVerifyCode(r.Context(), value, channel, notify.PurposeBind, hashCode(value, code))
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "服务暂时不可用，请稍后重试")
		return
	}
	if !matched {
		errorResponse(w, http.StatusBadRequest, "验证码错误或已过期")
		return
	}
	if err := srv.store.BindContact(r.Context(), u.ID, channel, value); err != nil {
		if errors.Is(err, store.ErrContactTaken) {
			errorResponse(w, http.StatusConflict, "该"+channelLabel(channel)+"已被其他账号绑定")
			return
		}
		errorResponse(w, http.StatusInternalServerError, "绑定失败，请稍后重试")
		return
	}

	c, _ := srv.store.GetUserContact(r.Context(), u.ID)
	if c == nil {
		c = &store.UserContact{}
	}
	name := strings.TrimSpace(u.Nickname)
	if name == "" {
		name = u.Username
	}
	srv.logSystemActor(r, u.ID, name, "info", "auth", "绑定"+channelLabel(channel), map[string]any{
		"username": u.Username,
		"channel":  channel,
	})
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": channelLabel(channel) + "绑定成功", "data": c})
}

// handleUnbindContact 解绑邮箱 / 手机，需二次确认密码。
func (srv *Server) handleUnbindContact(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	u := auth.GetCurrentUser(r, srv.store)
	if u == nil {
		errorResponse(w, http.StatusUnauthorized, "请先登录")
		return
	}
	var req struct {
		Channel  string `json:"channel"`
		Password string `json:"password"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	channel := strings.TrimSpace(req.Channel)
	if channel != notify.ChannelEmail && channel != notify.ChannelPhone {
		errorResponse(w, http.StatusBadRequest, "channel 只能是 email 或 phone")
		return
	}
	if !auth.CheckPassword(u.PasswordHash, strings.TrimSpace(req.Password)) {
		errorResponse(w, http.StatusBadRequest, "密码不正确")
		return
	}
	if err := srv.store.UnbindContact(r.Context(), u.ID, channel); err != nil {
		errorResponse(w, http.StatusInternalServerError, "解绑失败，请稍后重试")
		return
	}

	c, _ := srv.store.GetUserContact(r.Context(), u.ID)
	if c == nil {
		c = &store.UserContact{}
	}
	name := strings.TrimSpace(u.Nickname)
	if name == "" {
		name = u.Username
	}
	srv.logSystemActor(r, u.ID, name, "warn", "auth", "解绑"+channelLabel(channel), map[string]any{
		"username": u.Username,
		"channel":  channel,
	})
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": channelLabel(channel) + "已解绑", "data": c})
}

// handleDeleteAccount 注销账号：保留历史内容的作者占位，清空可识别信息并下线全部设备。
func (srv *Server) handleDeleteAccount(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	u := auth.GetCurrentUser(r, srv.store)
	if u == nil {
		errorResponse(w, http.StatusUnauthorized, "请先登录")
		return
	}
	var req struct {
		Password string `json:"password"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	if !auth.CheckPassword(u.PasswordHash, strings.TrimSpace(req.Password)) {
		errorResponse(w, http.StatusBadRequest, "密码不正确")
		return
	}
	if store.IsStaff(u.Role) {
		errorResponse(w, http.StatusForbidden, "管理员账号不能自助注销，请先移交权限并改为普通用户")
		return
	}
	if err := srv.store.AnonymizeUser(r.Context(), u.ID); err != nil {
		errorResponse(w, http.StatusInternalServerError, "注销失败，请稍后重试")
		return
	}
	revoked := auth.DefaultSessionManager.RevokeOtherSessions(u.ID, "")
	auth.ClearAuthCookie(w)

	name := strings.TrimSpace(u.Nickname)
	if name == "" {
		name = u.Username
	}
	srv.logSystemActor(r, u.ID, name, "warn", "auth", "注销账号", map[string]any{
		"username":         u.Username,
		"revoked_sessions": revoked,
	})
	jsonResponse(w, http.StatusOK, map[string]any{
		"code":             1,
		"msg":              "账号已注销，感谢一路同行",
		"revoked_sessions": revoked,
	})
}
