package api

import (
	"encoding/json"
	"net/http"
	"strconv"

	"video-collection-service/pkg/store"
)

func (srv *Server) registerWikiRoutes(mux *http.ServeMux) {
	// 公开词条查询与图谱检索接口
	mux.HandleFunc("/api/wiki/subjects", srv.handleWikiSubjects)
	mux.HandleFunc("/api/wiki/subject", srv.handleWikiSubjectDetail)
	mux.HandleFunc("/api/wiki/graph", srv.handleWikiGraph)

	// 管理员专属管理接口
	mux.HandleFunc("/api/admin/wiki/subjects", srv.adminWrite(srv.handleAdminWikiSubjects))
	mux.HandleFunc("/api/admin/wiki/relations", srv.adminWrite(srv.handleAdminWikiRelations))
	mux.HandleFunc("/api/admin/wiki/sync-video", srv.adminWrite(srv.handleAdminWikiSyncVideo))
}

// handleWikiSubjects 公开检索词条列表
func (srv *Server) handleWikiSubjects(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}

	q := r.URL.Query()
	page, _ := strconv.Atoi(q.Get("page"))
	pageSize, _ := strconv.Atoi(q.Get("page_size"))

	query := store.WikiSubjectQuery{
		Page:     page,
		PageSize: pageSize,
		Type:     q.Get("type"),
		SubType:  q.Get("sub_type"),
		Keyword:  q.Get("keyword"),
	}

	list, total, err := srv.store.ListWikiSubjects(r.Context(), query)
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "检索词条失败: "+err.Error())
		return
	}

	jsonResponse(w, http.StatusOK, map[string]any{
		"code":  1,
		"data":  list,
		"total": total,
		"page":  query.Page,
	})
}

// handleWikiSubjectDetail 获取词条完整详情与关系图
func (srv *Server) handleWikiSubjectDetail(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}

	id, _ := strconv.Atoi(r.URL.Query().Get("id"))
	if id <= 0 {
		name := r.URL.Query().Get("name")
		if name != "" {
			sub, err := srv.store.GetWikiSubjectByName(r.Context(), name)
			if err != nil || sub == nil {
				errorResponse(w, http.StatusNotFound, "词条不存在")
				return
			}
			id = sub.ID
		} else {
			errorResponse(w, http.StatusBadRequest, "缺少 id 或 name 参数")
			return
		}
	}

	detail, err := srv.store.GetWikiSubjectByID(r.Context(), id)
	if err != nil {
		errorResponse(w, http.StatusNotFound, "词条不存在: "+err.Error())
		return
	}

	jsonResponse(w, http.StatusOK, map[string]any{
		"code": 1,
		"data": detail,
	})
}

// handleWikiGraph 获取以某词条为中心的关联图谱数据
func (srv *Server) handleWikiGraph(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}

	id, _ := strconv.Atoi(r.URL.Query().Get("id"))
	if id <= 0 {
		errorResponse(w, http.StatusBadRequest, "缺少有效的 id 参数")
		return
	}
	depth, _ := strconv.Atoi(r.URL.Query().Get("depth"))
	if depth <= 0 {
		depth = 1
	}

	graph, err := srv.store.GetWikiGraph(r.Context(), id, depth)
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "生成图谱数据失败: "+err.Error())
		return
	}

	jsonResponse(w, http.StatusOK, map[string]any{
		"code": 1,
		"data": graph,
	})
}

// handleAdminWikiSubjects 管理员词条增删改
func (srv *Server) handleAdminWikiSubjects(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	switch r.Method {
	case http.MethodPost:
		var sub store.WikiSubject
		if err := json.NewDecoder(r.Body).Decode(&sub); err != nil {
			errorResponse(w, http.StatusBadRequest, "参数解析失败")
			return
		}
		id, err := srv.store.CreateWikiSubject(ctx, &sub)
		if err != nil {
			errorResponse(w, http.StatusBadRequest, err.Error())
			return
		}
		if srv.rag != nil {
			srv.rag.IndexWikiSubjectAsync(ctx, id)
		}
		jsonResponse(w, http.StatusOK, map[string]any{
			"code": 1,
			"msg":  "词条创建成功",
			"id":   id,
		})

	case http.MethodPut:
		var sub store.WikiSubject
		if err := json.NewDecoder(r.Body).Decode(&sub); err != nil {
			errorResponse(w, http.StatusBadRequest, "参数解析失败")
			return
		}
		if err := srv.store.UpdateWikiSubject(ctx, &sub); err != nil {
			errorResponse(w, http.StatusBadRequest, err.Error())
			return
		}
		if srv.rag != nil {
			srv.rag.IndexWikiNeighborhoodAsync(sub.ID)
		}
		jsonResponse(w, http.StatusOK, map[string]any{
			"code": 1,
			"msg":  "词条更新成功",
		})

	case http.MethodDelete:
		id, _ := strconv.Atoi(r.URL.Query().Get("id"))
		if id <= 0 {
			errorResponse(w, http.StatusBadRequest, "缺少有效 id 参数")
			return
		}
		var neighbors []int
		if srv.rag != nil {
			if graph, err := srv.store.GetWikiGraph(ctx, id, 1); err == nil && graph != nil {
				for _, node := range graph.Nodes {
					if node.ID != id {
						neighbors = append(neighbors, node.ID)
					}
				}
			}
		}
		if err := srv.store.DeleteWikiSubject(ctx, id); err != nil {
			errorResponse(w, http.StatusInternalServerError, err.Error())
			return
		}
		if srv.rag != nil {
			srv.rag.RemoveWikiSubjectAsync(id, neighbors...)
		}
		jsonResponse(w, http.StatusOK, map[string]any{
			"code": 1,
			"msg":  "词条已成功删除",
		})

	default:
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	}
}

// handleAdminWikiRelations 管理员关系连线增删
func (srv *Server) handleAdminWikiRelations(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	switch r.Method {
	case http.MethodPost:
		var rel store.WikiRelation
		if err := json.NewDecoder(r.Body).Decode(&rel); err != nil {
			errorResponse(w, http.StatusBadRequest, "参数解析失败")
			return
		}
		id, err := srv.store.CreateWikiRelation(ctx, &rel)
		if err != nil {
			errorResponse(w, http.StatusBadRequest, err.Error())
			return
		}
		if srv.rag != nil {
			srv.rag.IndexWikiSubjectsAsync(rel.SourceID, rel.TargetID)
		}
		jsonResponse(w, http.StatusOK, map[string]any{
			"code": 1,
			"msg":  "关系关联成功",
			"id":   id,
		})

	case http.MethodDelete:
		id, _ := strconv.Atoi(r.URL.Query().Get("id"))
		if id <= 0 {
			errorResponse(w, http.StatusBadRequest, "缺少有效 id 参数")
			return
		}
		var srcID, tgtID int
		if rel, _ := srv.store.GetWikiRelationByID(ctx, id); rel != nil {
			srcID, tgtID = rel.SourceID, rel.TargetID
		}
		if err := srv.store.DeleteWikiRelation(ctx, id); err != nil {
			errorResponse(w, http.StatusInternalServerError, err.Error())
			return
		}
		if srv.rag != nil && (srcID > 0 || tgtID > 0) {
			srv.rag.IndexWikiSubjectsAsync(srcID, tgtID)
		}
		jsonResponse(w, http.StatusOK, map[string]any{
			"code": 1,
			"msg":  "关系已解除",
		})

	default:
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	}
}

// handleAdminWikiSyncVideo 一键将视频库影片冷启动转化为 Wiki 作品和人物图谱
func (srv *Server) handleAdminWikiSyncVideo(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}

	var req struct {
		VideoID int `json:"video_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.VideoID <= 0 {
		errorResponse(w, http.StatusBadRequest, "请提供有效的 video_id")
		return
	}

	subject, err := srv.store.SyncVideoToWikiSubject(r.Context(), req.VideoID)
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "同步到 Wiki 知识库失败: "+err.Error())
		return
	}
	if srv.rag != nil && subject != nil && subject.ID > 0 {
		srv.rag.IndexWikiNeighborhoodAsync(subject.ID)
	}

	jsonResponse(w, http.StatusOK, map[string]any{
		"code":    1,
		"msg":     "视频已成功同步入库并生成知识图谱",
		"subject": subject,
	})
}
