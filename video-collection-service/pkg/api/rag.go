package api

import (
	"encoding/json"
	"net/http"
	"strconv"

	"video-collection-service/pkg/auth"
)

func (srv *Server) registerRAGRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/api/admin/rag/rebuild", auth.AdminRequired(srv.store, srv.handleAdminRAGRebuild))
	mux.HandleFunc("/api/admin/rag/search", auth.AdminRequired(srv.store, srv.handleAdminRAGSearch))
}

func (srv *Server) handleAdminRAGRebuild(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	if srv.rag == nil {
		errorResponse(w, http.StatusServiceUnavailable, "RAG 服务未启用")
		return
	}
	n, err := srv.rag.RebuildAll(r.Context())
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "重建索引失败: "+err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{
		"code":           1,
		"msg":            "RAG 索引重建完成",
		"chunks_indexed": n,
		"embedder":       srv.rag.EmbedderName(),
	})
}

func (srv *Server) handleAdminRAGSearch(w http.ResponseWriter, r *http.Request) {
	if srv.rag == nil {
		errorResponse(w, http.StatusServiceUnavailable, "RAG 服务未启用")
		return
	}
	var query string
	var topK int
	var sourceType string

	switch r.Method {
	case http.MethodGet:
		q := r.URL.Query()
		query = q.Get("q")
		if query == "" {
			query = q.Get("query")
		}
		topK, _ = strconv.Atoi(q.Get("top_k"))
		sourceType = q.Get("source_type")
	case http.MethodPost:
		var req struct {
			Query      string `json:"query"`
			Q          string `json:"q"`
			TopK       int    `json:"top_k"`
			SourceType string `json:"source_type"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			errorResponse(w, http.StatusBadRequest, "参数解析失败")
			return
		}
		query = req.Query
		if query == "" {
			query = req.Q
		}
		topK = req.TopK
		sourceType = req.SourceType
	default:
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}

	result, err := srv.rag.Search(r.Context(), query, topK, sourceType)
	if err != nil {
		errorResponse(w, http.StatusBadRequest, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{
		"code": 1,
		"data": result,
	})
}
