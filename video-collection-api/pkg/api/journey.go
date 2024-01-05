package api

import (
	"net/http"
	"time"
	"video-collection-api/pkg/auth"
	"video-collection-api/pkg/store"
)

func (srv *Server) handleJourney(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, "GET") {
		return
	}
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	data, err := srv.store.Journey(r.Context(), u.ID)
	if err != nil {
		growthError(w, err)
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "data": data})
}
func (srv *Server) handleMissionClaim(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, "POST") {
		return
	}
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	var req struct {
		Key string `json:"key"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	earned, err := srv.store.ClaimGrowthMission(r.Context(), u.ID, req.Key, time.Now())
	if err != nil {
		growthError(w, err)
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "data": map[string]int{"earned": earned}})
}
func (srv *Server) handleMissions(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, "GET", "POST") {
		return
	}
	if r.Method == "POST" {
		var m store.GrowthMission
		if !contentBody(w, r, &m) {
			return
		}
		if err := srv.store.SaveGrowthMission(r.Context(), &m); err != nil {
			growthError(w, err)
			return
		}
		jsonResponse(w, 200, map[string]any{"code": 1, "data": m})
		return
	}
	items, err := srv.store.ListGrowthMissions(r.Context(), 0, true, time.Now())
	if err != nil {
		growthError(w, err)
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "data": items})
}
func (srv *Server) handleRequestWall(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, "GET") {
		return
	}
	page, size, ok := contentPagination(w, r)
	if !ok {
		return
	}
	viewer := 0
	if u := auth.GetCurrentUser(r, srv.store); u != nil {
		viewer = u.ID
	}
	items, total, err := srv.store.MovieRequestWall(r.Context(), viewer, page, size)
	if err != nil {
		growthError(w, err)
		return
	}
	contentListResponse(w, items, total, page, size)
}
func requestWallUser(w http.ResponseWriter, r *http.Request, s store.Store) *store.User {
	u := contentUser(w, r, s)
	if u != nil && (u.Role == "operator" || u.Role == "observer") {
		errorResponse(w, 403, "当前角色不能公开或助力求片")
		return nil
	}
	return u
}
func (srv *Server) handleRequestShare(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, "POST") {
		return
	}
	u := requestWallUser(w, r, srv.store)
	if u == nil {
		return
	}
	var req struct {
		ID     int   `json:"id"`
		Shared *bool `json:"shared"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	if req.ID < 1 || req.Shared == nil {
		growthError(w, store.ErrInvalidOperation)
		return
	}
	if err := srv.store.ShareMovieRequest(r.Context(), u.ID, req.ID, *req.Shared); err != nil {
		growthError(w, err)
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "msg": "求片公开设置已更新"})
}
func (srv *Server) handleRequestSupport(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, "POST") {
		return
	}
	u := requestWallUser(w, r, srv.store)
	if u == nil {
		return
	}
	var req struct {
		ID int `json:"id"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	if req.ID < 1 {
		growthError(w, store.ErrInvalidOperation)
		return
	}
	if err := srv.store.SupportMovieRequest(r.Context(), u.ID, req.ID); err != nil {
		growthError(w, err)
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "msg": "已为这份期待亮灯"})
}
