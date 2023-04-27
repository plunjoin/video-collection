package api

import (
	"bytes"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"testing"

	"video-collection-api/config"
	"video-collection-api/pkg/ingest"
	"video-collection-api/pkg/store"
)

func TestCollectionUploadPreviewAndSave(t *testing.T) {
	f := newContentFixture(t)
	t.Setenv("COLLECTION_UPLOAD_DIR", t.TempDir())
	for _, path := range []string{"/api/admin/collection/preview", "/api/admin/collection/upload"} {
		f.request("POST", path, `{}`, nil, 401)
		f.request("POST", path, `{}`, f.alice, 401)
	}
	f.request("GET", "/api/admin/collection/records?source_id=rule", "", f.alice, 401)
	f.request("GET", "/api/admin/collection/preview", "", f.admin, 405)
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	part, err := writer.CreateFormFile("file", "articles.csv")
	if err != nil {
		t.Fatal(err)
	}
	part.Write([]byte("ID,标题,正文\n1,文章,测试正文\n"))
	writer.Close()
	r := httptest.NewRequest("POST", "/api/admin/collection/upload", &body)
	r.Header.Set("Content-Type", writer.FormDataContentType())
	r.Header.Set("Authorization", "Bearer "+f.tokens[f.admin.ID])
	w := httptest.NewRecorder()
	f.mux.ServeHTTP(w, r)
	if w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	var uploaded struct {
		Data struct {
			Token string `json:"token"`
		}
	}
	json.Unmarshal(w.Body.Bytes(), &uploaded)
	src := config.SourceConfig{ID: "rule", Name: "文章导入", Type: "pipeline", PageLimit: 1, TimeoutSec: 15, Filter: config.FilterRule{Pipeline: &config.PipelineRule{Version: 1, Input: "file", Target: "article", KeyField: "id", Duplicate: "update", MaxRecords: 100, File: config.ImportFileRule{Token: uploaded.Data.Token, HeaderRow: 1}, Fields: []config.FieldRule{{Target: "id", Selector: "ID"}, {Target: "title", Selector: "标题"}, {Target: "content", Selector: "正文"}}}}}
	data, _ := json.Marshal(src)
	result := decodeContentData[[]ingest.Sample](t, f.request("POST", "/api/admin/collection/preview", string(data), f.admin, 200))
	if len(result) != 1 || result[0].Values["title"] != "文章" {
		t.Fatalf("preview failed: %+v", result)
	}
	rows := decodeContentData[[]store.CollectionRecord](t, f.request("GET", "/api/admin/collection/records?source_id=rule", "", f.admin, 200))
	if len(rows) != 0 {
		t.Fatal("preview wrote content")
	}
	f.request("POST", "/api/admin/sources", string(data), f.admin, 200)
	sources := decodeContentData[[]config.SourceConfig](t, f.request("GET", "/api/admin/sources", "", f.admin, 200))
	if len(sources) != 1 || sources[0].Filter.Pipeline.File.Token != uploaded.Data.Token {
		t.Fatalf("save failed: %+v", sources)
	}
	src.Filter.Pipeline.KeyField = "missing"
	data, _ = json.Marshal(src)
	f.request("POST", "/api/admin/sources", string(data), f.admin, http.StatusBadRequest)
}
