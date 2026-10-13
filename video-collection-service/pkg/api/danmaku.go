package api

import (
	"errors"
	"net/http"
	"strings"
	"unicode/utf8"

	"video-collection-service/pkg/store"
)

var danmakuPalette = map[string]struct{}{
	"#FFFFFF": {},
	"#FFE14D": {},
	"#FF6B9A": {},
	"#7CFFB2": {},
	"#7AD7FF": {},
	"#C9A6FF": {},
	"#FF9F43": {},
}

func (srv *Server) handleDanmaku(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		srv.listDanmaku(w, r)
	case http.MethodPost:
		srv.createDanmaku(w, r)
	case http.MethodDelete:
		srv.deleteDanmaku(w, r)
	default:
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	}
}

func (srv *Server) listDanmaku(w http.ResponseWriter, r *http.Request) {
	videoID, ok := contentID(w, r.URL.Query().Get("video_id"))
	if !ok {
		return
	}
	episodeKey, ok := cleanEpisodeKey(r.URL.Query().Get("episode_key"))
	if !ok {
		errorResponse(w, http.StatusBadRequest, "剧集标识无效")
		return
	}
	items, err := srv.store.ListDanmaku(r.Context(), videoID, episodeKey)
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "弹幕加载失败")
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": items, "total": len(items)})
}

func (srv *Server) createDanmaku(w http.ResponseWriter, r *http.Request) {
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	if u.Role == "observer" {
		errorResponse(w, http.StatusForbidden, "观察员只能查看内容")
		return
	}
	var req struct {
		VideoID    int    `json:"video_id"`
		EpisodeKey string `json:"episode_key"`
		PlayTimeMs int    `json:"play_time_ms"`
		Mode       int    `json:"mode"`
		Color      string `json:"color"`
		Content    string `json:"content"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	episodeKey, ok := cleanEpisodeKey(req.EpisodeKey)
	if !ok || req.VideoID < 1 {
		errorResponse(w, http.StatusBadRequest, "剧集标识无效")
		return
	}
	if req.PlayTimeMs < 0 || req.PlayTimeMs > 12*60*60*1000 {
		errorResponse(w, http.StatusBadRequest, "弹幕时间无效")
		return
	}
	if req.Mode < 0 || req.Mode > 2 {
		errorResponse(w, http.StatusBadRequest, "弹幕位置无效")
		return
	}
	color := strings.ToUpper(strings.TrimSpace(req.Color))
	if color == "" {
		color = "#FFFFFF"
	}
	if _, allowed := danmakuPalette[color]; !allowed {
		errorResponse(w, http.StatusBadRequest, "弹幕颜色无效")
		return
	}
	content, ok := cleanDanmakuText(req.Content)
	if !ok {
		errorResponse(w, http.StatusBadRequest, "弹幕需要 1 到 40 个字")
		return
	}
	name := strings.TrimSpace(u.Nickname)
	if name == "" {
		name = u.Username
	}
	item := store.Danmaku{
		VideoID: req.VideoID, EpisodeKey: episodeKey, PlayTimeMs: req.PlayTimeMs,
		Mode: req.Mode, Color: color, Content: content, UserID: u.ID, AuthorName: name,
	}
	if err := srv.store.AddDanmaku(r.Context(), &item); err != nil {
		writeDanmakuError(w, err)
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "弹幕已发送", "data": item})
}

func (srv *Server) deleteDanmaku(w http.ResponseWriter, r *http.Request) {
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	id, ok := contentID(w, r.URL.Query().Get("id"))
	if !ok {
		return
	}
	if err := srv.store.DeleteDanmaku(r.Context(), id, u.ID, store.CanReview(u.Role)); err != nil {
		writeDanmakuError(w, err)
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "弹幕已删除"})
}

func writeDanmakuError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, store.ErrContentNotFound):
		errorResponse(w, http.StatusNotFound, "内容不存在")
	case errors.Is(err, store.ErrContentForbidden):
		errorResponse(w, http.StatusForbidden, "只能删除自己的弹幕")
	case errors.Is(err, store.ErrDanmakuLimited):
		errorResponse(w, http.StatusTooManyRequests, err.Error())
	default:
		errorResponse(w, http.StatusInternalServerError, "弹幕处理失败")
	}
}

func cleanEpisodeKey(raw string) (string, bool) {
	key := strings.TrimSpace(raw)
	if key == "" || utf8.RuneCountInString(key) > 80 {
		return "", false
	}
	for _, r := range key {
		if r < 0x20 || r == 0x7f {
			return "", false
		}
	}
	return key, true
}

func cleanDanmakuText(raw string) (string, bool) {
	text := strings.Join(strings.Fields(strings.TrimSpace(raw)), " ")
	count := utf8.RuneCountInString(text)
	if count < 1 || count > 40 {
		return "", false
	}
	return text, true
}
