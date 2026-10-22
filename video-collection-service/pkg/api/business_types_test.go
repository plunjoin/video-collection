package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"

	"video-collection-service/config"
	"video-collection-service/pkg/auth"
	"video-collection-service/pkg/store"
)

func TestBusinessTypeRowsAdminAPI(t *testing.T) {
	f := newContentFixture(t)
	ctx := context.Background()
	f.request("POST", "/api/admin/business-types", `{"slug":"row_item","name":"Rows","fields":[{"name":"title","label":"标题","required":true},{"name":"meta","data_type":"json"}]}`, f.admin, 200)
	if _, err := f.s.SaveCollectionRecord(ctx, store.CollectionRecord{SourceID: "source-a", Target: "row_item", Key: "external-1", Values: map[string]string{"title": "第一条", "meta": `{"ok":true}`}}, false); err != nil {
		t.Fatal(err)
	}
	result := f.request("GET", "/api/admin/business-types/row_item/rows?page=1&page_size=10", "", f.admin, 200)
	rows := decodeContentData[[]map[string]any](t, result)
	if len(rows) != 1 || rows[0]["source_id"] != "source-a" || rows[0]["title"] != "第一条" {
		t.Fatalf("rows: %+v", rows)
	}
	rowID, ok := rows[0]["id"].(float64)
	if !ok || rowID < 1 {
		t.Fatalf("row id: %+v", rows[0]["id"])
	}
	f.request("DELETE", fmt.Sprintf("/api/admin/business-types/row_item/rows?id=%d", int(rowID)), "", f.admin, 200)
	result = f.request("GET", "/api/admin/business-types/row_item/rows", "", f.admin, 200)
	if string(result["total"]) != "0" {
		t.Fatalf("row was not deleted: %s", result)
	}
	if _, err := f.s.SaveCollectionRecord(ctx, store.CollectionRecord{SourceID: "source-r", Target: "record", Key: "record-1", Values: map[string]string{"name": "通用"}}, false); err != nil {
		t.Fatal(err)
	}
	result = f.request("GET", "/api/admin/business-types/record/rows", "", f.admin, 200)
	records := decodeContentData[[]map[string]any](t, result)
	if len(records) != 1 || records[0]["key"] != "record-1" || records[0]["target"] != "record" {
		t.Fatalf("record rows: %+v", records)
	}
	f.request("DELETE", "/api/admin/business-types/record/rows?source_id=source-r&key=record-1", "", f.admin, 200)
	f.request("GET", "/api/admin/business-types/article/rows", "", f.admin, 400)
	f.request("GET", "/api/admin/business-types/missing/rows", "", f.admin, 404)
}

func TestBusinessTypeAdminAPI(t *testing.T) {
	f := newContentFixture(t)
	f.request("GET", "/api/admin/business-types", "", nil, 401)
	f.request("POST", "/api/admin/business-types", `{"slug":"demo_item","name":"Demo"}`, f.alice, 401)
	types := decodeContentData[[]store.BusinessType](t, f.request("GET", "/api/admin/business-types", "", f.admin, 200))
	if len(types) != 3 {
		t.Fatal(types)
	}
	f.request("POST", "/api/admin/business-types", `{"slug":"demo_item","name":"Demo","table_name":"users"}`, f.admin, 400)
	f.request("POST", "/api/admin/business-types", `{"slug":"demo_item","name":"Demo","fields":[{"name":"title","required":true},{"name":"score","data_type":"integer"}]}`, f.admin, 200)
	b := decodeContentData[store.BusinessType](t, f.request("GET", "/api/admin/business-types/demo_item", "", f.admin, 200))
	if b.IsSystem || b.Writer != "table" || b.TableName != "biz_demo_item" {
		t.Fatal(b)
	}
	f.request("PUT", "/api/admin/business-types/demo_item", `{"name":"Renamed","description":"Description"}`, f.admin, 200)
	f.request("POST", "/api/admin/business-types/demo_item/fields", `{"name":"extra","data_type":"json"}`, f.admin, 200)
	f.request("PUT", "/api/admin/business-types/demo_item/fields/extra", `{"name":"extra","label":"Extras","required":true}`, f.admin, 200)
	f.request("PUT", "/api/admin/business-types/demo_item/fields/extra", `{"name":"renamed"}`, f.admin, 400)
	f.request("DELETE", "/api/admin/business-types/demo_item/fields/extra", "", f.admin, 200)
	f.request("POST", "/api/admin/business-types/article/fields", `{"name":"extra","data_type":"text"}`, f.admin, 200)
	f.request("PUT", "/api/admin/business-types/article/fields/title", `{"label":"标题"}`, f.admin, 200)
	f.request("DELETE", "/api/admin/business-types/article/fields/title", "", f.admin, 400)
	f.request("PUT", "/api/admin/business-types/article/fields/title", `{"name":"title","data_type":"integer","required":true}`, f.admin, 400)
	f.request("DELETE", "/api/admin/business-types/article", "", f.admin, 400)
	f.request("GET", "/api/admin/business-types/missing", "", f.admin, 404)
	for _, role := range []string{"observer", "operator"} {
		u := &store.User{Username: role, Role: role, Status: 1}
		if err := f.s.CreateUser(context.Background(), u); err != nil {
			t.Fatal(err)
		}
		token := auth.DefaultSessionManager.CreateSession(u)
		f.tokens[u.ID] = token
		t.Cleanup(func() { auth.DefaultSessionManager.DeleteSession(token) })
		code := 200
		if role == "operator" {
			code = 403
		}
		f.request("GET", "/api/admin/business-types", "", u, code)
		f.request("POST", "/api/admin/business-types", `{"slug":"denied_item","name":"Denied"}`, u, 403)
	}
	f.request("DELETE", "/api/admin/business-types/demo_item", "", f.admin, 200)
	f.request("GET", "/api/admin/business-types/demo_item", "", f.admin, 404)
}

func TestCollectorWebhookRegisteredTargets(t *testing.T) {
	for _, target := range []string{"demo_item", "video", "record", "missing"} {
		t.Run(target, func(t *testing.T) {
			s, mux := newWebhookMux(t)
			ctx := context.Background()
			const secret = "biz-secret"
			if err := s.CreateBusinessType(ctx, store.BusinessType{Slug: "demo_item", Name: "Demo", Fields: []store.BusinessTypeField{{Name: "title", Required: true}, {Name: "external_id"}}}); err != nil {
				t.Fatal(err)
			}
			saveWebhookSource(t, s, "acg-news", secret, "", true)
			src, err := s.GetSourceByID(ctx, "acg-news")
			if err != nil {
				t.Fatal(err)
			}
			src.Filter.Pipeline = &config.PipelineRule{Target: target}
			if err = s.SaveSource(ctx, *src); err != nil {
				t.Fatal(err)
			}
			body := []byte(`[{"id":42,"source":"test","title_original":"Registry title"}]`)
			w := postCollector(mux, body, secret, http.Header{})
			if target == "missing" {
				if w.Code != 400 {
					t.Fatal(w.Code, w.Body.String())
				}
				return
			}
			if w.Code != 200 {
				t.Fatal(w.Code, w.Body.String())
			}
			rows, total, err := s.ListCollectionRecords(ctx, "acg-news", 1, 10)
			if err != nil || total != 1 || rows[0].Target != target {
				t.Fatalf("audit: %+v %v", rows, err)
			}
			if target != "record" && rows[0].ContentID == 0 {
				t.Fatal("writer did not create content")
			}
			w = postCollector(mux, body, secret, http.Header{})
			if w.Code != 200 {
				t.Fatal(w.Body.String())
			}
			rows, total, err = s.ListCollectionRecords(ctx, "acg-news", 1, 10)
			if err != nil || total != 1 {
				t.Fatalf("dedupe: %+v %v", rows, err)
			}
		})
	}
}

func TestSavePipelineRegisteredTarget(t *testing.T) {
	f := newContentFixture(t)
	f.request("POST", "/api/admin/business-types", `{"slug":"demo_item","name":"Demo","fields":[{"name":"score","data_type":"integer","required":true}]}`, f.admin, 200)
	src := config.SourceConfig{ID: "biz-rule", Name: "Biz", Type: "pipeline", API: "https://example.com", PageLimit: 1, TimeoutSec: 5, Filter: config.FilterRule{Pipeline: &config.PipelineRule{Version: 1, Input: "api", Target: "demo_item", KeyField: "score", Duplicate: "update", MaxRecords: 10, Fields: []config.FieldRule{{Target: "score", Selector: "score"}}}}}
	body, _ := json.Marshal(src)
	f.request("POST", "/api/admin/sources", string(body), f.admin, 200)
	f.request("DELETE", "/api/admin/business-types/demo_item", "", f.admin, 400)
	src.Filter.Pipeline.Target = "missing"
	body, _ = json.Marshal(src)
	f.request("POST", "/api/admin/sources", string(body), f.admin, 400)
}

func TestCollectorWebhookCustomFieldsWithoutTitle(t *testing.T) {
	s, mux := newWebhookMux(t)
	ctx := context.Background()
	const secret = "custom-fields"
	err := s.CreateBusinessType(ctx, store.BusinessType{Slug: "demo_item", Name: "Demo", Fields: []store.BusinessTypeField{{Name: "score", DataType: "integer", Required: true}, {Name: "details", DataType: "json"}}})
	if err != nil {
		t.Fatal(err)
	}
	saveWebhookSource(t, s, "acg-news", secret, "", true)
	src, err := s.GetSourceByID(ctx, "acg-news")
	if err != nil {
		t.Fatal(err)
	}
	src.Filter.Pipeline = &config.PipelineRule{Target: "demo_item"}
	if err = s.SaveSource(ctx, *src); err != nil {
		t.Fatal(err)
	}
	w := postCollector(mux, []byte(`[{"id":1,"score":7,"details":{"tag":"demo"}}]`), secret, http.Header{})
	if w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	rows, total, err := s.ListCollectionRecords(ctx, "acg-news", 1, 10)
	if err != nil || total != 1 || rows[0].Values["score"] != "7" || rows[0].Values["details"] != `{"tag":"demo"}` {
		t.Fatalf("custom webhook: %+v %v", rows, err)
	}
	w = postCollector(mux, []byte(`[{"id":2,"score":"invalid"}]`), secret, http.Header{})
	if w.Code != 400 {
		t.Fatal(w.Code, w.Body.String())
	}
}

func TestCollectorWebhookVideoPlaybackFields(t *testing.T) {
	s, mux := newWebhookMux(t)
	ctx := context.Background()
	const secret = "video-fields"
	saveWebhookSource(t, s, "acg-news", secret, "", true)
	src, err := s.GetSourceByID(ctx, "acg-news")
	if err != nil {
		t.Fatal(err)
	}
	src.Filter.Pipeline = &config.PipelineRule{Target: "video"}
	if err = s.SaveSource(ctx, *src); err != nil {
		t.Fatal(err)
	}
	w := postCollector(mux, []byte(`[{"id":1,"title_original":"Video","play_url":"第01集$https://example.com/1.m3u8","play_from":"m3u8"}]`), secret, http.Header{})
	if w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	rows, _, err := s.ListCollectionRecords(ctx, "acg-news", 1, 10)
	if err != nil || len(rows) != 1 {
		t.Fatalf("records: %+v %v", rows, err)
	}
	video, err := s.GetVideoByID(ctx, rows[0].ContentID)
	if err != nil || len(video.PlayGroups) != 1 || len(video.PlayGroups[0].Episodes) != 1 {
		t.Fatalf("playback: %+v %v", video, err)
	}
}
