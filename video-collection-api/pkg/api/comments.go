package api

import (
	"net/http"
	"strconv"
	"strings"

	"video-collection-api/pkg/auth"
	"video-collection-api/pkg/store"
)

func (srv *Server) genericCommentsHandler(admin bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		methods := []string{http.MethodGet, http.MethodPost, http.MethodDelete}
		if admin {
			methods = []string{http.MethodGet, http.MethodDelete}
		}
		if !contentMethod(w, r, methods...) {
			return
		}
		if r.Method == http.MethodGet {
			viewer := 0
			if u := auth.GetCurrentUser(r, srv.store); u != nil {
				viewer = u.ID
			}
			if r.URL.Query().Has("id") {
				id, ok := contentID(w, r.URL.Query().Get("id"))
				if !ok {
					return
				}
				c, err := srv.store.GetComment(r.Context(), id, viewer, admin)
				if err != nil {
					contentError(w, err)
					return
				}
				jsonResponse(w, 200, map[string]any{"code": 1, "data": c})
				return
			}
			id, ok := contentID(w, r.URL.Query().Get("target_id"))
			if !ok {
				return
			}
			page, size, ok := contentPagination(w, r)
			if !ok {
				return
			}
			q := store.CommentQuery{TargetType: strings.TrimSpace(r.URL.Query().Get("target_type")), TargetID: id, ViewerID: viewer, Page: page, PageSize: size, Admin: admin}
			for name, value := range map[string]*int{"parent_id": &q.ParentID, "root_id": &q.RootID} {
				if r.URL.Query().Has(name) {
					n, err := strconv.Atoi(r.URL.Query().Get(name))
					if err != nil || n < 0 {
						errorResponse(w, 400, name+" 必须为非负整数")
						return
					}
					*value = n
				}
			}
			items, total, err := srv.store.QueryComments(r.Context(), q)
			if err != nil {
				contentError(w, err)
				return
			}
			contentListResponse(w, items, total, page, size)
			return
		}
		u := contentUser(w, r, srv.store)
		if u == nil {
			return
		}
		if r.Method == http.MethodDelete {
			id, ok := contentID(w, r.URL.Query().Get("id"))
			if !ok {
				return
			}
			if err := srv.store.RemoveComment(r.Context(), id, u.ID, admin); err != nil {
				contentError(w, err)
				return
			}
			jsonResponse(w, 200, map[string]any{"code": 1, "msg": "评论已删除"})
			return
		}
		var req struct {
			TargetType string `json:"target_type"`
			TargetID   int    `json:"target_id"`
			ParentID   int    `json:"parent_id"`
			Content    string `json:"content"`
		}
		if !contentBody(w, r, &req) {
			return
		}
		c := store.Comment{TargetType: strings.TrimSpace(req.TargetType), TargetID: req.TargetID, ParentID: req.ParentID, Content: req.Content, UserID: u.ID, AuthorName: u.Nickname, AuthorAvatar: u.Avatar}
		if c.AuthorName == "" {
			c.AuthorName = u.Username
		}
		if err := srv.store.AddComment(r.Context(), &c); err != nil {
			contentError(w, err)
			return
		}
		jsonResponse(w, 200, map[string]any{"code": 1, "data": c, "msg": "评论成功"})
	}
}

func (srv *Server) handleCommentLike(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost, http.MethodDelete) {
		return
	}
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	var req struct {
		CommentID int `json:"comment_id"`
	}
	if r.Method == http.MethodPost {
		if !contentBody(w, r, &req) {
			return
		}
		if req.CommentID < 1 {
			errorResponse(w, 400, "comment_id 必须为正整数")
			return
		}
	} else {
		var ok bool
		req.CommentID, ok = contentID(w, r.URL.Query().Get("comment_id"))
		if !ok {
			return
		}
	}
	liked := r.Method == http.MethodPost
	count, err := srv.store.SetCommentLike(r.Context(), req.CommentID, u.ID, liked)
	if err != nil {
		contentError(w, err)
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "data": map[string]any{"liked": liked, "like_count": count}})
}
