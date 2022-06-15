package ingest

import (
	"context"
	"database/sql"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/xuri/excelize/v2"
	"video-collection-api/config"
)

func testSource(input string) config.SourceConfig {
	return config.SourceConfig{ID: "test", Name: "test", Type: "pipeline", PageLimit: 5, TimeoutSec: 2, Filter: config.FilterRule{Pipeline: &config.PipelineRule{
		Version: 1, Input: input, Target: "record", KeyField: "id", Duplicate: "update", MaxRecords: 100,
		Request: config.RequestRule{Method: "GET", ListPath: "data.items", StartPage: 1},
		Fields:  []config.FieldRule{{Target: "id", Selector: "id", Required: true}, {Target: "title", Selector: "title", Trim: true, StripHTML: true, Pattern: "广告", Replacement: ""}},
	}}}
}

func collect(t *testing.T, src config.SourceConfig, limit int) []Sample {
	t.Helper()
	var samples []Sample
	if err := Run(context.Background(), src, limit, func(s Sample) error { samples = append(samples, s); return nil }); err != nil {
		t.Fatal(err)
	}
	return samples
}

func TestAPIPaginationMappingAndPreviewLimit(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		if r.Method != "POST" || r.Header.Get("X-Test") != "test" || r.URL.Query().Get("category") != "news" {
			t.Error("request config missing")
		}
		page := r.URL.Query().Get("page")
		if page == "3" {
			fmt.Fprint(w, `{"data":{"items":[]}}`)
			return
		}
		fmt.Fprintf(w, `{"data":{"items":[{"id":%s,"title":" <b>广告标题</b> "}]}}`, page)
	}))
	defer server.Close()
	src := testSource("api")
	src.API = server.URL
	src.Headers = map[string]string{"X-Test": "test"}
	src.CustomParams = map[string]string{"category": "news"}
	src.Filter.Pipeline.Request.Method = "POST"
	src.Filter.Pipeline.Request.PageParam = "page"
	rows := collect(t, src, 1)
	if len(rows) != 1 || rows[0].Values["id"] != "1" || rows[0].Values["title"] != "标题" || calls != 1 {
		t.Fatalf("bad preview: %+v calls %d", rows, calls)
	}
	rows = collect(t, src, 0)
	if len(rows) != 2 || calls != 4 {
		t.Fatalf("pagination failed: %d %d", len(rows), calls)
	}
}

func TestHTMLDetailsRelativeLinksAndCycle(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/detail") {
			fmt.Fprint(w, `<h1>新闻标题</h1><img src="/cover.png">`)
			return
		}
		fmt.Fprint(w, `<article><a href="/detail/1">详情</a></article><a class="next" href="/">下一页</a>`)
	}))
	defer server.Close()
	src := testSource("html")
	src.API = server.URL + "/"
	p := src.Filter.Pipeline
	p.HTML = config.HTMLRule{ItemSelector: "article", DetailSelector: "a", NextSelector: ".next"}
	p.Fields = []config.FieldRule{{Target: "id", Selector: "$url"}, {Target: "title", Selector: "h1"}, {Target: "cover", Selector: "img", Attribute: "src"}}
	rows := collect(t, src, 0)
	if len(rows) != 1 || rows[0].Values["id"] != server.URL+"/detail/1" || rows[0].Values["cover"] != server.URL+"/cover.png" {
		t.Fatalf("bad extraction: %+v", rows)
	}
}

func TestCSVAndExcelColumns(t *testing.T) {
	t.Setenv("COLLECTION_UPLOAD_DIR", t.TempDir())
	src := testSource("file")
	p := src.Filter.Pipeline
	p.File.HeaderRow = 2
	p.Fields[1].Selector = "标题"
	token, err := SaveUpload("test.csv", strings.NewReader("说明\nid,标题\n1,第一篇\n\n2,第二篇\n"))
	if err != nil {
		t.Fatal(err)
	}
	p.File.Token = token
	rows := collect(t, src, 0)
	if len(rows) != 2 || rows[0].Values["title"] != "第一篇" {
		t.Fatalf("bad csv: %+v", rows)
	}
	book := excelize.NewFile()
	defer book.Close()
	book.SetCellValue("Sheet1", "A1", "说明")
	book.SetSheetRow("Sheet1", "A2", &[]string{"id", "标题"})
	book.SetSheetRow("Sheet1", "A3", &[]string{"3", "Excel 标题"})
	buf, err := book.WriteToBuffer()
	if err != nil {
		t.Fatal(err)
	}
	token, err = SaveUpload("test.xlsx", buf)
	if err != nil {
		t.Fatal(err)
	}
	p.File.Token = token
	rows = collect(t, src, 0)
	if len(rows) != 1 || rows[0].Values["title"] != "Excel 标题" {
		t.Fatalf("bad xlsx: %+v", rows)
	}
	p.File.Sheet = "missing"
	if err := Run(context.Background(), src, 1, func(Sample) error { return nil }); err == nil {
		t.Fatal("missing sheet accepted")
	}
	p.File.Token = "../../test.csv"
	if Validate(src) == nil {
		t.Fatal("path traversal accepted")
	}
}

func TestDatabaseReadsBoundedSQLite(t *testing.T) {
	path := filepath.Join(t.TempDir(), "source.db")
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`CREATE TABLE articles(id INTEGER,title TEXT); INSERT INTO articles VALUES (1,'一'),(2,'二')`); err != nil {
		t.Fatal(err)
	}
	db.Close()
	t.Setenv("TEST_IMPORT_DSN", path)
	src := testSource("database")
	src.Filter.Pipeline.Database = config.ImportDatabaseRule{Driver: "sqlite", DSNEnv: "TEST_IMPORT_DSN", Query: "SELECT id, title FROM articles"}
	rows := collect(t, src, 1)
	if len(rows) != 1 || rows[0].Values["id"] != "1" {
		t.Fatalf("bad sql import: %+v", rows)
	}
	for _, query := range []string{"DELETE FROM articles", "SELECT 1; DROP TABLE articles", "SELECT * INTO foo FROM articles", "SELECT 1 -- comment"} {
		src.Filter.Pipeline.Database.Query = query
		if Validate(src) == nil {
			t.Fatalf("accepted %s", query)
		}
	}
}

func TestInvalidRulesAndRequiredFields(t *testing.T) {
	src := testSource("api")
	src.API = "https://example.com"
	src.Filter.Pipeline.Fields[1].Pattern = "["
	if Validate(src) == nil {
		t.Fatal("bad regex accepted")
	}
	src.Filter.Pipeline.Fields[1].Pattern = ""
	src.Filter.Pipeline.Fields[1].Target = "id"
	if Validate(src) == nil {
		t.Fatal("duplicate field accepted")
	}
	src = testSource("html")
	src.API = "https://example.com"
	src.Filter.Pipeline.HTML.ItemSelector = "["
	if Validate(src) == nil {
		t.Fatal("invalid CSS accepted")
	}
	p := testSource("api").Filter.Pipeline
	sample := MapRecord(p, map[string]string{"title": "test"})
	if len(sample.Errors) == 0 {
		t.Fatal("missing identity accepted")
	}
}
