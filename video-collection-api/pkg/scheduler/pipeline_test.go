package scheduler

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"video-collection-api/config"
	"video-collection-api/pkg/ingest"
	"video-collection-api/pkg/store"
)

func TestPipelineExecutionPersistsAndDeduplicates(t *testing.T) {
	t.Setenv("COLLECTION_UPLOAD_DIR", t.TempDir())
	s, err := store.NewSQLiteStore(filepath.Join(t.TempDir(), "target.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	token, err := ingest.SaveUpload("input.csv", strings.NewReader("id,title,content\n1,标题,正文\n,缺少ID,正文\n"))
	if err != nil {
		t.Fatal(err)
	}
	src := config.SourceConfig{ID: "pipeline", Name: "import", Type: "pipeline", PageLimit: 1, TimeoutSec: 2, Filter: config.FilterRule{Pipeline: &config.PipelineRule{Version: 1, Input: "file", Target: "article", KeyField: "id", Duplicate: "skip", MaxRecords: 100, File: config.ImportFileRule{Token: token, HeaderRow: 1}, Fields: []config.FieldRule{{Target: "id", Selector: "id"}, {Target: "title", Selector: "title"}, {Target: "content", Selector: "content"}}}}}
	sc := &Scheduler{store: s, progress: map[string]*TaskProgress{}, maxLogs: 100}
	prog := &TaskProgress{StartTime: time.Now(), IsRunning: true}
	sc.runCollectTask(context.Background(), src, 0, prog)
	if prog.IsRunning || prog.TotalSaved != 1 || prog.TotalSkipped != 1 || prog.LastError != "" {
		t.Fatalf("first run: %+v", prog)
	}
	prog = &TaskProgress{StartTime: time.Now()}
	sc.runCollectTask(context.Background(), src, 0, prog)
	if prog.TotalSaved != 0 || prog.TotalSkipped != 2 {
		t.Fatalf("second run: %+v", prog)
	}
	src.Filter.Pipeline.Target = "video"
	prog = &TaskProgress{StartTime: time.Now()}
	sc.runCollectTask(context.Background(), src, 0, prog)
	if prog.TotalSaved != 1 || prog.LastError != "" {
		t.Fatalf("video run: %+v", prog)
	}
	_, total, err := s.QueryVideos(context.Background(), store.VideoQuery{Page: 1, PageSize: 20})
	if err != nil || total != 1 {
		t.Fatalf("video sink: %d %v", total, err)
	}
}
