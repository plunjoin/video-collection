package api

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"video-collection-service/pkg/store"
)

func signBody(secret string, body []byte) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	return "sha256=" + hex.EncodeToString(mac.Sum(nil))
}

func TestCollectorWebhookIngestsIntoNewsPipeline(t *testing.T) {
	secret := "test-webhook-secret"
	t.Setenv("ACG_WEBHOOK_SECRET", secret)
	t.Setenv("COLLECTOR_WEBHOOK_SECRET", "")

	s, err := store.NewSQLiteStore(filepath.Join(t.TempDir(), "webhook.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = s.Close() })

	mux := http.NewServeMux()
	NewServer(s, nil, nil, nil).RegisterRoutes(mux)

	body := []byte(`[{"id":42,"category":"动画","source":"crunchyroll","source_name":"Crunchyroll News","source_label":"来源：Crunchyroll News","kind":"rss","lang":"en","title_original":"PSYREN Dub","title_zh":"《PSYREN》英语配音","summary_zh":"第一集将于 10 月 19 日上线。","text_zh":null,"url":"https://example.com/psyren","published_at":"2026-10-18T13:00:00-04:00","also_reported_by":[],"images":[{"url":"https://cdn.example.com/psyren.jpg","local_path":"/tmp/x.jpg"}]}]`)

	req := httptest.NewRequest(http.MethodPost, "/api/webhooks/collector", strings.NewReader(string(body)))
	req.Header.Set("Content-Type", "application/json; charset=utf-8")
	req.Header.Set("X-ACG-Signature", signBody(secret, body))
	req.Header.Set("X-ACG-Timestamp", "1710000000")
	req.Header.Set("X-ACG-Batch-Id", "batch-abc")
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)
	if w.Code != 200 {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
	var resp map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp["ok"] != true || resp["inserted"] != float64(1) || resp["source_id"] != "acg-news" {
		t.Fatalf("resp=%v", resp)
	}

	rows, total, err := s.ListCollectionRecords(context.Background(), "acg-news", 1, 10)
	if err != nil || total != 1 || len(rows) != 1 {
		t.Fatalf("records total=%d len=%d err=%v", total, len(rows), err)
	}
	if rows[0].Target != "article" || rows[0].Key != "crunchyroll:42" {
		t.Fatalf("record=%+v", rows[0])
	}
	if rows[0].Values["title"] != "《PSYREN》英语配音" || rows[0].Values["cover"] != "https://cdn.example.com/psyren.jpg" {
		t.Fatalf("values=%v", rows[0].Values)
	}
	article, err := s.GetContent(context.Background(), "news", rows[0].ContentID, 0, true)
	if err != nil || article == nil {
		t.Fatalf("news: %v", err)
	}
	if article.Title != "《PSYREN》英语配音" || article.Status != "draft" || article.Category != "动画" {
		t.Fatalf("article=%+v", article)
	}
	if article.Cover != "https://cdn.example.com/psyren.jpg" {
		t.Fatalf("cover=%q", article.Cover)
	}

	// 幂等更新草稿
	body2 := []byte(`[{"id":42,"category":"动画","source":"crunchyroll","title_original":"PSYREN Dub","title_zh":"更新后的标题","summary_zh":"更新摘要","url":"https://example.com/psyren","images":[]}]`)
	req2 := httptest.NewRequest(http.MethodPost, "/api/webhooks/collector", strings.NewReader(string(body2)))
	req2.Header.Set("X-ACG-Signature", signBody(secret, body2))
	w2 := httptest.NewRecorder()
	mux.ServeHTTP(w2, req2)
	if w2.Code != 200 {
		t.Fatalf("update status=%d %s", w2.Code, w2.Body.String())
	}
	var resp2 map[string]any
	_ = json.Unmarshal(w2.Body.Bytes(), &resp2)
	if resp2["updated"] != float64(1) {
		t.Fatalf("expected updated=1 got %v", resp2)
	}
	article, _ = s.GetContent(context.Background(), "news", rows[0].ContentID, 0, true)
	if article.Title != "更新后的标题" {
		t.Fatalf("title not updated: %s", article.Title)
	}
}

func TestCollectorWebhookRejectsBadSignature(t *testing.T) {
	t.Setenv("COLLECTOR_WEBHOOK_SECRET", "good-secret")
	s, err := store.NewSQLiteStore(filepath.Join(t.TempDir(), "webhook-bad.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = s.Close() })
	mux := http.NewServeMux()
	NewServer(s, nil, nil, nil).RegisterRoutes(mux)

	body := []byte(`[{"id":1,"title_original":"x","summary_zh":"y"}]`)
	req := httptest.NewRequest(http.MethodPost, "/api/webhooks/collector", strings.NewReader(string(body)))
	req.Header.Set("X-ACG-Signature", "sha256=deadbeef")
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("want 401 got %d %s", w.Code, w.Body.String())
	}
}

func TestCollectorWebhookRequiresSecret(t *testing.T) {
	t.Setenv("COLLECTOR_WEBHOOK_SECRET", "")
	t.Setenv("ACG_WEBHOOK_SECRET", "")
	s, err := store.NewSQLiteStore(filepath.Join(t.TempDir(), "webhook-nosecret.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = s.Close() })
	mux := http.NewServeMux()
	NewServer(s, nil, nil, nil).RegisterRoutes(mux)
	req := httptest.NewRequest(http.MethodPost, "/api/webhooks/collector", strings.NewReader(`[]`))
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)
	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("want 503 got %d", w.Code)
	}
}

func TestMapCollectorItemFallbacks(t *testing.T) {
	titleZh := "中文标题"
	textZh := "帖子正文"
	it := collectorWebhookItem{
		ID:            json.RawMessage(`"abc"`),
		Source:        "x:@ufotable",
		TitleOriginal: "ignored when zh present",
		TitleZh:       &titleZh,
		TextZh:        &textZh,
		Images:        []collectorWebhookImage{{URL: "/relative.jpg"}, {URL: "https://ok.example/a.png"}},
	}
	key, values, err := mapCollectorItemToArticle(it)
	if err != nil {
		t.Fatal(err)
	}
	if key != "x:@ufotable:abc" {
		t.Fatalf("key=%s", key)
	}
	if values["title"] != "中文标题" || values["content"] != "帖子正文" || values["cover"] != "https://ok.example/a.png" {
		t.Fatalf("values=%v", values)
	}
}
