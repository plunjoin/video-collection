package api

import (
	"net/http"
	"net/url"
	"strings"
	"unicode/utf8"

	"video-collection-service/pkg/auth"
)

func (srv *Server) handleUpdateProfile(w http.ResponseWriter, r *http.Request) {
	u := auth.GetCurrentUser(r, srv.store)
	if u == nil {
		errorResponse(w, http.StatusUnauthorized, "请先登录")
		return
	}
	var req struct {
		Nickname string `json:"nickname"`
		Avatar   string `json:"avatar"`
		Bio      string `json:"bio"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	nickname, ok := cleanNickname(req.Nickname)
	if !ok {
		errorResponse(w, http.StatusBadRequest, "昵称需要 1 到 20 个字")
		return
	}
	avatar, ok := cleanProfileAvatar(req.Avatar)
	if !ok {
		errorResponse(w, http.StatusBadRequest, "头像需要是 http 或 https 链接，也可以留空")
		return
	}
	bio, ok := cleanBio(req.Bio)
	if !ok {
		errorResponse(w, http.StatusBadRequest, "个人简介最多 80 个字")
		return
	}
	if err := srv.store.UpdateProfile(r.Context(), u.ID, nickname, avatar, bio); err != nil {
		errorResponse(w, http.StatusInternalServerError, "资料保存失败，请稍后重试")
		return
	}
	updated, err := srv.store.GetUserByID(r.Context(), u.ID)
	if err != nil || updated == nil {
		errorResponse(w, http.StatusInternalServerError, "资料保存失败，请稍后重试")
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "资料已更新", "data": srv.userProfile(r, updated)})
}

func cleanNickname(raw string) (string, bool) {
	name := strings.Join(strings.Fields(strings.TrimSpace(raw)), " ")
	count := utf8.RuneCountInString(name)
	if count < 1 || count > 20 || len(name) > 64 {
		return "", false
	}
	for _, r := range name {
		if r < 0x20 {
			return "", false
		}
	}
	return name, true
}

func cleanBio(raw string) (string, bool) {
	bio := strings.Join(strings.Fields(strings.TrimSpace(raw)), " ")
	if utf8.RuneCountInString(bio) > 80 {
		return "", false
	}
	return bio, true
}

func cleanProfileAvatar(raw string) (string, bool) {
	avatar := strings.TrimSpace(raw)
	if avatar == "" {
		return "", true
	}
	if len(avatar) > 255 || strings.ContainsAny(avatar, " \t\r\n") {
		return "", false
	}
	if strings.HasPrefix(avatar, "/") {
		if strings.Contains(avatar, "..") || strings.Contains(avatar, "\\") {
			return "", false
		}
		return avatar, true
	}
	parsed, err := url.Parse(avatar)
	if err != nil || parsed.Host == "" || parsed.User != nil {
		return "", false
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return "", false
	}
	return avatar, true
}
