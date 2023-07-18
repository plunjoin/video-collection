package api

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"unicode/utf8"

	"video-collection-api/pkg/auth"
	"video-collection-api/pkg/store"
)

func (srv *Server) registerContentRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/api/comments", srv.genericCommentsHandler(false))
	mux.HandleFunc("/api/comments/likes", srv.handleCommentLike)
	mux.HandleFunc("/api/admin/comments", auth.AdminRequired(srv.store, srv.genericCommentsHandler(true)))
	mux.HandleFunc("/api/news", srv.contentHandler("news", false))
	mux.HandleFunc("/api/community/posts", srv.contentHandler("post", false))
	mux.HandleFunc("/api/community/comments", srv.commentsHandler(false))
	mux.HandleFunc("/api/community/likes", srv.handlePostLike)
	mux.HandleFunc("/api/user/notifications", srv.handleNotifications)
	mux.HandleFunc("/api/user/notifications/unread-count", srv.handleUnreadNotifications)
	mux.HandleFunc("/api/user/notifications/read", srv.handleReadNotifications)
	mux.HandleFunc("/api/admin/news", auth.AdminRequired(srv.store, srv.contentHandler("news", true)))
	mux.HandleFunc("/api/admin/community/posts", auth.AdminRequired(srv.store, srv.contentHandler("post", true)))
	mux.HandleFunc("/api/admin/community/comments", auth.AdminRequired(srv.store, srv.commentsHandler(true)))
	mux.HandleFunc("/api/admin/notifications", auth.AdminRequired(srv.store, srv.handleSendNotification))
}

func contentMethod(w http.ResponseWriter, r *http.Request, methods ...string) bool {
	for _, method := range methods {
		if r.Method == method {
			return true
		}
	}
	w.Header().Set("Allow", strings.Join(methods, ", "))
	errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	return false
}

func contentError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, store.ErrInvalidComment):
		errorResponse(w, http.StatusBadRequest, err.Error())
	case errors.Is(err, store.ErrContentNotFound):
		errorResponse(w, http.StatusNotFound, err.Error())
	case errors.Is(err, store.ErrContentForbidden):
		errorResponse(w, http.StatusForbidden, err.Error())
	case errors.Is(err, store.ErrInvalidRecipient):
		errorResponse(w, http.StatusBadRequest, err.Error())
	default:
		errorResponse(w, http.StatusInternalServerError, "数据操作失败，请稍后重试")
	}
}

func contentBody(w http.ResponseWriter, r *http.Request, value any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	err := decoder.Decode(value)
	if err == nil {
		var extra any
		if decoder.Decode(&extra) != io.EOF {
			err = errors.New("multiple JSON values")
		}
	}
	if err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			errorResponse(w, http.StatusRequestEntityTooLarge, "请求内容过大")
		} else {
			errorResponse(w, http.StatusBadRequest, "JSON 参数无效或包含未知字段")
		}
		return false
	}
	return true
}

func contentID(w http.ResponseWriter, raw string) (int, bool) {
	id, err := strconv.Atoi(raw)
	if err != nil || id < 1 {
		errorResponse(w, http.StatusBadRequest, "id 必须为正整数")
		return 0, false
	}
	return id, true
}

func contentPagination(w http.ResponseWriter, r *http.Request) (int, int, bool) {
	values := []int{1, 20}
	for i, key := range []string{"page", "page_size"} {
		if r.URL.Query().Has(key) {
			n, err := strconv.Atoi(r.URL.Query().Get(key))
			if err != nil || n < 1 || (key == "page" && n > 1000000) || (key == "page_size" && n > 100) {
				errorResponse(w, http.StatusBadRequest, "page 必须为 1–1000000，page_size 必须为 1–100")
				return 0, 0, false
			}
			values[i] = n
		}
	}
	return values[0], values[1], true
}

func contentUser(w http.ResponseWriter, r *http.Request, s store.Store) *store.User {
	u := auth.GetCurrentUser(r, s)
	if u == nil {
		errorResponse(w, http.StatusUnauthorized, "请先登录")
	}
	return u
}

func contentListResponse(w http.ResponseWriter, items any, total, page, size int) {
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": items, "total": total, "page": page, "page_size": size})
}

func validContentStatus(kind, status string) bool {
	return status == "published" || (kind == "news" && status == "draft") || (kind == "post" && status == "hidden")
}

func (srv *Server) contentHandler(kind string, admin bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		methods := []string{http.MethodGet, http.MethodPost, http.MethodDelete}
		if kind == "news" && !admin {
			methods = []string{http.MethodGet}
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
				item, err := srv.store.GetContent(r.Context(), kind, id, viewer, admin)
				if err != nil {
					contentError(w, err)
					return
				}
				jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": item})
				return
			}
			page, size, ok := contentPagination(w, r)
			if !ok {
				return
			}
			q := store.ContentQuery{Page: page, PageSize: size, ViewerID: viewer, Kind: kind, Admin: admin, Keyword: strings.TrimSpace(r.URL.Query().Get("keyword")), Category: strings.TrimSpace(r.URL.Query().Get("category"))}
			if utf8.RuneCountInString(q.Keyword) > 200 || utf8.RuneCountInString(q.Category) > 50 {
				errorResponse(w, 400, "搜索条件过长")
				return
			}
			if r.URL.Query().Has("author_id") {
				q.AuthorID, ok = contentID(w, r.URL.Query().Get("author_id"))
				if !ok {
					return
				}
			}
			if admin {
				q.Status = r.URL.Query().Get("status")
				if q.Status != "" && !validContentStatus(kind, q.Status) {
					errorResponse(w, 400, "无效的内容状态")
					return
				}
			}
			items, total, err := srv.store.ListContent(r.Context(), q)
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
			if !staffPublicationDelete(w, u) {
				return
			}
			id, ok := contentID(w, r.URL.Query().Get("id"))
			if !ok {
				return
			}
			if err := srv.store.DeleteContent(r.Context(), kind, id, u.ID, admin); err != nil {
				contentError(w, err)
				return
			}
			jsonResponse(w, 200, map[string]any{"code": 1, "msg": "删除成功"})
			return
		}
		var req struct {
			ID       int    `json:"id"`
			Title    string `json:"title"`
			Summary  string `json:"summary"`
			Content  string `json:"content"`
			Cover    string `json:"cover"`
			Category string `json:"category"`
			Status   string `json:"status"`
			Pinned   *bool  `json:"pinned"`
		}
		if !contentBody(w, r, &req) {
			return
		}
		if !admin && (req.Status != "" || req.Pinned != nil) {
			errorResponse(w, 403, "仅管理员可以设置状态和置顶")
			return
		}
		c := store.Content{ID: req.ID, Kind: kind, Title: strings.TrimSpace(req.Title), Summary: strings.TrimSpace(req.Summary), Content: strings.TrimSpace(req.Content), Cover: strings.TrimSpace(req.Cover), Category: strings.TrimSpace(req.Category), Status: req.Status}
		if req.Pinned != nil {
			c.Pinned = *req.Pinned
		}
		if c.Status == "" {
			if kind == "news" {
				c.Status = "draft"
			} else {
				c.Status = "published"
			}
		}
		if c.ID < 0 || c.Title == "" || c.Content == "" || utf8.RuneCountInString(c.Title) > 200 || utf8.RuneCountInString(c.Summary) > 1000 || utf8.RuneCountInString(c.Content) > 50000 || utf8.RuneCountInString(c.Category) > 50 || len(c.Cover) > 2048 || !validContentStatus(kind, c.Status) {
			errorResponse(w, 400, "标题和正文必填；标题最多200字、摘要1000字、正文50000字、分类50字，且状态必须有效")
			return
		}
		if c.Cover != "" {
			cover, err := url.Parse(c.Cover)
			if err != nil || cover.Host == "" || (cover.Scheme != "https" && cover.Scheme != "http") {
				errorResponse(w, 400, "封面必须为 http 或 https URL")
				return
			}
		}
		if srv.queuePublication(w, r, u, kind, c.ID, c) {
			return
		}
		if err := srv.store.SaveContent(r.Context(), &c, u.ID, admin); err != nil {
			contentError(w, err)
			return
		}
		item, err := srv.store.GetContent(r.Context(), kind, c.ID, u.ID, true)
		if err != nil {
			contentError(w, err)
			return
		}
		jsonResponse(w, 200, map[string]any{"code": 1, "data": item, "msg": "保存成功"})
	}
}

func (srv *Server) commentsHandler(admin bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		methods := []string{http.MethodGet, http.MethodPost, http.MethodDelete}
		if admin {
			methods = []string{http.MethodGet, http.MethodDelete}
		}
		if !contentMethod(w, r, methods...) {
			return
		}
		if r.Method == http.MethodGet {
			id, ok := contentID(w, r.URL.Query().Get("post_id"))
			if !ok {
				return
			}
			page, size, ok := contentPagination(w, r)
			if !ok {
				return
			}
			items, total, err := srv.store.ListComments(r.Context(), id, page, size, admin)
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
			if !staffPublicationDelete(w, u) {
				return
			}
			id, ok := contentID(w, r.URL.Query().Get("id"))
			if !ok {
				return
			}
			if err := srv.store.DeleteComment(r.Context(), id, u.ID, admin); err != nil {
				contentError(w, err)
				return
			}
			jsonResponse(w, 200, map[string]any{"code": 1, "msg": "删除成功"})
			return
		}
		var req struct {
			PostID  int    `json:"post_id"`
			Content string `json:"content"`
		}
		if !contentBody(w, r, &req) {
			return
		}
		req.Content = strings.TrimSpace(req.Content)
		if req.PostID < 1 || req.Content == "" || utf8.RuneCountInString(req.Content) > 2000 {
			errorResponse(w, 400, "post_id 必须为正整数，评论内容为1–2000字")
			return
		}
		c := store.CommunityComment{PostID: req.PostID, UserID: u.ID, Content: req.Content, AuthorName: u.Nickname, AuthorAvatar: u.Avatar}
		if c.AuthorName == "" {
			c.AuthorName = u.Username
		}
		c.TargetType, c.TargetID = "post", c.PostID
		if srv.queuePublication(w, r, u, "comment", 0, c) {
			return
		}
		if err := srv.store.CreateComment(r.Context(), &c); err != nil {
			contentError(w, err)
			return
		}
		jsonResponse(w, 200, map[string]any{"code": 1, "data": c, "msg": "评论成功"})
	}
}

func (srv *Server) handlePostLike(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost, http.MethodDelete) {
		return
	}
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	var req struct {
		PostID int `json:"post_id"`
	}
	if r.Method == http.MethodPost {
		if !contentBody(w, r, &req) {
			return
		}
	} else {
		var ok bool
		req.PostID, ok = contentID(w, r.URL.Query().Get("post_id"))
		if !ok {
			return
		}
	}
	if req.PostID < 1 {
		errorResponse(w, 400, "post_id 必须为正整数")
		return
	}
	liked := r.Method == http.MethodPost
	count, err := srv.store.SetPostLike(r.Context(), req.PostID, u.ID, liked)
	if err != nil {
		contentError(w, err)
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "data": map[string]any{"liked": liked, "like_count": count}})
}

func (srv *Server) handleNotifications(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodGet, http.MethodDelete) {
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
		if err := srv.store.DeleteNotification(r.Context(), u.ID, id); err != nil {
			contentError(w, err)
			return
		}
		jsonResponse(w, 200, map[string]any{"code": 1, "msg": "删除成功"})
		return
	}
	page, size, ok := contentPagination(w, r)
	if !ok {
		return
	}
	q := store.NotificationQuery{UserID: u.ID, Page: page, PageSize: size, Type: r.URL.Query().Get("type")}
	if q.Type != "" && q.Type != "system" && q.Type != "comment" && q.Type != "like" {
		errorResponse(w, 400, "通知类型无效")
		return
	}
	if r.URL.Query().Has("unread_only") {
		value, err := strconv.ParseBool(r.URL.Query().Get("unread_only"))
		if err != nil {
			errorResponse(w, 400, "unread_only 必须为布尔值")
			return
		}
		q.UnreadOnly = value
	}
	items, total, unread, err := srv.store.ListNotifications(r.Context(), q)
	if err != nil {
		contentError(w, err)
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "data": items, "total": total, "unread_count": unread, "page": page, "page_size": size})
}

func (srv *Server) handleUnreadNotifications(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodGet) {
		return
	}
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	count, err := srv.store.CountUnreadNotifications(r.Context(), u.ID)
	if err != nil {
		contentError(w, err)
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "data": map[string]int{"unread_count": count}})
}

func (srv *Server) handleReadNotifications(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	var req struct {
		IDs []int `json:"ids"`
		All bool  `json:"all"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	ids, ok := uniqueContentIDs(req.IDs)
	if !ok || (req.All && len(ids) > 0) || (!req.All && len(ids) == 0) {
		errorResponse(w, 400, "指定1–1000个正整数 ids 或 all=true，不能同时指定")
		return
	}
	count, err := srv.store.ReadNotifications(r.Context(), u.ID, ids, req.All)
	if err != nil {
		contentError(w, err)
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "data": map[string]int64{"count": count}})
}

func uniqueContentIDs(ids []int) ([]int, bool) {
	if len(ids) > 1000 {
		return nil, false
	}
	seen := make(map[int]bool)
	result := make([]int, 0, len(ids))
	for _, id := range ids {
		if id < 1 {
			return nil, false
		}
		if !seen[id] {
			seen[id] = true
			result = append(result, id)
		}
	}
	return result, true
}

func (srv *Server) handleSendNotification(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	var req struct {
		UserIDs   []int  `json:"user_ids"`
		Broadcast bool   `json:"broadcast"`
		Title     string `json:"title"`
		Content   string `json:"content"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	ids, ok := uniqueContentIDs(req.UserIDs)
	req.Title, req.Content = strings.TrimSpace(req.Title), strings.TrimSpace(req.Content)
	if !ok || (req.Broadcast && len(ids) > 0) || (!req.Broadcast && len(ids) == 0) || req.Title == "" || req.Content == "" || utf8.RuneCountInString(req.Title) > 200 || utf8.RuneCountInString(req.Content) > 5000 {
		errorResponse(w, 400, "标题1–200字，正文1–5000字；指定1–1000个正整数 user_ids 或 broadcast=true")
		return
	}
	count, err := srv.store.SendNotification(r.Context(), &store.Notification{ActorID: u.ID, Title: req.Title, Content: req.Content}, ids, req.Broadcast)
	if err != nil {
		contentError(w, err)
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "data": map[string]int64{"sent_count": count}, "msg": "发送成功"})
}
