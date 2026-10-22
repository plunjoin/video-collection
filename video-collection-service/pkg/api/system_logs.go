package api

import (
	"net/http"
	"strings"
	"unicode/utf8"

	"video-collection-service/pkg/auth"
	"video-collection-service/pkg/store"
)

func (srv *Server) registerSystemLogRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/api/admin/system-logs", auth.AdminRequired(srv.store, srv.handleSystemLogs))
}

func (srv *Server) handleSystemLogs(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	page, size, ok := contentPagination(w, r)
	if !ok {
		return
	}
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if utf8.RuneCountInString(q) > 200 {
		errorResponse(w, http.StatusBadRequest, "关键词过长")
		return
	}
	logs, total, err := srv.store.ListSystemLogs(r.Context(), store.SystemLogQuery{
		Level:    strings.TrimSpace(r.URL.Query().Get("level")),
		Category: strings.TrimSpace(r.URL.Query().Get("category")),
		Q:        q,
		Page:     page,
		PageSize: size,
	})
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{
		"code":      1,
		"data":      logs,
		"total":     total,
		"page":      page,
		"page_size": size,
	})
}

// logSystem 写入系统审计日志；失败不影响主流程。
func (srv *Server) logSystem(r *http.Request, level, category, message string, meta map[string]any) {
	if srv == nil || srv.store == nil || strings.TrimSpace(message) == "" {
		return
	}
	entry := store.SystemLog{
		Level:    level,
		Category: category,
		Message:  message,
		Meta:     meta,
	}
	if r != nil {
		if u := auth.GetCurrentUser(r, srv.store); u != nil {
			entry.ActorID = u.ID
			entry.ActorName = strings.TrimSpace(u.Nickname)
			if entry.ActorName == "" {
				entry.ActorName = u.Username
			}
		}
	}
	_ = srv.store.AppendSystemLog(r.Context(), entry)
}

func (srv *Server) logSystemActor(r *http.Request, actorID int, actorName, level, category, message string, meta map[string]any) {
	if srv == nil || srv.store == nil || strings.TrimSpace(message) == "" {
		return
	}
	ctx := r.Context()
	entry := store.SystemLog{
		Level:     level,
		Category:  category,
		Message:   message,
		ActorID:   actorID,
		ActorName: strings.TrimSpace(actorName),
		Meta:      meta,
	}
	_ = srv.store.AppendSystemLog(ctx, entry)
}
