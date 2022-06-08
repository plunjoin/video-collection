package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"
	"video-collection-api/pkg/auth"
	"video-collection-api/pkg/store"
)

func growthError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, store.ErrContentForbidden):
		errorResponse(w, 403, err.Error())
	case errors.Is(err, store.ErrContentNotFound):
		errorResponse(w, 404, err.Error())
	case errors.Is(err, store.ErrConflict):
		errorResponse(w, 409, err.Error())
	case errors.Is(err, store.ErrInvalidOperation), errors.Is(err, store.ErrInvalidComment), errors.Is(err, store.ErrInsufficientPoints):
		errorResponse(w, 400, err.Error())
	default:
		errorResponse(w, 500, "服务暂时不可用，请稍后重试")
	}
}
func (srv *Server) userProfile(r *http.Request, u *store.User) map[string]any {
	_ = srv.store.RecordActivity(r.Context(), u.ID, time.Now())
	d, _ := srv.store.Decorations(r.Context(), u.ID)
	avatar := u.Avatar
	if d.Avatar != "" {
		avatar = d.Avatar
	}
	balance, _ := srv.store.PointsBalance(r.Context(), u.ID)
	wallet := map[string]int{"balance": balance}
	return map[string]any{"id": u.ID, "username": u.Username, "nickname": u.Nickname, "avatar": avatar, "role": u.Role, "decorations": d, "wallet": wallet, "backend_access": store.IsStaff(u.Role), "can_review": store.CanReview(u.Role)}
}

// Called from every publication entry point, including public community/comments.
func (srv *Server) queuePublication(w http.ResponseWriter, r *http.Request, u *store.User, kind string, id int, payload any) bool {
	if u.Role == "observer" {
		errorResponse(w, 403, "观察员只能查看内容")
		return true
	}
	if u.Role != "operator" {
		return false
	}
	data, err := json.Marshal(payload)
	if err != nil {
		growthError(w, err)
		return true
	}
	v := store.Review{Kind: kind, TargetID: id, SubmitterID: u.ID, Payload: data}
	if err = srv.store.SubmitReview(r.Context(), &v); err != nil {
		growthError(w, err)
		return true
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "pending": true, "review_id": v.ID, "data": payload, "msg": "已提交审核，通过后才会展示"})
	return true
}
func staffPublicationDelete(w http.ResponseWriter, u *store.User) bool {
	if u.Role == "operator" || u.Role == "observer" {
		errorResponse(w, 403, "当前角色不能删除内容，请联系管理员")
		return false
	}
	return true
}
func (srv *Server) registerGrowthRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/api/user/journey", srv.handleJourney)
	mux.HandleFunc("/api/user/missions/claim", srv.handleMissionClaim)
	mux.HandleFunc("/api/admin/missions", auth.AdminRequired(srv.store, srv.handleMissions))
	mux.HandleFunc("/api/movie-request-wall", srv.handleRequestWall)
	mux.HandleFunc("/api/user/movie-requests/share", srv.handleRequestShare)
	mux.HandleFunc("/api/user/movie-requests/support", srv.handleRequestSupport)
	mux.HandleFunc("/api/user/points", srv.handlePoints)
	mux.HandleFunc("/api/user/points/checkin", srv.handleCheckin)
	mux.HandleFunc("/api/user/shop", srv.handleShop(false))
	mux.HandleFunc("/api/user/shop/redeem", srv.handleRedeem)
	mux.HandleFunc("/api/user/shop/equip", srv.handleEquip)
	mux.HandleFunc("/api/user/movie-requests", srv.handleMovieRequests(false))
	mux.HandleFunc("/api/admin/movie-requests", auth.AdminRequired(srv.store, srv.handleMovieRequests(true)))
	mux.HandleFunc("/api/admin/reviews", auth.AdminRequired(srv.store, srv.handleReviews))
	mux.HandleFunc("/api/admin/growth", auth.AdminRequired(srv.store, srv.handleGrowth))
	mux.HandleFunc("/api/admin/audit", auth.AdminRequired(srv.store, srv.handleAdminAudit))
	mux.HandleFunc("/api/admin/growth/rules", auth.AdminRequired(srv.store, srv.handleGrowthRules))
	mux.HandleFunc("/api/admin/shop", auth.AdminRequired(srv.store, srv.handleShop(true)))
	mux.HandleFunc("/api/cosmetics/", srv.handleCosmeticAsset)
}
func (srv *Server) handleAdminAudit(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, "GET") {
		return
	}
	page, size, ok := contentPagination(w, r)
	if !ok {
		return
	}
	items, total, err := srv.store.ListAdminOperations(r.Context(), page, size)
	if err != nil {
		growthError(w, err)
		return
	}
	contentListResponse(w, items, total, page, size)
}
func (srv *Server) handlePoints(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, "GET") {
		return
	}
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	data, err := srv.store.Wallet(r.Context(), u.ID)
	if err != nil {
		growthError(w, err)
		return
	}
	rules, err := srv.store.GrowthRules(r.Context())
	if err != nil {
		growthError(w, err)
		return
	}
	data["rules"] = rules
	jsonResponse(w, 200, map[string]any{"code": 1, "data": data})
}
func (srv *Server) handleCheckin(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, "POST") {
		return
	}
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	amount, err := srv.store.Checkin(r.Context(), u.ID, time.Now())
	if err != nil {
		growthError(w, err)
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "data": map[string]int{"earned": amount}, "msg": "签到成功（重复签到不会重复奖励）"})
}
func (srv *Server) handleShop(admin bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		methods := []string{"GET"}
		if admin {
			methods = append(methods, "POST")
		}
		if !contentMethod(w, r, methods...) {
			return
		}
		u := contentUser(w, r, srv.store)
		if u == nil {
			return
		}
		if r.Method == "POST" {
			var c store.Cosmetic
			if !contentBody(w, r, &c) {
				return
			}
			if err := srv.store.SaveCosmetic(r.Context(), &c); err != nil {
				growthError(w, err)
				return
			}
			jsonResponse(w, 200, map[string]any{"code": 1, "data": c})
			return
		}
		items, err := srv.store.ListCosmetics(r.Context(), u.ID, admin)
		if err != nil {
			growthError(w, err)
			return
		}
		jsonResponse(w, 200, map[string]any{"code": 1, "data": items})
	}
}
func (srv *Server) handleRedeem(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, "POST") {
		return
	}
	u := contentUser(w, r, srv.store)
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
	if err := srv.store.Redeem(r.Context(), u.ID, req.ID); err != nil {
		growthError(w, err)
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "msg": "兑换成功"})
}
func (srv *Server) handleEquip(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, "POST") {
		return
	}
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	var req struct {
		ID   int    `json:"id"`
		Slot string `json:"slot"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	if req.ID < 0 {
		growthError(w, store.ErrInvalidOperation)
		return
	}
	if err := srv.store.Equip(r.Context(), u.ID, req.ID, req.Slot); err != nil {
		growthError(w, err)
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "msg": "装扮已更新"})
}
func (srv *Server) handleMovieRequests(admin bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !contentMethod(w, r, "GET", "POST") {
			return
		}
		u := contentUser(w, r, srv.store)
		if u == nil {
			return
		}
		if r.Method == "GET" {
			page, size, ok := contentPagination(w, r)
			if !ok {
				return
			}
			owner := u.ID
			if admin {
				owner = 0
			}
			items, total, err := srv.store.ListMovieRequests(r.Context(), owner, page, size)
			if err != nil {
				growthError(w, err)
				return
			}
			contentListResponse(w, items, total, page, size)
			return
		}
		if admin {
			var req struct {
				ID     int    `json:"id"`
				Status string `json:"status"`
				Reply  string `json:"reply"`
			}
			if !contentBody(w, r, &req) {
				return
			}
			if err := srv.store.ResolveMovieRequest(r.Context(), req.ID, u.ID, req.Status, req.Reply); err != nil {
				growthError(w, err)
				return
			}
			jsonResponse(w, 200, map[string]any{"code": 1, "msg": "求片状态已更新"})
			return
		}
		if u.Role == "observer" || u.Role == "operator" {
			errorResponse(w, 403, "后台观察员和运营人员请使用内容提交工作台")
			return
		}
		var req struct {
			Title   string `json:"title"`
			Details string `json:"details"`
		}
		if !contentBody(w, r, &req) {
			return
		}
		v := store.MovieRequest{UserID: u.ID, Title: req.Title, Details: req.Details}
		if err := srv.store.CreateMovieRequest(r.Context(), &v); err != nil {
			growthError(w, err)
			return
		}
		jsonResponse(w, 200, map[string]any{"code": 1, "data": v, "msg": "求片已提交；未采纳会退还积分"})
	}
}
func (srv *Server) handleReviews(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, "GET", "POST") {
		return
	}
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	if r.Method == "GET" {
		page, size, ok := contentPagination(w, r)
		if !ok {
			return
		}
		owner := 0
		if u.Role == "operator" {
			owner = u.ID
		}
		items, total, err := srv.store.ListReviews(r.Context(), owner, r.URL.Query().Get("status"), page, size)
		if err != nil {
			growthError(w, err)
			return
		}
		contentListResponse(w, items, total, page, size)
		return
	}
	var req struct {
		ID      int    `json:"id"`
		Approve *bool  `json:"approve"`
		Note    string `json:"note"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	if req.ID < 1 || req.Approve == nil {
		growthError(w, store.ErrInvalidOperation)
		return
	}
	if err := srv.store.DecideReview(r.Context(), req.ID, u.ID, *req.Approve, req.Note); err != nil {
		growthError(w, err)
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "msg": "审核完成"})
}
func (srv *Server) handleGrowth(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, "GET") {
		return
	}
	items, err := srv.store.GrowthStats(r.Context())
	if err != nil {
		growthError(w, err)
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "data": items})
}
func (srv *Server) handleGrowthRules(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, "GET", "POST") {
		return
	}
	if r.Method == "POST" {
		var rules store.GrowthRules
		if !contentBody(w, r, &rules) {
			return
		}
		if err := srv.store.SaveGrowthRules(r.Context(), rules); err != nil {
			growthError(w, err)
			return
		}
	}
	rules, err := srv.store.GrowthRules(r.Context())
	if err != nil {
		growthError(w, err)
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "data": rules})
}

// Built-in SVGs contain no user supplied markup and are shared by all clients.
func (srv *Server) handleCosmeticAsset(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, "GET") {
		return
	}
	name := strings.TrimPrefix(r.URL.Path, "/api/cosmetics/")
	if name != "orbit.svg" && name != "pulse.svg" {
		http.NotFound(w, r)
		return
	}
	animation := ""
	if name == "pulse.svg" {
		animation = `<animate attributeName="r" values="24;29;24" dur="3s" repeatCount="indefinite"/>`
	}
	w.Header().Set("Content-Type", "image/svg+xml")
	w.Header().Set("Cache-Control", "public, max-age=86400")
	w.Header().Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; sandbox")
	_, _ = w.Write([]byte(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96"><defs><linearGradient id="g"><stop stop-color="#6366f1"/><stop offset="1" stop-color="#22d3ee"/></linearGradient></defs><rect width="96" height="96" rx="48" fill="#111827"/><circle cx="48" cy="48" r="26" fill="url(#g)">` + animation + `</circle><ellipse cx="48" cy="48" rx="39" ry="12" fill="none" stroke="#f5d0fe" stroke-width="3" transform="rotate(-25 48 48)"/><circle cx="72" cy="24" r="4" fill="#fde68a"/></svg>`))
}
