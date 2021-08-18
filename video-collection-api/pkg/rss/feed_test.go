package rss

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"video-collection-api/pkg/maccms"
	"video-collection-api/pkg/store"
)

type mockStore struct {
	store.Store
}

func (m *mockStore) GetSetting(ctx context.Context, key, defaultVal string) (string, error) {
	if key == "site_name" {
		return "单元测试影视站", nil
	}
	if key == "site_subtitle" {
		return "最新影视更新", nil
	}
	return defaultVal, nil
}

func (m *mockStore) GetCategories(ctx context.Context) ([]store.Category, error) {
	return []store.Category{
		{ID: 10, PID: 0, Name: "电影频道"},
		{ID: 20, PID: 0, Name: "连续剧"},
	}, nil
}

func (m *mockStore) QueryVideos(ctx context.Context, q store.VideoQuery) ([]store.VideoRecord, int, error) {
	return []store.VideoRecord{
		{
			ID:        1001,
			Name:      "阿凡达3",
			TypeID:    10,
			TypeName:  "电影频道",
			Picture:   "https://example.com/poster.jpg",
			Actor:     "萨姆·沃辛顿",
			Director:  "詹姆斯·卡梅隆",
			Remarks:   "4K先行预告",
			Content:   "潘多拉星球新冒险",
			UpdatedAt: time.Now(),
			PlayGroups: []maccms.PlayGroup{
				{
					PlayerCode: "m3u8",
					Episodes: []maccms.Episode{
						{Name: "预告1", URL: "https://example.com/ep1.m3u8"},
					},
				},
			},
		},
	}, 1, nil
}

func TestRSSHandler(t *testing.T) {
	handler := NewHandler(&mockStore{})

	req := httptest.NewRequest(http.MethodGet, "/rss.xml", nil)
	w := httptest.NewRecorder()

	handler.ServeHTTP(w, req)

	resp := w.Result()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}

	contentType := resp.Header.Get("Content-Type")
	if !strings.Contains(contentType, "application/rss+xml") {
		t.Errorf("expected application/rss+xml content type, got %s", contentType)
	}

	body := w.Body.String()
	if !strings.Contains(body, "<rss version=\"2.0\"") {
		t.Errorf("missing rss version=2.0 tag")
	}
	if !strings.Contains(body, "单元测试影视站") {
		t.Errorf("missing site name in rss body")
	}
	if !strings.Contains(body, "阿凡达3") {
		t.Errorf("missing video name in rss body")
	}
	if !strings.Contains(body, "https://example.com/poster.jpg") {
		t.Errorf("missing picture enclosure in rss body")
	}
}
