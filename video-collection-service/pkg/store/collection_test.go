package store

import (
	"context"
	"path/filepath"
	"testing"

	"video-collection-service/config"
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
	r := CollectionRecord{SourceID: "rule", Target: "article", Key: "external-1", Values: map[string]string{"title": "初始标题", "content": "正文", "url": "https://example.com/a", "source_name": "Demo Source", "published_at": "2026-10-01T12:00:00Z"}}
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
	if article.SourceURL != "https://example.com/a" || article.SourceName != "Demo Source" || article.PublishedAt != "2026-10-01T12:00:00Z" {
		t.Fatalf("provenance fields: url=%q name=%q published=%q", article.SourceURL, article.SourceName, article.PublishedAt)
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

func TestCollectionRecordRectificationAndCalibration(t *testing.T) {
	ctx := context.Background()
	s, err := NewSQLiteStore(filepath.Join(t.TempDir(), "rectify.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()

	// 1. 测试注入样本数据
	count, err := s.ImportSampleCollectionRecords(ctx, "rule_demo", "record")
	if err != nil || count != 5 {
		t.Fatalf("ImportSampleCollectionRecords failed: count=%d, err=%v", count, err)
	}

	// 2. 检索并校验
	rows, total, err := s.ListCollectionRecords(ctx, "rule_demo", 1, 10)
	if err != nil || total != 5 || len(rows) != 5 {
		t.Fatalf("ListCollectionRecords failed: total=%d, len=%d, err=%v", total, len(rows), err)
	}

	// 3. 在线校正字段
	targetKey := "tmdb_person_1892"
	newValues := map[string]string{
		"actor_id": "1892",
		"name":     "成龙 (Jackie Chan)",
		"biography": "华语功夫电影巨星",
	}
	if err := s.UpdateCollectionRecord(ctx, "rule_demo", "record", targetKey, newValues); err != nil {
		t.Fatalf("UpdateCollectionRecord failed: %v", err)
	}

	// 4. 校正入库为 Wiki 实体
	sub, err := s.RectifyCollectionRecordToWiki(ctx, "rule_demo", "record", targetKey, WikiSubject{
		Name:         "成龙",
		OriginalName: "Jackie Chan",
		Type:         "person",
		SubType:      "actor",
		Summary:      "华语功夫电影巨星，奥斯卡终身成就奖得主",
		Infobox:      map[string]any{"代表作": "警察故事"},
	})
	if err != nil || sub == nil || sub.ID <= 0 {
		t.Fatalf("RectifyCollectionRecordToWiki failed: sub=%+v, err=%v", sub, err)
	}

	// 检查 content_id 是否绑定
	rows, _, _ = s.ListCollectionRecords(ctx, "rule_demo", 1, 10)
	var found *CollectionRecord
	for _, r := range rows {
		if r.Key == targetKey {
			found = &r
			break
		}
	}
	if found == nil || found.ContentID != sub.ID {
		t.Fatalf("ContentID not linked: %+v", found)
	}

	// 5. 删除记录
	if err := s.DeleteCollectionRecord(ctx, "rule_demo", "record", targetKey); err != nil {
		t.Fatalf("DeleteCollectionRecord failed: %v", err)
	}
	rowsAfter, totalAfter, _ := s.ListCollectionRecords(ctx, "rule_demo", 1, 10)
	if totalAfter != 4 || len(rowsAfter) != 4 {
		t.Fatalf("Delete failed, total=%d", totalAfter)
	}
}

