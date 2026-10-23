package store

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
	"time"

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
	if err != nil || article.Title != "更新标题" || article.Status != "published" {
		t.Fatalf("article: %+v %v", article, err)
	}
	if article.SourceURL != "https://example.com/a" || article.SourceName != "Demo Source" || article.PublishedAt != "2026-10-01T12:00:00Z" {
		t.Fatalf("provenance fields: url=%q name=%q published=%q", article.SourceURL, article.SourceName, article.PublishedAt)
	}
	wantCreatedAt := time.Date(2026, time.October, 1, 12, 0, 0, 0, time.UTC)
	if !article.CreatedAt.Equal(wantCreatedAt) {
		t.Fatalf("created_at = %v, want %v", article.CreatedAt, wantCreatedAt)
	}
	r.Values["title"] = "已发布也可更新"
	r.Values["published_at"] = "2026-10-02T12:00:00Z"
	if saved, err := s.SaveCollectionRecord(ctx, r, false); err != nil || !saved {
		t.Fatalf("published update: %v %v", saved, err)
	}
	article, err = s.GetContent(ctx, "news", article.ID, 0, true)
	if err != nil || article.Title != "已发布也可更新" || article.Status != "published" {
		t.Fatalf("published update lost: %+v %v", article, err)
	}
	if article.PublishedAt != "2026-10-02T12:00:00Z" {
		t.Fatalf("published_at not updated: %q", article.PublishedAt)
	}
	r.Values["status"] = "draft"
	r.Values["title"] = "显式降为草稿"
	if saved, err := s.SaveCollectionRecord(ctx, r, false); err != nil || !saved {
		t.Fatalf("explicit demote: %v %v", saved, err)
	}
	article, err = s.GetContent(ctx, "news", article.ID, 0, true)
	if err != nil || article.Status != "draft" || article.Title != "显式降为草稿" {
		t.Fatalf("demote failed: %+v %v", article, err)
	}
	r.SourceID = "other"
	r.Target = "record"
	if saved, err := s.SaveCollectionRecord(ctx, r, false); err != nil || !saved {
		t.Fatal("other source identity collided", err)
	}
}

func TestCollectionArticleCreatedAtFromPublishedAt(t *testing.T) {
	ctx := context.Background()
	s, err := NewSQLiteStore(filepath.Join(t.TempDir(), "timestamps.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()

	want := time.Date(2026, time.October, 1, 12, 34, 56, 0, time.UTC)
	baseline := time.Date(2025, time.January, 2, 3, 4, 5, 0, time.UTC)
	tests := []struct {
		name        string
		publishedAt string
		want        time.Time
		omit        bool
	}{
		{name: "RFC3339", publishedAt: "2026-10-01T12:34:56Z", want: want},
		{name: "RFC3339Nano", publishedAt: "2026-10-01T12:34:56.123456789Z", want: want.Add(123456789 * time.Nanosecond)},
		{name: "positive_offset", publishedAt: "2026-10-01T20:34:56+08:00", want: want},
		{name: "negative_offset", publishedAt: "2026-10-01T08:34:56-04:00", want: want},
		{name: "compact_offset", publishedAt: "2026-10-01T20:34:56+0800", want: want},
		{name: "space_with_offset", publishedAt: "2026-10-01 20:34:56+08:00", want: want},
		{name: "space_with_compact_offset", publishedAt: "2026-10-01 20:34:56+0800", want: want},
		{name: "datetime", publishedAt: "2026-10-01 12:34:56", want: want},
		{name: "datetime_fraction", publishedAt: "2026-10-01 12:34:56.123456789", want: want.Add(123456789 * time.Nanosecond)},
		{name: "ISO_without_zone", publishedAt: "2026-10-01T12:34:56", want: want},
		{name: "minutes", publishedAt: "2026-10-01 12:34", want: want.Truncate(time.Minute)},
		{name: "date", publishedAt: "2026-10-01", want: want.Truncate(24 * time.Hour)},
		{name: "RFC1123Z", publishedAt: "Thu, 01 Oct 2026 20:34:56 +0800", want: want},
		{name: "RFC1123", publishedAt: "Thu, 01 Oct 2026 12:34:56 GMT", want: want},
		{name: "whitespace", publishedAt: " \t2026-10-01T12:34:56Z\n", want: want},
		{name: "missing", omit: true},
		{name: "empty"},
		{name: "whitespace_only", publishedAt: " \t\n"},
		{name: "invalid", publishedAt: "not a date"},
		{name: "invalid_date", publishedAt: "2026-02-30T12:34:56Z"},
		{name: "invalid_time", publishedAt: "2026-10-01T25:34:56Z"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			for _, operation := range []string{"insert", "update"} {
				t.Run(operation, func(t *testing.T) {
					r := CollectionRecord{SourceID: "timestamps", Target: "article", Key: t.Name(), Values: map[string]string{"title": "Timestamp test", "content": "Body"}}
					if operation == "update" {
						r.Values["published_at"] = baseline.Format(time.RFC3339)
						if saved, err := s.SaveCollectionRecord(ctx, r, false); err != nil || !saved {
							t.Fatalf("seed draft: saved=%v err=%v", saved, err)
						}
					}
					if tt.omit {
						delete(r.Values, "published_at")
					} else {
						r.Values["published_at"] = tt.publishedAt
					}
					before := time.Now().UTC()
					if saved, err := s.SaveCollectionRecord(ctx, r, false); err != nil || !saved {
						t.Fatalf("save: saved=%v err=%v", saved, err)
					}
					after := time.Now().UTC()

					var createdAt, updatedAt time.Time
					var publishedAt string
					if err := s.db.QueryRowContext(ctx, `SELECT c.created_at,c.updated_at,c.published_at FROM content_entries c JOIN collection_records r ON r.content_id=c.id WHERE r.source_id=$1 AND r.target=$2 AND r.record_key=$3`, r.SourceID, r.Target, r.Key).Scan(&createdAt, &updatedAt, &publishedAt); err != nil {
						t.Fatal(err)
					}
					expected := tt.want
					if expected.IsZero() && operation == "update" {
						expected = baseline
					}
					if expected.IsZero() {
						if createdAt.Before(before) || createdAt.After(after) {
							t.Fatalf("fallback created_at = %v, want between %v and %v", createdAt, before, after)
						}
					} else if !createdAt.Equal(expected) {
						t.Fatalf("created_at = %v, want %v", createdAt, expected)
					}
					if publishedAt != strings.TrimSpace(tt.publishedAt) {
						t.Fatalf("published_at = %q, want %q", publishedAt, strings.TrimSpace(tt.publishedAt))
					}
					if updatedAt.Before(before) || updatedAt.After(after) {
						t.Fatalf("updated_at = %v, want ingestion time between %v and %v", updatedAt, before, after)
					}
				})
			}
		})
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
		"actor_id":  "1892",
		"name":      "成龙 (Jackie Chan)",
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
