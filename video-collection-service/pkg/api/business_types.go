package api

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
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
			}
		default:
			errorResponse(w, 405, "Method Not Allowed")
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
			var f store.BusinessTypeField
			if !decode(&f) {
				return
			}
			err = srv.store.UpdateBusinessTypeField(r.Context(), slug, parts[2], f)
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
	jsonResponse(w, 200, map[string]any{"code": 1, "data": data})
}
