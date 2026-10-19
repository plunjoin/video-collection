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
	"time"

	"video-collection-service/config"
	"video-collection-service/pkg/store"
)

func signBody(secret string, body []byte) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	return "sha256=" + hex.EncodeToString(mac.Sum(nil))
}

func newWebhookMux(t *testing.T) (*store.SQLiteStore, *http.ServeMux) {
	t.Helper()
	s, err := store.NewSQLiteStore(filepath.Join(t.TempDir(), "webhook.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = s.Close() })
	mux := http.NewServeMux()
	NewServer(s, nil, nil, nil).RegisterRoutes(mux)
	return s, mux
}

func saveWebhookSource(t *testing.T, s *store.SQLiteStore, id, secret, expires string, enabled bool) {
	t.Helper()
	params := map[string]string{}
	if secret != "" {
		params["webhook_secret"] = secret
	}
	if expires != "" {
		params["webhook_secret_expires_at"] = expires
	}
	err := s.SaveSource(context.Background(), config.SourceConfig{
		ID:           id,
		Name:         id,
		API:          "webhook://collector",
		Type:         "webhook",
		Enabled:      enabled,
		TimeoutSec:   15,
		PageLimit:    1,
		CustomParams: params,
	})
	if err != nil {
		t.Fatal(err)
	}
}

func postCollector(mux *http.ServeMux, body []byte, secret string, extra http.Header) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, "/api/webhooks/collector", strings.NewReader(string(body)))
	req.Header.Set("Content-Type", "application/json; charset=utf-8")
	if secret != "" {
		req.Header.Set("X-ACG-Signature", signBody(secret, body))
	}
	for k, vals := range extra {
		for _, v := range vals {
			req.Header.Set(k, v)
		}
	}
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)
	return w
}

func TestCollectorWebhookIngestsIntoNewsPipeline(t *testing.T) {
	secret := "test-webhook-secret"
	t.Setenv("ACG_WEBHOOK_SECRET", secret)
	t.Setenv("COLLECTOR_WEBHOOK_SECRET", "")

	s, mux := newWebhookMux(t)
	// 环境变量兜底仍要求源已启用（与后台开关一致）
	saveWebhookSource(t, s, "acg-news", "", "", true)

	body := []byte(`[{"id":42,"category":"动画","source":"crunchyroll","source_name":"Crunchyroll News","source_label":"来源：Crunchyroll News","kind":"rss","lang":"en","title_original":"PSYREN Dub","title_zh":"《PSYREN》英语配音","summary_zh":"第一集将于 10 月 19 日上线。","text_zh":null,"url":"https://example.com/psyren","published_at":"2026-10-18T13:00:00-04:00","also_reported_by":[],"images":[{"url":"https://cdn.example.com/psyren.jpg","local_path":"/tmp/x.jpg"}]}]`)

	w := postCollector(mux, body, secret, http.Header{
		"X-ACG-Timestamp": {"1710000000"},
		"X-ACG-Batch-Id":  {"batch-abc"},
	})
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
	if article.SourceURL != "https://example.com/psyren" {
		t.Fatalf("source_url=%q", article.SourceURL)
	}
	if article.SourceName != "Crunchyroll News" {
		t.Fatalf("source_name=%q", article.SourceName)
	}
	if article.PublishedAt != "2026-10-18T13:00:00-04:00" {
		t.Fatalf("published_at=%q", article.PublishedAt)
	}
	if !strings.Contains(article.Content, "第一集将于 10 月 19 日上线") {
		t.Fatalf("content=%q", article.Content)
	}

	// 幂等更新草稿
	body2 := []byte(`[{"id":42,"category":"动画","source":"crunchyroll","title_original":"PSYREN Dub","title_zh":"更新后的标题","summary_zh":"更新摘要","url":"https://example.com/psyren","images":[]}]`)
	w2 := postCollector(mux, body2, secret, nil)
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

func TestCollectorWebhookUsesSourceCustomParamsSecret(t *testing.T) {
	t.Setenv("COLLECTOR_WEBHOOK_SECRET", "")
	t.Setenv("ACG_WEBHOOK_SECRET", "")
	s, mux := newWebhookMux(t)
	secret := "per-source-secret"
	saveWebhookSource(t, s, "acg-news", secret, "", true)

	body := []byte(`[{"id":7,"title_original":"from-source","summary_zh":"ok"}]`)
	w := postCollector(mux, body, secret, nil)
	if w.Code != 200 {
		t.Fatalf("want 200 got %d %s", w.Code, w.Body.String())
	}
}

func TestCollectorWebhookRejectsExpiredSecret(t *testing.T) {
	t.Setenv("COLLECTOR_WEBHOOK_SECRET", "")
	t.Setenv("ACG_WEBHOOK_SECRET", "")
	s, mux := newWebhookMux(t)
	secret := "expiring-secret"
	past := time.Now().Add(-time.Hour).UTC().Format(time.RFC3339)
	saveWebhookSource(t, s, "acg-news", secret, past, true)

	body := []byte(`[{"id":1,"title_original":"x","summary_zh":"y"}]`)
	w := postCollector(mux, body, secret, nil)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("want 401 got %d %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "过期") {
		t.Fatalf("body=%s", w.Body.String())
	}
}

func TestCollectorWebhookRejectsDisabledSource(t *testing.T) {
	t.Setenv("COLLECTOR_WEBHOOK_SECRET", "env-secret")
	s, mux := newWebhookMux(t)
	saveWebhookSource(t, s, "acg-news", "src-secret", "", false)

	body := []byte(`[{"id":1,"title_original":"x","summary_zh":"y"}]`)
	w := postCollector(mux, body, "src-secret", nil)
	if w.Code != http.StatusForbidden {
		t.Fatalf("want 403 got %d %s", w.Code, w.Body.String())
	}
}

func TestCollectorWebhookEnvFallbackStillWorks(t *testing.T) {
	secret := "env-only-secret"
	t.Setenv("COLLECTOR_WEBHOOK_SECRET", secret)
	t.Setenv("ACG_WEBHOOK_SECRET", "")
	s, mux := newWebhookMux(t)
	saveWebhookSource(t, s, "acg-news", "", "", true) // 无 per-source secret

	body := []byte(`[{"id":9,"title_original":"env","summary_zh":"fallback"}]`)
	w := postCollector(mux, body, secret, nil)
	if w.Code != 200 {
		t.Fatalf("want 200 got %d %s", w.Code, w.Body.String())
	}
}

func TestCollectorWebhookRejectsBadSignature(t *testing.T) {
	t.Setenv("COLLECTOR_WEBHOOK_SECRET", "good-secret")
	s, mux := newWebhookMux(t)
	saveWebhookSource(t, s, "acg-news", "", "", true)

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
	s, mux := newWebhookMux(t)
	saveWebhookSource(t, s, "acg-news", "", "", true)

	req := httptest.NewRequest(http.MethodPost, "/api/webhooks/collector", strings.NewReader(`[]`))
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)
	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("want 503 got %d", w.Code)
	}
}

func TestCollectorWebhookPrefersSourceSecretOverEnv(t *testing.T) {
	t.Setenv("COLLECTOR_WEBHOOK_SECRET", "env-secret")
	s, mux := newWebhookMux(t)
	srcSecret := "source-secret"
	saveWebhookSource(t, s, "acg-news", srcSecret, "", true)

	body := []byte(`[{"id":3,"title_original":"prefer","summary_zh":"src"}]`)
	// 用 env 签名应失败
	wBad := postCollector(mux, body, "env-secret", nil)
	if wBad.Code != http.StatusUnauthorized {
		t.Fatalf("env sig want 401 got %d %s", wBad.Code, wBad.Body.String())
	}
	wOK := postCollector(mux, body, srcSecret, nil)
	if wOK.Code != 200 {
		t.Fatalf("source sig want 200 got %d %s", wOK.Code, wOK.Body.String())
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

func TestValidateWebhookSource(t *testing.T) {
	if err := config.ValidateCollectionSource(config.SourceConfig{
		ID: "acg-news", Name: "w", API: "webhook://collector", Type: "webhook",
		CustomParams: map[string]string{"webhook_secret_expires_at": "2099-01-01T00:00:00Z"},
	}); err != nil {
		t.Fatal(err)
	}
	if err := config.ValidateCollectionSource(config.SourceConfig{
		ID: "x", Name: "x", API: "https://example.com", Type: "webhook",
	}); err == nil {
		t.Fatal("expected error for https api with webhook type")
	}
}

func TestMapCollectorItemSynthesizesBodyWhenEmpty(t *testing.T) {
	it := collectorWebhookItem{
		ID:            json.RawMessage(`"99"`),
		Source:        "mal",
		SourceName:    "MyAnimeList",
		SourceLabel:   "MyAnimeList News",
		TitleOriginal: "Some Anime Announcement",
		URL:           "https://myanimelist.net/news/99",
		PublishedAt:   "2026-10-01T00:00:00Z",
	}
	key, values, err := mapCollectorItemToArticle(it)
	if err != nil {
		t.Fatal(err)
	}
	if key != "mal:99" {
		t.Fatalf("key=%s", key)
	}
	want := "来源：MyAnimeList News\n原文：https://myanimelist.net/news/99\n\nSome Anime Announcement"
	if values["content"] != want {
		t.Fatalf("content=%q want=%q", values["content"], want)
	}
	if values["url"] != "https://myanimelist.net/news/99" || values["published_at"] != "2026-10-01T00:00:00Z" {
		t.Fatalf("values=%v", values)
	}
}

func TestMapCollectorItemSourceLabelAlreadyPrefixed(t *testing.T) {
	it := collectorWebhookItem{
		ID:            json.RawMessage(`"100"`),
		Source:        "mal",
		SourceLabel:   "来源：MyAnimeList News",
		TitleOriginal: "Title Only",
		URL:           "https://myanimelist.net/news/100",
	}
	_, values, err := mapCollectorItemToArticle(it)
	if err != nil {
		t.Fatal(err)
	}
	want := "来源：MyAnimeList News\n原文：https://myanimelist.net/news/100\n\nTitle Only"
	if values["content"] != want {
		t.Fatalf("content=%q want=%q", values["content"], want)
	}
}
