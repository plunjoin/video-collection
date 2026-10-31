package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"video-collection-service/pkg/auth"
	"video-collection-service/pkg/rag"
)

func (srv *Server) registerRAGRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/api/admin/rag/rebuild", auth.AdminRequired(srv.store, srv.handleAdminRAGRebuild))
	mux.HandleFunc("/api/admin/rag/search", auth.AdminRequired(srv.store, srv.handleAdminRAGSearch))
	mux.HandleFunc("/api/admin/rag/ask", auth.AdminRequired(srv.store, srv.handleAdminRAGAsk))

	// 公开只读接口：门户 AI 问答与语义检索；未配置对话模型时 ask 自动降级为检索模式
	mux.HandleFunc("/api/rag/search", srv.handleRAGSearch)
	mux.HandleFunc("/api/rag/ask", srv.handleRAGAsk)
}

// ragEntityRef 将检索命中映射为可跳转的实体引用，供前端渲染引用链接。
type ragEntityRef struct {
	SourceType string `json:"source_type"`
	SourceID   string `json:"source_id"`
	SubjectID  int    `json:"subject_id,omitempty"`
	Title      string `json:"title,omitempty"`
	URL        string `json:"url,omitempty"`
}

// ragRefs 从命中块的元数据提取实体跳转：资讯/帖子回链详情页，词条给出 ID 与名称。
func ragRefs(hits []rag.StoredChunk) []ragEntityRef {
	refs := make([]ragEntityRef, 0, len(hits))
	for _, hit := range hits {
		ref := ragEntityRef{SourceType: hit.SourceType, SourceID: hit.SourceID, SubjectID: hit.SubjectID}
		switch hit.SourceType {
		case rag.SourceNews:
			ref.Title, _ = hit.Metadata["title"].(string)
			ref.URL = "/news/" + hit.SourceID
		case rag.SourcePost:
			ref.Title, _ = hit.Metadata["title"].(string)
			ref.URL = "/community/" + hit.SourceID
		case rag.SourceWikiSubject, rag.SourceWikiRelation:
			ref.Title, _ = hit.Metadata["subject_name"].(string)
		}
		refs = append(refs, ref)
	}
	return refs
}

func (srv *Server) handleRAGAsk(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	if srv.rag == nil {
		errorResponse(w, http.StatusServiceUnavailable, "RAG 服务未启用")
		return
	}
	var req struct {
		Q          string `json:"q"`
		Query      string `json:"query"`
		TopK       int    `json:"top_k"`
		SourceType string `json:"source_type"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&req); err != nil {
		errorResponse(w, http.StatusBadRequest, "参数解析失败")
		return
	}
	query := strings.TrimSpace(req.Query)
	if query == "" {
		query = strings.TrimSpace(req.Q)
	}
	if query == "" {
		errorResponse(w, http.StatusBadRequest, "查询文本不能为空")
		return
	}

	// 未配置对话模型时降级：仅返回检索结果与引用，避免门户问答不可用。
	if !srv.rag.ChatConfigured() {
		search, err := srv.rag.Search(r.Context(), query, req.TopK, req.SourceType)
		if err != nil {
			errorResponse(w, http.StatusBadRequest, "RAG 检索失败: "+err.Error())
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{
			"code": 1,
			"data": map[string]any{
				"query":     search.Query,
				"answer":    "",
				"mode":      "retrieval",
				"note":      "未配置对话模型（OPENAI_API_KEY），当前为检索模式：以下为知识库命中片段与引用。",
				"citations": search.Results,
				"refs":      ragRefs(search.Results),
				"embedder":  srv.rag.EmbedderName(),
				"top_k":     search.TopK,
			},
		})
		return
	}

	result, err := srv.rag.Ask(r.Context(), query, req.TopK, req.SourceType)
	if err != nil {
		status := http.StatusInternalServerError
		if errors.Is(err, rag.ErrChat) {
			status = http.StatusBadGateway
		}
		errorResponse(w, status, "RAG 问答失败: "+err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{
		"code": 1,
		"data": map[string]any{
			"query":      result.Query,
			"answer":     result.Answer,
			"mode":       "chat",
			"citations":  result.Citations,
			"refs":       ragRefs(result.Citations),
			"model":      result.Model,
			"embedder":   result.Embedder,
			"top_k":      result.TopK,
			"graph_note": result.GraphNote,
		},
	})
}

func (srv *Server) handleRAGSearch(w http.ResponseWriter, r *http.Request) {
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
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&req); err != nil {
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

	// 公开接口限制返回规模，防止全表向量扫描被滥用。
	if topK <= 0 {
		topK = 8
	}
	if topK > 20 {
		topK = 20
	}
	result, err := srv.rag.Search(r.Context(), query, topK, sourceType)
	if err != nil {
		errorResponse(w, http.StatusBadRequest, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{
		"code": 1,
		"data": map[string]any{
			"query":    result.Query,
			"top_k":    result.TopK,
			"results":  result.Results,
			"refs":     ragRefs(result.Results),
			"embedder": srv.rag.EmbedderName(),
		},
	})
}

func (srv *Server) handleAdminRAGAsk(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	if srv.rag == nil {
		errorResponse(w, http.StatusServiceUnavailable, "RAG 服务未启用")
		return
	}
	var req struct {
		Q          string `json:"q"`
		Query      string `json:"query"`
		TopK       int    `json:"top_k"`
		SourceType string `json:"source_type"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		errorResponse(w, http.StatusBadRequest, "参数解析失败")
		return
	}
	query := strings.TrimSpace(req.Query)
	if query == "" {
		query = strings.TrimSpace(req.Q)
	}
	if query == "" {
		errorResponse(w, http.StatusBadRequest, "查询文本不能为空")
		return
	}
	result, err := srv.rag.Ask(r.Context(), query, req.TopK, req.SourceType)
	if err != nil {
		status := http.StatusInternalServerError
		if errors.Is(err, rag.ErrChat) {
			status = http.StatusBadGateway
		}
		errorResponse(w, status, "RAG 问答失败: "+err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": result})
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
