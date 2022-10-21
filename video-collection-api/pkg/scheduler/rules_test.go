package scheduler

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"
	"video-collection-api/config"
	"video-collection-api/pkg/store"
)

func TestRuleCollectionRespectsLimitsAndSourceHours(t *testing.T) {
	s, err := store.NewSQLiteStore(filepath.Join(t.TempDir(), "rules.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	requests := 0
	wantHours := ""
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		q := r.URL.Query()
		if q.Get("updated") != wantHours || q.Has("ac") || q.Has("h") {
			t.Errorf("incorrect rule parameters: %s", r.URL)
		}
		fmt.Fprintf(w, `{"pages":5,"items":[{"id":"%s","title":"影片 %s"}]}`, q.Get("page"), q.Get("page"))
	}))
	defer upstream.Close()
	src := config.SourceConfig{ID: "rule", Name: "rule", API: upstream.URL, Type: "rule", CollectHours: 12, PageLimit: 2, IntervalMs: 1, Filter: config.FilterRule{Collector: &config.CollectionRule{Version: 1, Format: "custom_json", Method: "GET", Query: map[string]string{"page": "{page}", "updated": "{hours}"}, Mapping: config.CustomMapping{ListPath: "items", PageCountPath: "pages", NamePath: "title", IDPath: "id"}}}}
	sc := &Scheduler{store: s, progress: map[string]*TaskProgress{}, maxLogs: 100}
	prog := &TaskProgress{StartTime: time.Now()}
	sc.runCollectTask(context.Background(), src, 0, prog)
	if requests != 2 || prog.TotalSaved != 2 || prog.LastError != "" {
		t.Fatalf("full collection exceeded limit or failed: requests=%d, progress=%+v", requests, prog)
	}
	wantHours = "12"
	requests = 0
	prog = &TaskProgress{StartTime: time.Now()}
	sc.runCollectTask(context.Background(), src, -1, prog)
	if requests != 2 || prog.LastError != "" {
		t.Fatalf("source configuration ignored: %+v", prog)
	}
}
