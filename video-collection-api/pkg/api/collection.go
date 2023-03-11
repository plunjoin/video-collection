package api

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"video-collection-api/config"
	"video-collection-api/pkg/auth"
	"video-collection-api/pkg/ingest"
)

func (srv *Server) registerCollectionRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/api/admin/collection/preview", auth.AdminRequired(srv.store, srv.handleCollectionPreview))
	mux.HandleFunc("/api/admin/collection/upload", auth.AdminRequired(srv.store, srv.handleCollectionUpload))
	mux.HandleFunc("/api/admin/collection/records", auth.AdminRequired(srv.store, srv.handleCollectionRecords))
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
	if r.Method != http.MethodGet {
		errorResponse(w, 405, "Method Not Allowed")
		return
	}
	source := r.URL.Query().Get("source_id")
	if source == "" {
		errorResponse(w, 400, "缺少 source_id")
		return
	}
	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	size, _ := strconv.Atoi(r.URL.Query().Get("page_size"))
	rows, total, err := srv.store.ListCollectionRecords(r.Context(), source, page, size)
	if err != nil {
		errorResponse(w, 500, "读取采集结果失败")
		return
	}
	jsonResponse(w, 200, map[string]any{"code": 1, "data": rows, "total": total})
}
