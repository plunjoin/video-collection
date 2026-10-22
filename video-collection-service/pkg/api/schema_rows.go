package api

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"video-collection-service/pkg/store"
)

func (srv *Server) handleSchemaRows(w http.ResponseWriter, r *http.Request) {
	parts := strings.Split(strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/admin/schema/"), "/"), "/")
	if (len(parts) != 2 && len(parts) != 3) || parts[0] == "" || parts[1] != "rows" ||
		(len(parts) == 3 && parts[2] != "save" && parts[2] != "batch-delete") {
		errorResponse(w, http.StatusNotFound, "Not Found")
		return
	}
	slug := parts[0]
	b, err := srv.store.GetBusinessType(r.Context(), slug)
	if err != nil {
		schemaRowsError(w, err)
		return
	}
	if b.Writer == "article" || b.Writer == "video" {
		errorResponse(w, http.StatusBadRequest, "请使用专用资讯或视频接口")
		return
	}
	if len(parts) == 3 {
		if r.Method != http.MethodPost {
			errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
			return
		}
		if b.Writer != "table" {
			errorResponse(w, http.StatusBadRequest, "仅自定义表支持保存和批量删除")
			return
		}
		if parts[2] == "save" {
			srv.saveSchemaRow(w, r, slug)
			return
		}
		var req struct {
			IDs []int `json:"ids"`
		}
		if !contentBody(w, r, &req) {
			return
		}
		if err = srv.store.BatchDeleteBusinessTypeRows(r.Context(), slug, req.IDs); err != nil {
			schemaRowsError(w, err)
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "删除成功"})
		return
	}

	query := r.URL.Query()
	switch r.Method {
	case http.MethodGet:
		if b.Writer == "record" && (query.Has("id") || query.Has("source_id") || query.Has("key")) {
			sourceID, key := strings.TrimSpace(query.Get("source_id")), strings.TrimSpace(query.Get("key"))
			if sourceID == "" || key == "" {
				errorResponse(w, http.StatusBadRequest, "读取通用数据需要 source_id 和 key")
				return
			}
			record, err := srv.store.GetCollectionRecord(r.Context(), sourceID, "record", key)
			if err != nil {
				schemaRowsError(w, err)
				return
			}
			jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": schemaRecordRow(*record)})
			return
		}
		if query.Has("id") {
			id, ok := contentID(w, query.Get("id"))
			if !ok {
				return
			}
			row, err := srv.store.GetBusinessTypeRow(r.Context(), slug, id)
			if err != nil {
				schemaRowsError(w, err)
				return
			}
			jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": row})
			return
		}
		page, size, ok := contentPagination(w, r)
		if !ok {
			return
		}
		var rows any
		var total int
		if b.Writer == "record" {
			var records []store.CollectionRecord
			records, total, err = srv.store.ListCollectionRecordsByTarget(r.Context(), "record", page, size)
			items := make([]map[string]any, 0, len(records))
			for _, record := range records {
				items = append(items, schemaRecordRow(record))
			}
			rows = items
		} else {
			filters := make(map[string]string)
			for key, values := range query {
				switch key {
				case "page", "page_size", "id", "key":
					continue
				}
				if len(values) != 1 {
					errorResponse(w, http.StatusBadRequest, "筛选参数不能重复: "+key)
					return
				}
				filters[key] = values[0]
			}
			rows, total, err = srv.store.ListBusinessTypeRowsFiltered(r.Context(), slug, page, size, filters)
		}
		if err != nil {
			schemaRowsError(w, err)
			return
		}
		contentListResponse(w, rows, total, page, size)
	case http.MethodDelete:
		if b.Writer == "record" {
			sourceID, key := strings.TrimSpace(query.Get("source_id")), strings.TrimSpace(query.Get("key"))
			if sourceID == "" || key == "" {
				errorResponse(w, http.StatusBadRequest, "删除通用数据需要 source_id 和 key")
				return
			}
			err = srv.store.DeleteCollectionRecord(r.Context(), sourceID, "record", key)
		} else {
			id, ok := contentID(w, query.Get("id"))
			if !ok {
				return
			}
			err = srv.store.DeleteBusinessTypeRow(r.Context(), slug, id)
		}
		if err != nil {
			schemaRowsError(w, err)
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "删除成功"})
	default:
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	}
}

func (srv *Server) saveSchemaRow(w http.ResponseWriter, r *http.Request, slug string) {
	var body map[string]json.RawMessage
	if !contentBody(w, r, &body) {
		return
	}
	if body == nil {
		errorResponse(w, http.StatusBadRequest, "请求必须为 JSON 对象")
		return
	}
	var id int
	if raw, ok := body["id"]; ok {
		var err error
		id, err = strconv.Atoi(string(raw))
		if err != nil || id < 0 {
			errorResponse(w, http.StatusBadRequest, "id 必须为非负整数")
			return
		}
	}
	var sourceID, key string
	if raw, ok := body["source_id"]; ok {
		if err := json.Unmarshal(raw, &sourceID); err != nil {
			errorResponse(w, http.StatusBadRequest, "source_id 必须为字符串")
			return
		}
	}
	if raw, ok := body["key"]; ok {
		if err := json.Unmarshal(raw, &key); err != nil {
			errorResponse(w, http.StatusBadRequest, "key 必须为字符串")
			return
		}
	}
	values := make(map[string]string, len(body))
	for name, raw := range body {
		if name == "id" || name == "source_id" || name == "key" {
			continue
		}
		var value string
		if err := json.Unmarshal(raw, &value); err != nil || string(raw) == "null" {
			var compact bytes.Buffer
			if err = json.Compact(&compact, raw); err != nil {
				errorResponse(w, http.StatusBadRequest, "字段 JSON 无效: "+name)
				return
			}
			value = compact.String()
		}
		values[name] = value
	}
	id, err := srv.store.SaveBusinessTypeRow(r.Context(), slug, id, sourceID, key, values)
	if err != nil {
		schemaRowsError(w, err)
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "保存成功", "id": id})
}

func schemaRecordRow(record store.CollectionRecord) map[string]any {
	return map[string]any{
		"source_id":  record.SourceID,
		"target":     record.Target,
		"key":        record.Key,
		"record_key": record.Key,
		"values":     record.Values,
		"payload":    record.Values,
		"content_id": record.ContentID,
		"updated_at": record.UpdatedAt,
	}
}

func schemaRowsError(w http.ResponseWriter, err error) {
	status := http.StatusBadRequest
	if errors.Is(err, sql.ErrNoRows) {
		status = http.StatusNotFound
	}
	errorResponse(w, status, err.Error())
}
