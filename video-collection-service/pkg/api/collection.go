package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"video-collection-service/config"
	"video-collection-service/pkg/auth"
	"video-collection-service/pkg/collector"
	"video-collection-service/pkg/ingest"
	"video-collection-service/pkg/store"
)

func (srv *Server) registerCollectionRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/api/admin/collection/preview", auth.AdminRequired(srv.store, srv.handleCollectionPreview))
	mux.HandleFunc("/api/admin/collection/upload", auth.AdminRequired(srv.store, srv.handleCollectionUpload))
	mux.HandleFunc("/api/admin/collection/records", auth.AdminRequired(srv.store, srv.handleCollectionRecords))
	mux.HandleFunc("/api/admin/collection/records/to-wiki", auth.AdminRequired(srv.store, srv.handleRectifyRecordToWiki))
	mux.HandleFunc("/api/admin/collection/records/to-video", auth.AdminRequired(srv.store, srv.handleRectifyRecordToVideo))
	mux.HandleFunc("/api/admin/collection/records/batch-rectify", auth.AdminRequired(srv.store, srv.handleBatchRectifyRecords))
	mux.HandleFunc("/api/admin/collection/records/sample", auth.AdminRequired(srv.store, srv.handleImportSampleRecords))
	mux.HandleFunc("/api/admin/collection/tasks", auth.AdminRequired(srv.store, srv.handleCollectionTasks))
	mux.HandleFunc("/api/admin/collection/tasks/detail", auth.AdminRequired(srv.store, srv.handleCollectionTaskDetail))
	mux.HandleFunc("/api/admin/collection/logs", auth.AdminRequired(srv.store, srv.handleCollectionLogs))
	mux.HandleFunc("/api/admin/collection/logs/cleanup", auth.AdminRequired(srv.store, srv.handleClearCollectionLogs))
}

func (srv *Server) handleCollectionPreview(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, 405, "Method Not Allowed")
		return
	}
	var src config.SourceConfig
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024*1024)).Decode(&src); err != nil {
		errorResponse(w, 400, "规则 JSON 无效或超过 1 MB")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 25*time.Second)
	defer cancel()
	rows := []ingest.Sample{}
	err := ingest.Run(ctx, src, 10, func(s ingest.Sample) error { rows = append(rows, s); return nil })
	if err != nil {
		errorResponse(w, 400, err.Error())
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "data": rows, "msg": "最多预览 10 条，未写入内容库"})
}

func (srv *Server) handleCollectionUpload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, 405, "Method Not Allowed")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 21*1024*1024)
	if err := r.ParseMultipartForm(2 * 1024 * 1024); err != nil {
		if r.MultipartForm != nil {
			r.MultipartForm.RemoveAll()
		}
		errorResponse(w, 400, "文件上传失败，上限 20 MB")
		return
	}
	defer r.MultipartForm.RemoveAll()
	f, header, err := r.FormFile("file")
	if err != nil {
		errorResponse(w, 400, "请选择导入文件")
		return
	}
	defer f.Close()
	token, err := ingest.SaveUpload(header.Filename, f)
	if err != nil {
		errorResponse(w, 400, err.Error())
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "data": map[string]string{"token": token, "name": header.Filename}})
}

func (srv *Server) handleCollectionRecords(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		source := r.URL.Query().Get("source_id")
		if source == "" {
			errorResponse(w, 400, "缺少 source_id")
			return
		}
		page, _ := strconv.Atoi(r.URL.Query().Get("page"))
		size, _ := strconv.Atoi(r.URL.Query().Get("page_size"))
		rows, total, err := srv.store.ListCollectionRecords(r.Context(), source, page, size)
		if err != nil {
			errorResponse(w, 500, "读取采集结果失败: "+err.Error())
			return
		}
		jsonResponse(w, 200, map[string]any{"code": 1, "data": rows, "total": total})

	case http.MethodPut:
		var req struct {
			SourceID string            `json:"source_id"`
			Target   string            `json:"target"`
			Key      string            `json:"key"`
			Values   map[string]string `json:"values"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			errorResponse(w, 400, "参数格式错误")
			return
		}
		if req.SourceID == "" || req.Key == "" {
			errorResponse(w, 400, "缺少 source_id 或 key")
			return
		}
		if req.Target == "" {
			req.Target = "record"
		}
		if err := srv.store.UpdateCollectionRecord(r.Context(), req.SourceID, req.Target, req.Key, req.Values); err != nil {
			errorResponse(w, 500, "校正数据失败: "+err.Error())
			return
		}
		jsonResponse(w, 200, map[string]any{"code": 1, "msg": "采集记录已成功校正更新"})

	case http.MethodDelete:
		source := r.URL.Query().Get("source_id")
		target := r.URL.Query().Get("target")
		key := r.URL.Query().Get("key")
		if target == "" {
			target = "record"
		}
		if source == "" || key == "" {
			errorResponse(w, 400, "缺少 source_id 或 key")
			return
		}
		if err := srv.store.DeleteCollectionRecord(r.Context(), source, target, key); err != nil {
			errorResponse(w, 500, "删除记录失败: "+err.Error())
			return
		}
		jsonResponse(w, 200, map[string]any{"code": 1, "msg": "采集记录已成功删除"})

	default:
		errorResponse(w, 405, "Method Not Allowed")
	}
}

func (srv *Server) handleRectifyRecordToWiki(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, 405, "Method Not Allowed")
		return
	}
	var req struct {
		SourceID string            `json:"source_id"`
		Target   string            `json:"target"`
		Key      string            `json:"key"`
		Subject  store.WikiSubject `json:"subject"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		errorResponse(w, 400, "参数格式错误")
		return
	}
	if req.Target == "" {
		req.Target = "record"
	}
	sub, err := srv.store.RectifyCollectionRecordToWiki(r.Context(), req.SourceID, req.Target, req.Key, req.Subject)
	if err != nil {
		errorResponse(w, 500, "校正转入 Wiki 失败: "+err.Error())
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "msg": "已校正并入库为 Wiki 实体", "data": sub})
}

func (srv *Server) handleRectifyRecordToVideo(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, 405, "Method Not Allowed")
		return
	}
	var req struct {
		SourceID string               `json:"source_id"`
		Target   string               `json:"target"`
		Key      string               `json:"key"`
		PlayURL  string               `json:"play_url"`
		PlayFrom string               `json:"play_from"`
		Video    collector.CleanedVod `json:"video"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		errorResponse(w, 400, "参数格式错误")
		return
	}
	if req.Target == "" {
		req.Target = "video"
	}
	if len(req.Video.PlayGroups) == 0 && req.PlayURL != "" {
		playFrom := req.PlayFrom
		if playFrom == "" {
			playFrom = "m3u8"
		}
		groups := collector.ParsePlayGroups(playFrom, "", "", req.PlayURL)
		for i := range groups {
			if groups[i].SourceID == "" {
				groups[i].SourceID = req.SourceID
			}
		}
		req.Video.PlayGroups = groups
	}
	vid, err := srv.store.RectifyCollectionRecordToVideo(r.Context(), req.SourceID, req.Target, req.Key, &req.Video)
	if err != nil {
		errorResponse(w, 500, "校正转入视频库失败: "+err.Error())
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "msg": "已校正并入库到视频库", "data": map[string]any{"id": vid}})
}

func (srv *Server) handleImportSampleRecords(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, 405, "Method Not Allowed")
		return
	}
	var req struct {
		SourceID string `json:"source_id"`
		Target   string `json:"target"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	if req.SourceID == "" {
		req.SourceID = "demo_rule"
	}
	if req.Target == "" {
		req.Target = "record"
	}
	count, err := srv.store.ImportSampleCollectionRecords(r.Context(), req.SourceID, req.Target)
	if err != nil {
		errorResponse(w, 500, "导入演职样本数据失败: "+err.Error())
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "msg": fmt.Sprintf("已成功注入 %d 条演职样本采集数据", count), "data": map[string]any{"count": count}})
}

func (srv *Server) handleBatchRectifyRecords(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, 405, "Method Not Allowed")
		return
	}
	var req struct {
		SourceID string `json:"source_id"`
		Target   string `json:"target"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	count, err := srv.store.BatchRectifyCollectionRecords(r.Context(), req.SourceID, req.Target)
	if err != nil {
		errorResponse(w, 500, "批量数据校正失败: "+err.Error())
		return
	}
	jsonResponse(w, 200, map[string]any{
		"code": 1,
		"msg":  fmt.Sprintf("已成功完成数据校正，共智能校正入库 %d 条实体记录", count),
		"data": map[string]any{"rectified_count": count},
	})
}

func (srv *Server) handleCollectionTasks(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		errorResponse(w, 405, "Method Not Allowed")
		return
	}
	q := r.URL.Query()
	page, _ := strconv.Atoi(q.Get("page"))
	pageSize, _ := strconv.Atoi(q.Get("page_size"))
	sourceID := q.Get("source_id")
	status := q.Get("status")
	triggerType := q.Get("trigger_type")

	tasks, total, err := srv.store.ListCollectionTasks(r.Context(), store.CollectionTaskQuery{
		SourceID:    sourceID,
		Status:      status,
		TriggerType: triggerType,
		Page:        page,
		PageSize:    pageSize,
	})
	if err != nil {
		errorResponse(w, 500, err.Error())
		return
	}

	// 实时补全正在运行中的内存统计
	if srv.scheduler != nil {
		liveProgress := srv.scheduler.GetProgressList()
		for i := range tasks {
			if tasks[i].Status == "running" {
				if prog, ok := liveProgress[tasks[i].SourceID]; ok && prog.IsRunning {
					tasks[i].TotalFetched = prog.TotalFetched
					tasks[i].TotalSaved = prog.TotalSaved
					tasks[i].TotalSkipped = prog.TotalSkipped
				}
			}
		}
	}

	jsonResponse(w, 200, map[string]any{
		"code":      1,
		"data":      tasks,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

func (srv *Server) handleCollectionTaskDetail(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		errorResponse(w, 405, "Method Not Allowed")
		return
	}
	id, _ := strconv.Atoi(r.URL.Query().Get("id"))
	if id <= 0 {
		errorResponse(w, 400, "缺少有效任务 ID")
		return
	}
	task, err := srv.store.GetCollectionTask(r.Context(), id)
	if err != nil {
		errorResponse(w, 500, err.Error())
		return
	}
	if task == nil {
		errorResponse(w, 404, "任务记录不存在")
		return
	}

	logs, _, _ := srv.store.ListCollectionLogs(r.Context(), store.CollectionLogQuery{
		TaskID:   id,
		PageSize: 500,
	})

	jsonResponse(w, 200, map[string]any{
		"code": 1,
		"data": map[string]any{
			"task": task,
			"logs": logs,
		},
	})
}

func (srv *Server) handleCollectionLogs(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		errorResponse(w, 405, "Method Not Allowed")
		return
	}
	q := r.URL.Query()
	page, _ := strconv.Atoi(q.Get("page"))
	pageSize, _ := strconv.Atoi(q.Get("page_size"))
	taskID, _ := strconv.Atoi(q.Get("task_id"))
	sourceID := q.Get("source_id")
	level := q.Get("level")
	keyword := q.Get("keyword")

	logs, total, err := srv.store.ListCollectionLogs(r.Context(), store.CollectionLogQuery{
		TaskID:   taskID,
		SourceID: sourceID,
		Level:    level,
		Keyword:  keyword,
		Page:     page,
		PageSize: pageSize,
	})
	if err != nil {
		errorResponse(w, 500, err.Error())
		return
	}

	jsonResponse(w, 200, map[string]any{
		"code":      1,
		"data":      logs,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

func (srv *Server) handleClearCollectionLogs(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, 405, "Method Not Allowed")
		return
	}
	var req struct {
		Days int `json:"days"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	if req.Days <= 0 {
		req.Days = 15
	}
	deleted, err := srv.store.ClearCollectionLogs(r.Context(), req.Days)
	if err != nil {
		errorResponse(w, 500, err.Error())
		return
	}
	jsonResponse(w, 200, map[string]any{
		"code": 1,
		"msg":  fmt.Sprintf("已成功清理 %d 天前的历史采集日志（共 %d 条）", req.Days, deleted),
		"data": map[string]any{"deleted": deleted},
	})
}

