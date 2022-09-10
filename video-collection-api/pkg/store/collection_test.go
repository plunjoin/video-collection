package store

import (
	"context"
	"path/filepath"
	"testing"

	"video-collection-api/config"
)

func TestCollectionRulePersistenceAndArticleDeduplication(t *testing.T) {
	ctx := context.Background()
	s, err := NewSQLiteStore(filepath.Join(t.TempDir(), "collection.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	src := config.SourceConfig{ID: "rule", Name: "规则", Type: "pipeline", Filter: config.FilterRule{Pipeline: &config.PipelineRule{Version: 1, Input: "file", Target: "article", KeyField: "id", Fields: []config.FieldRule{{Target: "title", Selector: "标题"}}}}}
	if err = s.SaveSource(ctx, src); err != nil {
		t.Fatal(err)
	}
	loaded, err := s.GetSourceByID(ctx, "rule")
	if err != nil || loaded.Filter.Pipeline.Fields[0].Selector != "标题" {
		t.Fatalf("rule lost: %+v %v", loaded, err)
	}
	r := CollectionRecord{SourceID: "rule", Target: "article", Key: "external-1", Values: map[string]string{"title": "初始标题", "content": "正文"}}
	if saved, err := s.SaveCollectionRecord(ctx, r, false); err != nil || !saved {
		t.Fatalf("save: %v %v", saved, err)
	}
	r.Values["title"] = "更新标题"
	if saved, err := s.SaveCollectionRecord(ctx, r, true); err != nil || saved {
		t.Fatalf("skip: %v %v", saved, err)
	}
	if saved, err := s.SaveCollectionRecord(ctx, r, false); err != nil || !saved {
		t.Fatalf("update: %v %v", saved, err)
	}
	rows, total, err := s.ListCollectionRecords(ctx, "rule", 1, 20)
	if err != nil || total != 1 || len(rows) != 1 {
		t.Fatalf("records: %v %d %v", rows, total, err)
	}
	article, err := s.GetContent(ctx, "news", rows[0].ContentID, 0, true)
	if err != nil || article.Title != "更新标题" || article.Status != "draft" {
		t.Fatalf("article: %+v %v", article, err)
	}
	article.Status = "published"
	if err := s.SaveContent(ctx, article, article.AuthorID, true); err != nil {
		t.Fatal(err)
	}
	r.Values["title"] = "不可覆盖"
	if saved, err := s.SaveCollectionRecord(ctx, r, false); err != nil || saved {
		t.Fatalf("published overwritten: %v %v", saved, err)
	}
	article, err = s.GetContent(ctx, "news", article.ID, 0, true)
	if err != nil || article.Title != "更新标题" {
		t.Fatalf("editorial change lost: %+v %v", article, err)
	}
	r.SourceID = "other"
	r.Target = "record"
	if saved, err := s.SaveCollectionRecord(ctx, r, false); err != nil || !saved {
		t.Fatal("other source identity collided", err)
	}
}
