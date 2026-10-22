package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"strings"
	"testing"

	"video-collection-service/pkg/store"
)

func newSchemaRowsFixture(t *testing.T) *contentFixture {
	t.Helper()
	f := newContentFixture(t)
	f.request("POST", "/api/admin/business-types", `{
		"slug":"schema_item","name":"Schema rows","fields":[
			{"name":"title","data_type":"text","required":true},
			{"name":"notes","data_type":"text"},
			{"name":"status","data_type":"enum","required":true,"options":["draft","live"]},
			{"name":"meta","data_type":"json"},
			{"name":"count","data_type":"integer"},
			{"name":"score","data_type":"real"},
			{"name":"enabled","data_type":"boolean"},
			{"name":"private","data_type":"text","filterable":false}
		]}`, f.admin, 200)
	return f
}

func schemaSavedID(t *testing.T, result map[string]json.RawMessage) int {
	t.Helper()
	var id int
	if err := json.Unmarshal(result["id"], &id); err != nil || id < 1 {
		t.Fatalf("save id: %s (%v)", result, err)
	}
	if string(result["code"]) != "1" || string(result["msg"]) != `"保存成功"` {
		t.Fatalf("save response: %s", result)
	}
	return id
}

func TestSchemaRowsCRUD(t *testing.T) {
	f := newSchemaRowsFixture(t)
	const base = "/api/admin/schema/schema_item/rows"
	f.request("GET", base, "", nil, 401)
	f.request("POST", base+"/save", `{}`, f.alice, 401)
	for _, body := range []string{
		`{"title":"Bad","status":"missing"}`,
		`{"title":"Bad","status":""}`,
		`{"status":"live"}`,
		`null`, `[]`, `{} {}`,
		`{"id":-1}`, `{"id":"1"}`, `{"id":1.2}`, `{"id":null}`,
		`{"source_id":123}`, `{"key":123}`,
	} {
		f.request("POST", base+"/save", body, f.admin, 400)
	}
	result := f.request("GET", base, "", f.admin, 200)
	if string(result["total"]) != "0" {
		t.Fatalf("invalid saves wrote rows: %s", result)
	}
	id := schemaSavedID(t, f.request("POST", base+"/save", `{
		"title":"First","status":"draft","count":3,"score":1.5,"enabled":true,
		"meta": {"tags": ["a", "b"]}, "extra": [1, 2], "nullable":null
	}`, f.admin, 200))
	rowPath := fmt.Sprintf("%s?id=%d", base, id)
	row := decodeContentData[map[string]any](t, f.request("GET", rowPath, "", f.admin, 200))
	if row["title"] != "First" || row["count"] != float64(3) || row["score"] != 1.5 || row["source_id"] != "manual" {
		t.Fatalf("saved row: %+v", row)
	}
	if len(row["meta"].(map[string]any)["tags"].([]any)) != 2 {
		t.Fatalf("json field: %+v", row)
	}
	payload := row["payload"].(map[string]any)
	if payload["meta"] != `{"tags":["a","b"]}` || payload["extra"] != `[1,2]` || payload["nullable"] != "null" || payload["enabled"] != "true" {
		t.Fatalf("coercion: %+v", payload)
	}
	var identity []string
	if err := json.Unmarshal([]byte(row["record_key"].(string)), &identity); err != nil || len(identity) != 2 || identity[0] != "manual" || !strings.HasPrefix(identity[1], "manual-") {
		t.Fatalf("default identity: %+v (%v)", identity, err)
	}
	updatedID := schemaSavedID(t, f.request("POST", base+"/save", fmt.Sprintf(`{"id":%d,"source_id":"changed","key":"changed","title":"Updated","status":"live","meta":[1,2]}`, id), f.admin, 200))
	if updatedID != id {
		t.Fatalf("update changed id: %d -> %d", id, updatedID)
	}
	row = decodeContentData[map[string]any](t, f.request("GET", rowPath, "", f.admin, 200))
	if row["title"] != "Updated" || row["source_id"] != "manual" || row["record_key"] != stringMustJSON(t, identity) {
		t.Fatalf("update identity: %+v", row)
	}
	record, err := f.s.GetCollectionRecord(context.Background(), identity[0], "schema_item", identity[1])
	if err != nil || record.ContentID != id || record.Values["title"] != "Updated" {
		t.Fatalf("audit: %+v (%v)", record, err)
	}
	f.request("POST", base+"/save", fmt.Sprintf(`{"id":%d,"title":"Invalid update","status":"bad"}`, id), f.admin, 400)
	row = decodeContentData[map[string]any](t, f.request("GET", rowPath, "", f.admin, 200))
	if row["title"] != "Updated" {
		t.Fatal("invalid update changed row", row)
	}
	f.request("DELETE", rowPath, "", f.admin, 200)
	f.request("GET", rowPath, "", f.admin, 404)
	if exists, err := f.s.HasCollectionRecord(context.Background(), identity[0], "schema_item", identity[1]); err != nil || exists {
		t.Fatalf("deleted audit remains: %v %v", exists, err)
	}
	first := schemaSavedID(t, f.request("POST", base+"/save", `{"source_id":"source","key":"one","title":"One","status":"live"}`, f.admin, 200))
	upsert := schemaSavedID(t, f.request("POST", base+"/save", `{"source_id":"source","key":"one","title":"One again","status":"live"}`, f.admin, 200))
	if upsert != first {
		t.Fatalf("upsert changed id: %d %d", first, upsert)
	}
	second := schemaSavedID(t, f.request("POST", base+"/save", `{"source_id":"other","key":"one","title":"Two","status":"draft"}`, f.admin, 200))
	result = f.request("GET", base+"?page=2&page_size=1", "", f.admin, 200)
	if string(result["total"]) != "2" || string(result["page"]) != "2" || string(result["page_size"]) != "1" || len(decodeContentData[[]map[string]any](t, result)) != 1 {
		t.Fatalf("pagination: %s", result)
	}
	for _, body := range []string{`{"ids":[]}`, `{}`, `{"ids":[0]}`, `{"ids":[-1]}`, `{"ids":["1"]}`} {
		f.request("POST", base+"/batch-delete", body, f.admin, 400)
	}
	f.request("POST", base+"/batch-delete", fmt.Sprintf(`{"ids":[%d,999999]}`, first), f.admin, 404)
	f.request("GET", fmt.Sprintf("%s?id=%d", base, first), "", f.admin, 200)
	if exists, err := f.s.HasCollectionRecord(context.Background(), "source", "schema_item", "one"); err != nil || !exists {
		t.Fatalf("failed batch did not roll back audit: %v %v", exists, err)
	}
	f.request("POST", base+"/batch-delete", fmt.Sprintf(`{"ids":[%d,%d,%d]}`, first, second, first), f.admin, 200)
	result = f.request("GET", base, "", f.admin, 200)
	if string(result["total"]) != "0" || len(decodeContentData[[]map[string]any](t, result)) != 0 {
		t.Fatalf("batch deletion: %s", result)
	}
	for _, source := range []string{"source", "other"} {
		if exists, err := f.s.HasCollectionRecord(context.Background(), source, "schema_item", "one"); err != nil || exists {
			t.Fatalf("batch audit remains: %v %v", exists, err)
		}
	}
	f.request("POST", base+"/save", `{"id":999999,"title":"Missing","status":"draft"}`, f.admin, 404)
	f.request("DELETE", base+"?id=999999", "", f.admin, 404)
}

func stringMustJSON(t *testing.T, value any) string {
	t.Helper()
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestSchemaRowsFilters(t *testing.T) {
	f := newSchemaRowsFixture(t)
	const base = "/api/admin/schema/schema_item/rows"
	for _, body := range []string{
		`{"source_id":"a","key":"1","title":"Alpha","notes":"other","status":"live","count":1,"score":1.5,"enabled":true,"private":"secret"}`,
		`{"source_id":"b","key":"2","title":"Beta","notes":"Alpha notes","status":"live","count":3,"score":3.5,"enabled":false}`,
		`{"source_id":"a","key":"3","title":"Gamma","status":"draft","count":5,"score":5.5,"enabled":true}`,
	} {
		f.request("POST", base+"/save", body, f.admin, 200)
	}
	for _, tc := range []struct {
		query string
		total int
	}{
		{"status=live", 2}, {"status=draft", 1}, {"title=Alpha", 1},
		{"q=Alpha", 2}, {"q=absent", 0}, {"q=secret", 0}, {"q=", 3},
		{"count=3", 1}, {"count_min=2&count_max=5", 2},
		{"score=1.5", 1}, {"score_min=2&score_max=4", 1},
		{"enabled=true", 2}, {"enabled=false", 1}, {"source_id=a", 2},
		{"source_id=a%25", 0},
		{"created_at_min=2000-01-01T00:00:00Z", 3}, {"created_at_min=9999-01-01T00:00:00Z", 0},
		{"created_at_max=9999-01-01T00:00:00Z", 3}, {"created_at_max=2000-01-01T00:00:00Z", 0},
		{"updated_at_min=2000-01-01T00:00:00Z", 3}, {"updated_at_min=9999-01-01T00:00:00Z", 0},
		{"updated_at_max=9999-01-01T00:00:00Z", 3}, {"updated_at_max=2000-01-01T00:00:00Z", 0},
		{"created_at_min=2000&created_at_max=9999&updated_at_min=2000&updated_at_max=9999&status=live", 2},
		{"status=live&count_min=2&enabled=false&q=Alpha&source_id=b", 1},
		{"status=live&page=2&page_size=1", 2}, {"status=draft&page=2&page_size=1", 1},
		{"title=" + url.QueryEscape(`Alpha' OR 1=1 --`), 0},
	} {
		t.Run(tc.query, func(t *testing.T) {
			result := f.request("GET", base+"?"+tc.query, "", f.admin, 200)
			if string(result["total"]) != fmt.Sprint(tc.total) {
				t.Fatalf("filtered total: %s, want %d", result, tc.total)
			}
		})
	}
	for _, query := range []string{
		"meta=x", "meta_min=1", "unknown_field=x", "private=secret", "private_min=1",
		"created_at=x", "updated_at=x", "created_at_other=x", "updated_at_min_other=x",
		"status=missing", "status=", "status_min=live", "title_min=A", "enabled_min=true",
		"count=oops", "count=1.1", "count_min=oops", "score=NaN", "score_max=Inf",
		"enabled=1", "enabled=TRUE", "status=live&status=draft", "source_id=a&source_id=b",
		"page=0", "page_size=101", "id=0", "id=oops", url.QueryEscape(`title" OR 1=1 --`) + "=x",
	} {
		f.request("GET", base+"?"+query, "", f.admin, 400)
	}
	// Old business-types row routes retain their pagination-only behavior.
	result := f.request("GET", "/api/admin/business-types/schema_item/rows?status=missing&unknown_field=x", "", f.admin, 200)
	if string(result["total"]) != "3" {
		t.Fatalf("legacy filtering changed: %s", result)
	}
}

func TestSchemaFieldEnumAndFilterableAdminAPI(t *testing.T) {
	f := newSchemaRowsFixture(t)
	getFields := func() map[string]store.BusinessTypeField {
		t.Helper()
		b := decodeContentData[store.BusinessType](t, f.request("GET", "/api/admin/business-types/schema_item", "", f.admin, 200))
		fields := make(map[string]store.BusinessTypeField)
		for _, field := range b.Fields {
			fields[field.Name] = field
		}
		return fields
	}
	fields := getFields()
	for _, name := range []string{"title", "status", "count", "score", "enabled"} {
		if !fields[name].Filterable {
			t.Fatalf("default filterability: %+v", fields[name])
		}
	}
	if fields["meta"].Filterable || fields["private"].Filterable || strings.Join(fields["status"].Options, ",") != "draft,live" {
		t.Fatalf("field metadata: %+v", fields)
	}
	const fieldBase = "/api/admin/business-types/schema_item/fields"
	for _, body := range []string{
		`{"name":"bad_enum","data_type":"enum"}`, `{"name":"bad_enum","data_type":"enum","options":[]}`,
		`{"name":"bad_json","data_type":"json","filterable":true}`, `{"name":"bad","unknown":true}`,
	} {
		f.request("POST", fieldBase, body, f.admin, 400)
	}
	f.request("POST", fieldBase, `{"name":"kind","data_type":"enum","options":["one","two"],"filterable":false}`, f.admin, 200)
	f.request("POST", fieldBase, `{"name":"extra","options":["ignored"]}`, f.admin, 200)
	fields = getFields()
	if fields["kind"].Filterable || !fields["extra"].Filterable || len(fields["extra"].Options) != 0 {
		t.Fatalf("added metadata: %+v", fields)
	}
	f.request("POST", "/api/admin/schema/schema_item/rows/save", `{"title":"Alpha","notes":"searchable","status":"live","kind":"one"}`, f.admin, 200)
	f.request("PUT", fieldBase+"/title", `{"filterable":false}`, f.admin, 200)
	f.request("PUT", fieldBase+"/private", `{"filterable":true}`, f.admin, 200)
	f.request("PUT", fieldBase+"/kind", `{"options":["one","three"],"filterable":true}`, f.admin, 200)
	f.request("PUT", fieldBase+"/kind", `{"label":"Kind"}`, f.admin, 200)
	fields = getFields()
	if fields["title"].Filterable || !fields["private"].Filterable || !fields["kind"].Filterable || strings.Join(fields["kind"].Options, ",") != "one,three" {
		t.Fatalf("updated metadata: %+v", fields)
	}
	f.request("GET", "/api/admin/schema/schema_item/rows?title=Alpha", "", f.admin, 400)
	f.request("GET", "/api/admin/schema/schema_item/rows?private=anything", "", f.admin, 200)
	f.request("GET", "/api/admin/schema/schema_item/rows?kind=three", "", f.admin, 200)
	f.request("GET", "/api/admin/schema/schema_item/rows?kind=two", "", f.admin, 400)
	result := f.request("GET", "/api/admin/schema/schema_item/rows?q=Alpha", "", f.admin, 200)
	if string(result["total"]) != "0" {
		t.Fatalf("q searched disabled text: %s", result)
	}
	f.request("PUT", fieldBase+"/title", `{"filterable":true}`, f.admin, 200)
	if !getFields()["title"].Filterable {
		t.Fatal("title filterability was not restored")
	}
	for _, query := range []string{"title=Alpha", "q=Alpha"} {
		result = f.request("GET", "/api/admin/schema/schema_item/rows?"+query, "", f.admin, 200)
		if string(result["total"]) != "1" {
			t.Fatalf("restored title filter: %s", result)
		}
	}
	for _, body := range []string{`{"options":[]}`, `{"name":"renamed"}`, `{"data_type":"text"}`} {
		f.request("PUT", fieldBase+"/kind", body, f.admin, 400)
	}
	f.request("PUT", fieldBase+"/meta", `{"filterable":true}`, f.admin, 400)
	f.request("PUT", fieldBase+"/extra", `{"options":["ignored"],"filterable":false}`, f.admin, 200)
	if len(getFields()["extra"].Options) != 0 {
		t.Fatal("non-enum options persisted")
	}
	f.request("POST", "/api/admin/schema/schema_item/rows/save", `{"title":"Other","status":"live","kind":"two"}`, f.admin, 400)
	f.request("POST", "/api/admin/business-types", `{"slug":"bad_schema","name":"Bad","fields":[{"name":"meta","data_type":"json","filterable":true}]}`, f.admin, 400)
	f.request("POST", "/api/admin/business-types", `{"slug":"bad_schema","name":"Bad","fields":[{"name":"kind","data_type":"enum"}]}`, f.admin, 400)
}

func TestSchemaRowsRecordAndDedicatedWriters(t *testing.T) {
	f := newContentFixture(t)
	ctx := context.Background()
	if _, err := f.s.SaveCollectionRecord(ctx, store.CollectionRecord{SourceID: "source", Target: "record", Key: "one", Values: map[string]string{"name": "Record"}}, false); err != nil {
		t.Fatal(err)
	}
	result := f.request("GET", "/api/admin/schema/record/rows?unknown=ignored&q=ignored&page_size=1", "", f.admin, 200)
	rows := decodeContentData[[]map[string]any](t, result)
	if len(rows) != 1 || rows[0]["source_id"] != "source" || rows[0]["key"] != "one" || rows[0]["record_key"] != "one" || rows[0]["target"] != "record" || rows[0]["payload"].(map[string]any)["name"] != "Record" {
		t.Fatalf("record rows: %+v", rows)
	}
	row := decodeContentData[map[string]any](t, f.request("GET", "/api/admin/schema/record/rows?source_id=source&key=one", "", f.admin, 200))
	if row["key"] != "one" || row["values"].(map[string]any)["name"] != "Record" {
		t.Fatal("record get", row)
	}
	for _, query := range []string{"id=1", "source_id=source", "key=one"} {
		f.request("GET", "/api/admin/schema/record/rows?"+query, "", f.admin, 400)
		f.request("DELETE", "/api/admin/schema/record/rows?"+query, "", f.admin, 400)
	}
	f.request("GET", "/api/admin/schema/record/rows?source_id=source&key=missing", "", f.admin, 404)
	f.request("POST", "/api/admin/schema/record/rows/save", `{}`, f.admin, 400)
	f.request("POST", "/api/admin/schema/record/rows/batch-delete", `{"ids":[1]}`, f.admin, 400)
	f.request("DELETE", "/api/admin/schema/record/rows?source_id=source&key=one", "", f.admin, 200)
	result = f.request("GET", "/api/admin/schema/record/rows", "", f.admin, 200)
	if string(result["total"]) != "0" {
		t.Fatal("record not deleted", result)
	}
	for _, slug := range []string{"article", "video"} {
		base := "/api/admin/schema/" + slug + "/rows"
		for _, request := range []struct{ method, path, body string }{
			{"GET", base, ""}, {"GET", base + "?id=1", ""}, {"POST", base + "/save", `{}`},
			{"DELETE", base + "?id=1", ""}, {"POST", base + "/batch-delete", `{"ids":[1]}`},
		} {
			result = f.request(request.method, request.path, request.body, f.admin, 400)
			if string(result["error"]) != `"请使用专用资讯或视频接口"` {
				t.Fatalf("dedicated writer message: %s", result)
			}
		}
	}
	for _, path := range []string{"", "/save", "/batch-delete"} {
		method := "POST"
		if path == "" {
			method = "GET"
		}
		f.request(method, "/api/admin/schema/missing/rows"+path, `{}`, f.admin, 404)
	}
	for _, path := range []string{"record", "record/not-rows", "record/rows/unknown", "record/rows/save/extra"} {
		f.request("GET", "/api/admin/schema/"+path, "", f.admin, 404)
	}
	f.request("PUT", "/api/admin/schema/record/rows", `{}`, f.admin, 405)
	f.request("GET", "/api/admin/schema/record/rows/save", "", f.admin, 405)
}
