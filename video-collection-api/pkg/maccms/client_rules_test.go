package maccms

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"video-collection-api/config"
)

func TestConfiguredRequestAndNestedResponse(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		if r.Method != "POST" || q.Get("cursor_page") != "2" || q.Get("since") != "12" || q.Get("token") != "secret" || q.Has("ac") || q.Has("pg") || q.Has("out") {
			t.Errorf("unexpected request: %s %s", r.Method, r.URL)
		}
		body, _ := io.ReadAll(r.Body)
		if string(body) != `{"limit":50}` || r.Header.Get("Authorization") != "Bearer test" {
			t.Error("request body or headers lost")
		}
		io.WriteString(w, `{"data":{"page":"2","pages":4,"total":8,"items":[{"identity":{"id":"abc"},"metadata":{"title":"测试影片"},"images":[{"url":"cover.jpg"}],"stream":{"url":"https://example.com/a.m3u8"}}]}}`)
	}))
	defer upstream.Close()
	rule := &config.CollectionRule{Version: 1, Format: "custom_json", Method: "POST", Body: `{"limit":50}`, Query: map[string]string{"cursor_page": "{page}", "since": "{hours}"}, Mapping: config.CustomMapping{ListPath: "data.items", PagePath: "data.page", PageCountPath: "data.pages", TotalPath: "data.total", IDPath: "identity.id", NamePath: "metadata.title", PicPath: "images.0.url", PlayURLPath: "stream.url"}}
	c := NewClient(config.SourceConfig{API: upstream.URL, Type: "rule", Headers: map[string]string{"Authorization": "Bearer test"}, CustomParams: map[string]string{"token": "secret"}, Filter: config.FilterRule{Collector: rule}})
	items, resp, err := c.CollectPage(context.Background(), QueryParams{Page: 2, Hours: 12})
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 || items[0].Name != "测试影片" || items[0].Picture != "cover.jpg" || resp.PageCount != 4 || resp.Total != 8 {
		t.Fatalf("unexpected response: %+v %+v", items, resp)
	}
	u, _ := url.Parse(c.BuildURL(QueryParams{Page: 1, Hours: 12, IsAll: true}))
	if u.Query().Has("since") {
		t.Fatal("full collection retained incremental parameter")
	}
}

func TestLegacyRESTDoesNotReceiveCMSParameters(t *testing.T) {
	c := NewClient(config.SourceConfig{API: "https://example.com/videos", Type: "custom_json"})
	u, _ := url.Parse(c.BuildURL(QueryParams{Action: "detail", Page: 3, Hours: 24}))
	if u.Query().Get("page") != "3" || u.Query().Has("ac") || u.Query().Has("h") || u.Query().Has("pg") {
		t.Fatal(u.String())
	}
	c = NewClient(config.SourceConfig{API: "https://example.com/videos?h=99", Type: "json"})
	u, _ = url.Parse(c.BuildURL(QueryParams{Page: 1, IsAll: true}))
	if u.Query().Has("h") {
		t.Fatal("full collection kept hours from endpoint")
	}
}

func TestMappingErrorsAndEmptyPage(t *testing.T) {
	if _, err := ParseCustomJsonResponse([]byte(`{"other":[]}`), config.CustomMapping{ListPath: "data.items"}); err == nil {
		t.Fatal("invalid list path accepted")
	}
	resp, err := ParseCustomJsonResponse([]byte(`{"data":{"items":[]},"items":[{"title":"wrong"}]}`), config.CustomMapping{ListPath: "data.items"})
	if err != nil || len(resp.List) != 0 {
		t.Fatal("empty configured page fell back to another list")
	}
	resp, err = ParseCustomJsonResponse([]byte(`[{"title":"fallback"}]`), config.CustomMapping{ListPath: "$", NamePath: "missing.title"})
	if err != nil || len(resp.List) != 0 {
		t.Fatal("explicit field mapping fell back silently")
	}
}

func TestRetriesAndCancellation(t *testing.T) {
	requests := 0
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { requests++; w.WriteHeader(503) }))
	defer upstream.Close()
	c := NewClient(config.SourceConfig{API: upstream.URL, Type: "json", RetryCount: 0})
	if _, err := c.FetchRawResponse(context.Background(), QueryParams{Page: 1}); err == nil || requests != 1 {
		t.Fatal("zero retries did not mean one attempt")
	}
	c = NewClient(config.SourceConfig{API: upstream.URL, Type: "unsupported"})
	if _, err := c.FetchRawResponse(context.Background(), QueryParams{}); err == nil || !strings.Contains(err.Error(), "未知") {
		t.Fatal("unknown type accepted")
	}
}
