package api

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"video-collection-service/pkg/store"
)

func (srv *Server) handleBusinessTypes(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/api/admin/business-types")
	parts := strings.Split(strings.Trim(path, "/"), "/")
	slug := ""
	if path != "" && path != "/" {
		slug = parts[0]
	}
	var data any
	var err error
	var total int
	var page, pageSize int
	decode := func(dst any) bool {
		dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
		// Reject table/writer/is_system and other routing properties. These belong
		// exclusively to the store, never to an administrative mapping request.
		dec.DisallowUnknownFields()
		if e := dec.Decode(dst); e != nil {
			errorResponse(w, 400, "参数无效: "+e.Error())
			return false
		}
		return true
	}
	switch {
	case slug == "":
		switch r.Method {
		case http.MethodGet:
			data, err = srv.store.ListBusinessTypes(r.Context())
		case http.MethodPost:
			var req struct {
				Slug        string                    `json:"slug"`
				Name        string                    `json:"name"`
				Description string                    `json:"description"`
				Fields      []store.BusinessTypeField `json:"fields"`
			}
			if !decode(&req) {
				return
			}
			err = srv.store.CreateBusinessType(r.Context(), store.BusinessType{Slug: req.Slug, Name: req.Name, Description: req.Description, Fields: req.Fields})
			if err == nil {
				data, err = srv.store.GetBusinessType(r.Context(), req.Slug)
				if err == nil {
					srv.logSystem(r, "info", "admin", "创建业务类型 "+req.Slug, map[string]any{"slug": req.Slug, "name": req.Name})
				}
			}
		default:
			errorResponse(w, 405, "Method Not Allowed")
			return
		}
	case len(parts) == 2 && parts[1] == "rows":
		switch r.Method {
		case http.MethodGet:
			page, pageSize, _ = contentPagination(w, r)
			if page == 0 {
				return
			}
			var b *store.BusinessType
			b, err = srv.store.GetBusinessType(r.Context(), slug)
			if err == nil {
				switch b.Writer {
				case "article", "video":
					err = errors.New("系统业务类型请使用专用资讯或视频页面")
				case "record":
					var records []store.CollectionRecord
					records, total, err = srv.store.ListCollectionRecordsByTarget(r.Context(), "record", page, pageSize)
					data = make([]map[string]any, 0, len(records))
					for _, record := range records {
						data = append(data.([]map[string]any), map[string]any{
							"source_id":  record.SourceID,
							"target":     record.Target,
							"key":        record.Key,
							"record_key": record.Key,
							"values":     record.Values,
							"payload":    record.Values,
							"content_id": record.ContentID,
							"updated_at": record.UpdatedAt,
						})
					}
				default:
					data, total, err = srv.store.ListBusinessTypeRows(r.Context(), slug, page, pageSize)
				}
			}
		case http.MethodDelete:
			b, getErr := srv.store.GetBusinessType(r.Context(), slug)
			if getErr != nil {
				err = getErr
				break
			}
			if b.Writer == "record" {
				sourceID := strings.TrimSpace(r.URL.Query().Get("source_id"))
				key := strings.TrimSpace(r.URL.Query().Get("key"))
				if sourceID == "" || key == "" {
					errorResponse(w, http.StatusBadRequest, "删除通用数据需要 source_id 和 key")
					return
				}
				err = srv.store.DeleteCollectionRecord(r.Context(), sourceID, "record", key)
			} else if b.Writer == "article" || b.Writer == "video" {
				errorResponse(w, http.StatusBadRequest, "系统业务类型请使用专用资讯或视频页面")
				return
			} else {
				id, parseErr := strconv.Atoi(r.URL.Query().Get("id"))
				if parseErr != nil || id < 1 {
					errorResponse(w, http.StatusBadRequest, "id 必须为正整数")
					return
				}
				err = srv.store.DeleteBusinessTypeRow(r.Context(), slug, id)
			}
		default:
			errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
			return
		}
	case len(parts) == 1:
		switch r.Method {
		case http.MethodGet:
			data, err = srv.store.GetBusinessType(r.Context(), slug)
		case http.MethodPut:
			var req struct {
				Name        string `json:"name"`
				Description string `json:"description"`
			}
			if !decode(&req) {
				return
			}
			err = srv.store.UpdateBusinessType(r.Context(), slug, req.Name, req.Description)
		case http.MethodDelete:
			err = srv.store.DeleteBusinessType(r.Context(), slug)
			if err == nil {
				srv.logSystem(r, "warn", "admin", "删除业务类型 "+slug, map[string]any{"slug": slug})
			}
		default:
			errorResponse(w, 405, "Method Not Allowed")
			return
		}
	case len(parts) == 2 && parts[1] == "fields" && r.Method == http.MethodPost:
		var f store.BusinessTypeField
		if !decode(&f) {
			return
		}
		err = srv.store.AddBusinessTypeField(r.Context(), slug, f)
	case len(parts) == 3 && parts[1] == "fields":
		switch r.Method {
		case http.MethodPut:
			var req struct {
				Name       string    `json:"name"`
				Label      string    `json:"label"`
				DataType   string    `json:"data_type"`
				Required   *bool     `json:"required"`
				Filterable *bool     `json:"filterable"`
				Options    *[]string `json:"options"`
			}
			if !decode(&req) {
				return
			}
			var b *store.BusinessType
			b, err = srv.store.GetBusinessType(r.Context(), slug)
			if err == nil {
				err = sql.ErrNoRows
				for _, old := range b.Fields {
					if old.Name == parts[2] {
						field := old
						if req.Name != "" {
							field.Name = req.Name
						}
						if req.DataType != "" {
							field.DataType = req.DataType
						}
						field.Label = req.Label
						if req.Required != nil {
							field.Required = *req.Required
						}
						if req.Filterable != nil {
							field.Filterable = *req.Filterable
						}
						if req.Options != nil {
							field.Options = *req.Options
						}
						err = srv.store.UpdateBusinessTypeField(r.Context(), slug, parts[2], field)
						break
					}
				}
			}

		case http.MethodDelete:
			err = srv.store.DeleteBusinessTypeField(r.Context(), slug, parts[2])
		default:
			errorResponse(w, 405, "Method Not Allowed")
			return
		}
	default:
		errorResponse(w, 404, "Not Found")
		return
	}
	if err != nil {
		status := 400
		if errors.Is(err, sql.ErrNoRows) {
			status = 404
		}
		errorResponse(w, status, err.Error())
		return
	}
	response := map[string]any{"code": 1, "data": data}
	if page > 0 {
		response["total"] = total
		response["page"] = page
		response["page_size"] = pageSize
	}
	jsonResponse(w, 200, response)
}
