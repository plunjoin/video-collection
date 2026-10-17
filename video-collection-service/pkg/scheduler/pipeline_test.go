package scheduler

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"video-collection-service/config"
	"video-collection-service/pkg/ingest"
	"video-collection-service/pkg/store"
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

func TestPipelineExecution_MultiEpisodeSplitting(t *testing.T) {
	t.Setenv("COLLECTION_UPLOAD_DIR", t.TempDir())
	s, err := store.NewSQLiteStore(filepath.Join(t.TempDir(), "target_episodes.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()

	csvContent := "id,title,play_url,play_from\n101,进击的巨人,第01集$https://cdn.example.com/ep1.m3u8#第02集$https://cdn.example.com/ep2.m3u8,lzm3u8\n"
	token, err := ingest.SaveUpload("anime.csv", strings.NewReader(csvContent))
	if err != nil {
		t.Fatal(err)
	}

	src := config.SourceConfig{
		ID:         "anime_pipeline",
		Name:       "番剧采集",
		Type:       "pipeline",
		PageLimit:  1,
		TimeoutSec: 10,
		Filter: config.FilterRule{
			Pipeline: &config.PipelineRule{
				Version:    1,
				Input:      "file",
				Target:     "video",
				KeyField:   "id",
				Duplicate:  "update",
				MaxRecords: 10,
				File:       config.ImportFileRule{Token: token, HeaderRow: 1},
				Fields: []config.FieldRule{
					{Target: "id", Selector: "id"},
					{Target: "title", Selector: "title"},
					{Target: "play_url", Selector: "play_url"},
					{Target: "play_from", Selector: "play_from"},
				},
			},
		},
	}

	sc := &Scheduler{store: s, progress: map[string]*TaskProgress{}, maxLogs: 100}
	prog := &TaskProgress{StartTime: time.Now()}
	sc.runCollectTask(context.Background(), src, 0, prog)

	if prog.TotalSaved != 1 || prog.LastError != "" {
		t.Fatalf("run failed: %+v", prog)
	}

	videos, total, err := s.QueryVideos(context.Background(), store.VideoQuery{Keyword: "进击的巨人"})
	if err != nil || total != 1 {
		t.Fatalf("expected 1 video, got %d, err: %v", total, err)
	}

	detail, err := s.GetVideoByID(context.Background(), videos[0].ID)
	if err != nil {
		t.Fatal(err)
	}

	if len(detail.PlayGroups) != 1 {
		t.Fatalf("expected 1 play group, got %d", len(detail.PlayGroups))
	}

	group := detail.PlayGroups[0]
	if group.PlayerCode != "lzm3u8" {
		t.Errorf("expected player code lzm3u8, got %s", group.PlayerCode)
	}

	if len(group.Episodes) != 2 {
		t.Fatalf("expected 2 episodes split by #, got %d", len(group.Episodes))
	}

	if group.Episodes[0].Name != "第01集" || group.Episodes[0].URL != "https://cdn.example.com/ep1.m3u8" {
		t.Errorf("unexpected ep 0: %+v", group.Episodes[0])
	}
	if group.Episodes[1].Name != "第02集" || group.Episodes[1].URL != "https://cdn.example.com/ep2.m3u8" {
		t.Errorf("unexpected ep 1: %+v", group.Episodes[1])
	}
}
