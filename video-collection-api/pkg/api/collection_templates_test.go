package api

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"video-collection-api/config"
)

func TestTemplatesAuthorizationReloadAndRulePersistence(t *testing.T) {
	f := newContentFixture(t)
	f.request("GET", "/api/admin/sources/templates", "", nil, 401)
	f.request("GET", "/api/admin/sources/templates", "", f.alice, 401)
	templates := decodeContentData[[]config.CollectionTemplate](t, f.request("GET", "/api/admin/sources/templates", "", f.admin, 200))
	if len(templates) < 4 {
		t.Fatal("default templates missing")
	}
	path := filepath.Join(t.TempDir(), "templates.yaml")
	t.Setenv("COLLECTION_TEMPLATES_PATH", path)
	data := `- id: independent
  name: Custom catalog
  aliases: [own_json]
  rule:
    version: 1
    format: custom_json
    method: GET
    query: {p: "{page}"}
    mapping: {list_path: items, name_path: title}
`
	if err := os.WriteFile(path, []byte(data), 0600); err != nil {
		t.Fatal(err)
	}
	templates = decodeContentData[[]config.CollectionTemplate](t, f.request("GET", "/api/admin/sources/templates", "", f.admin, 200))
	if len(templates) != 1 || templates[0].ID != "independent" {
		t.Fatal("external template was not reloaded")
	}
	src := config.SourceConfig{ID: "configurable", Name: "可配置", API: "https://example.com/videos", Type: "rule", CollectHours: 0, PageLimit: 7, Filter: config.FilterRule{Collector: &templates[0].Rule}}
	encoded, _ := json.Marshal(src)
	f.request("POST", "/api/admin/sources", string(encoded), f.admin, 200)
	sources := decodeContentData[[]config.SourceConfig](t, f.request("GET", "/api/admin/sources", "", f.admin, 200))
	if len(sources) != 1 || sources[0].CollectHours != 0 || sources[0].Filter.Collector.Query["p"] != "{page}" {
		t.Fatal("rule not persisted")
	}
	src.Filter.Collector.Query["p"] = "{unknown}"
	encoded, _ = json.Marshal(src)
	f.request("POST", "/api/admin/sources", string(encoded), f.admin, 400)
}
