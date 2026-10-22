package api

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"video-collection-service/config"
	"video-collection-service/pkg/auth"
	"video-collection-service/pkg/store"
)

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
