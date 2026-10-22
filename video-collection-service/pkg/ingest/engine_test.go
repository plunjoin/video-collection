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
	"video-collection-service/config"
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

func TestRSSAndAtomFeedIngestion(t *testing.T) {
	rssContent := `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/elements/1.1/">
<channel>
<title>AGI Hunt · AI 快讯</title>
<link>https://agihunt.info/</link>
<description>全天候 AI 资讯快讯</description>
<item>
<title>开源版 ElevenLabs 替代品爆火: 本地跑、支持 646 种语言</title>
<link>https://agihunt.info/p/1a1484fc6653f5e6079cad75892</link>
<guid isPermaLink="true">https://agihunt.info/p/1a1484fc6653f5e6079cad75892</guid>
<description>一位独立开发者开源了完全本地运行的 ElevenLabs 免费替代品，GitHub 星标已达 19.4K。</description>
<dc:creator>art_zucker</dc:creator>
<pubDate>Sat, 17 Oct 2026 05:21:20 +0000</pubDate>
</item>
<item>
<title>数据行业为何被 28 岁以下年轻人主导？业内人士给出三大原因</title>
<link>https://agihunt.info/p/1a1485252df297180f72eae3a9a</link>
<guid isPermaLink="true">https://agihunt.info/p/1a1485252df297180f72eae3a9a</guid>
<description>业内人士分析数据行业比其他 AI 大市场更被年轻群体主导的三个原因。</description>
<dc:creator>dejavucoder</dc:creator>
<pubDate>Sat, 17 Oct 2026 05:20:44 +0000</pubDate>
</item>
</channel>
</rss>`

	atomContent := `<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>示例 Atom 资讯源</title>
  <link href="https://example.com/"/>
  <updated>2026-10-17T05:00:00Z</updated>
  <entry>
    <title>DeepSeek V3 架构解析发布</title>
    <id>https://example.com/p/deepseek-v3</id>
    <link href="https://example.com/p/deepseek-v3"/>
    <published>2026-10-17T04:30:00Z</published>
    <summary>DeepSeek V3 采用 MLA 稀疏注意力与 MoE 架构创新。</summary>
    <content>DeepSeek V3 采用 MLA 稀疏注意力与 MoE 架构创新，大幅降低推理成本。</content>
    <author><name>AI Researcher</name></author>
    <category term="模型架构"/>
  </entry>
</feed>`

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/atom.xml" {
			w.Header().Set("Content-Type", "application/atom+xml")
			fmt.Fprint(w, atomContent)
			return
		}
		w.Header().Set("Content-Type", "application/rss+xml; charset=utf-8")
		fmt.Fprint(w, rssContent)
	}))
	defer server.Close()

	// 1. 测试显式 input="rss"
	src := config.SourceConfig{
		ID: "rss_test", Name: "AGI Hunt 快讯", Type: "pipeline", PageLimit: 1, TimeoutSec: 5,
		API: server.URL + "/feed.xml",
		Filter: config.FilterRule{Pipeline: &config.PipelineRule{
			Version: 1, Input: "rss", Target: "article", KeyField: "link", Duplicate: "skip", MaxRecords: 10,
			Fields: []config.FieldRule{
				{Target: "title", Selector: "title", Required: true, Trim: true},
				{Target: "content", Selector: "description", Required: true, Trim: true},
				{Target: "summary", Selector: "summary", Trim: true},
				{Target: "link", Selector: "link", Required: true, Trim: true},
				{Target: "author", Selector: "creator", Trim: true},
				{Target: "category", Selector: "category", Default: "AI快讯"},
			},
		}},
	}
	rows := collect(t, src, 10)
	if len(rows) != 2 {
		t.Fatalf("expected 2 RSS items, got %d", len(rows))
	}
	if rows[0].Values["title"] != "开源版 ElevenLabs 替代品爆火: 本地跑、支持 646 种语言" {
		t.Errorf("unexpected title: %q", rows[0].Values["title"])
	}
	if rows[0].Values["link"] != "https://agihunt.info/p/1a1484fc6653f5e6079cad75892" {
		t.Errorf("unexpected link: %q", rows[0].Values["link"])
	}
	if rows[0].Values["author"] != "art_zucker" {
		t.Errorf("unexpected author: %q", rows[0].Values["author"])
	}
	if rows[0].Values["category"] != "AI快讯" {
		t.Errorf("unexpected category: %q", rows[0].Values["category"])
	}
	if !strings.Contains(rows[0].Values["content"], "19.4K") {
		t.Errorf("unexpected content: %q", rows[0].Values["content"])
	}

	// 2. 测试 input="api" 自动识别 RSS XML
	srcAuto := src
	srcAuto.Filter.Pipeline.Input = "api"
	rowsAuto := collect(t, srcAuto, 10)
	if len(rowsAuto) != 2 || rowsAuto[1].Values["author"] != "dejavucoder" {
		t.Fatalf("auto xml detection failed: %+v", rowsAuto)
	}

	// 3. 测试 Atom Feed
	srcAtom := config.SourceConfig{
		ID: "atom_test", Name: "Atom 资讯", Type: "pipeline", PageLimit: 1, TimeoutSec: 5,
		API: server.URL + "/atom.xml",
		Filter: config.FilterRule{Pipeline: &config.PipelineRule{
			Version: 1, Input: "rss", Target: "article", KeyField: "link", Duplicate: "skip", MaxRecords: 10,
			Fields: []config.FieldRule{
				{Target: "title", Selector: "title", Required: true, Trim: true},
				{Target: "content", Selector: "content", Required: true, Trim: true},
				{Target: "summary", Selector: "summary", Trim: true},
				{Target: "link", Selector: "link", Required: true, Trim: true},
				{Target: "author", Selector: "author", Trim: true},
				{Target: "category", Selector: "category", Default: "前沿动态"},
			},
		}},
	}
	atomRows := collect(t, srcAtom, 10)
	if len(atomRows) != 1 {
		t.Fatalf("expected 1 Atom item, got %d", len(atomRows))
	}
	if atomRows[0].Values["title"] != "DeepSeek V3 架构解析发布" {
		t.Errorf("unexpected atom title: %q", atomRows[0].Values["title"])
	}
	if atomRows[0].Values["category"] != "模型架构" {
		t.Errorf("unexpected atom category: %q", atomRows[0].Values["category"])
	}
	if atomRows[0].Values["author"] != "AI Researcher" {
		t.Errorf("unexpected atom author: %q", atomRows[0].Values["author"])
	}
}

func TestRegisteredBusinessTargetValidation(t *testing.T) {
	src := testSource("api")
	src.API = "https://example.com"
	src.Filter.Pipeline.Target = "demo_item"
	lookup := func(slug string) (TargetSchema, error) {
		if slug != "demo_item" {
			return TargetSchema{}, fmt.Errorf("unknown")
		}
		return TargetSchema{RequiredFields: []string{"score"}}, nil
	}
	if err := Validate(src, lookup); err == nil {
		t.Fatal("missing schema mapping accepted")
	}
	src.Filter.Pipeline.Fields = append(src.Filter.Pipeline.Fields, config.FieldRule{Target: "score"})
	if err := Validate(src, lookup); err != nil {
		t.Fatal(err)
	}
	src.Filter.Pipeline.Target = "missing"
	if err := Validate(src, lookup); err == nil {
		t.Fatal("unknown target accepted")
	}
	src.Filter.Pipeline.Target = "demo_item"
	if err := Validate(src); err == nil {
		t.Fatal("unregistered standalone target accepted")
	}
	// Custom types need not contain title.
	src.Filter.Pipeline.Fields = []config.FieldRule{{Target: "score"}}
	src.Filter.Pipeline.KeyField = "score"
	if err := Validate(src, lookup); err != nil {
		t.Fatal(err)
	}
	if s := MapRecord(src.Filter.Pipeline, map[string]string{"score": "7"}); len(s.Errors) > 0 {
		t.Fatal(s.Errors)
	}
}
