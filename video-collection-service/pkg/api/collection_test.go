package api

import (
	"bytes"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"testing"

	"video-collection-service/config"
	"video-collection-service/pkg/ingest"
	"video-collection-service/pkg/store"
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

func TestCollectionRecordsCalibrationEndpoints(t *testing.T) {
	f := newContentFixture(t)

	// 1. 注入样本数据
	f.request("POST", "/api/admin/collection/records/sample", `{"source_id":"tmdb_test","target":"record"}`, f.admin, 200)

	// 2. 查询列表
	res := f.request("GET", "/api/admin/collection/records?source_id=tmdb_test", "", f.admin, 200)
	var total int
	var records []store.CollectionRecord
	json.Unmarshal(res["total"], &total)
	json.Unmarshal(res["data"], &records)
	if total != 5 || len(records) != 5 {
		t.Fatalf("unexpected sample records: total=%d, len=%d", total, len(records))
	}

	// 3. 在线校正 (PUT)
	updatePayload := `{"source_id":"tmdb_test","target":"record","key":"tmdb_person_1892","values":{"name":"成龙大哥","actor_id":"1892","gender":"男"}}`
	f.request("PUT", "/api/admin/collection/records", updatePayload, f.admin, 200)

	// 4. 校正入库转为 Wiki 实体 (POST /to-wiki)
	toWikiPayload := `{
		"source_id": "tmdb_test",
		"target": "record",
		"key": "tmdb_person_1892",
		"subject": {
			"name": "成龙",
			"original_name": "Jackie Chan",
			"type": "person",
			"sub_type": "actor",
			"summary": "著名功夫巨星",
			"infobox": {"性别": "男"}
		}
	}`
	wikiRes := f.request("POST", "/api/admin/collection/records/to-wiki", toWikiPayload, f.admin, 200)
	var sub store.WikiSubject
	json.Unmarshal(wikiRes["data"], &sub)
	if sub.ID <= 0 || sub.Name != "成龙" {
		t.Fatalf("rectify to wiki failed: %+v", sub)
	}

	// 5. 删除记录 (DELETE)
	f.request("DELETE", "/api/admin/collection/records?source_id=tmdb_test&target=record&key=tmdb_person_1892", "", f.admin, 200)
	resAfter := f.request("GET", "/api/admin/collection/records?source_id=tmdb_test", "", f.admin, 200)
	var totalAfter int
	json.Unmarshal(resAfter["total"], &totalAfter)
	if totalAfter != 4 {
		t.Fatalf("expected 4 records after delete, got %d", totalAfter)
	}
}

