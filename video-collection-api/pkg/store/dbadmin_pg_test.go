package store

import (
	"context"
	"testing"
)

// PG 集成测试：本机无 PostgreSQL 时自动跳过，使用独立测试库避免污染业务数据
func newPostgresDBAdminFixture(t *testing.T) *PostgresStore {
	t.Helper()
	s, err := NewPostgresStore("postgres://postgres@localhost:5432/videodb_dbadmin_test?sslmode=disable")
	if err != nil {
		t.Skipf("Skipping PostgreSQL dbadmin integration test: %v", err)
	}
	t.Cleanup(func() { _ = s.Close() })
	return s
}

func TestDBAdminPostgresIntegration(t *testing.T) {
	s := newPostgresDBAdminFixture(t)
	ctx := context.Background()

	if s.Engine() != "postgres" {
		t.Fatalf("engine = %s, want postgres", s.Engine())
	}

	info, err := s.GetDBInfo(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if info.Engine != "postgres" || info.Database == "" || info.Host == "" || info.SizeBytes <= 0 {
		t.Fatalf("bad postgres info: %+v", info)
	}

	// 新库从未 ANALYZE，reltuples 为 -1：列表统计必须回退精确计数，不得出现负数行数
	tables, err := s.ListDBTables(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, tb := range tables {
		if tb.Rows < 0 {
			t.Fatalf("table %s has negative rows: %+v", tb.Name, tb)
		}
	}

	// 测试库跨运行持久存在，清掉历史残留保证断言幂等
	if _, err := s.db.Exec("DELETE FROM videos"); err != nil {
		t.Fatal(err)
	}

	videoID, err := s.SaveVideoManual(ctx, &VideoRecord{Name: "PG集成测试片"})
	if err != nil {
		t.Fatal(err)
	}

	// keyword 浏览依赖 lib/pq 的 $N 位置占位符
	result, err := s.BrowseTable(ctx, TableBrowseQuery{Table: "videos", Keyword: "集成测试"})
	if err != nil {
		t.Fatalf("keyword browse failed on postgres: %v", err)
	}
	if result.Total != 1 {
		t.Fatalf("keyword total = %d, want 1", result.Total)
	}
	if id, _ := result.Rows[0]["id"].(int64); id != int64(videoID) {
		t.Fatalf("keyword row id = %v, want %d", result.Rows[0]["id"], videoID)
	}

	// 备份 + replace 恢复：TRUNCATE CASCADE 处理外键、jsonb 列显式转换、序列校正
	backup, err := s.BackupDatabase(ctx, BackupOptions{})
	if err != nil {
		t.Fatal(err)
	}
	restored, err := s.RestoreDatabase(ctx, backup.Filename, "replace")
	if err != nil {
		t.Fatalf("replace restore failed on postgres: %v", err)
	}
	if restored.Inserted == 0 {
		t.Fatalf("replace restored nothing: %+v", restored)
	}
	video, err := s.GetVideoByID(ctx, videoID)
	if err != nil || video == nil || video.Name != "PG集成测试片" {
		t.Fatalf("video lost after replace restore: err=%v video=%+v", err, video)
	}

	// replace 写回显式主键后，SERIAL 序列必须被校正，否则新插入会撞主键
	newID, err := s.SaveVideoManual(ctx, &VideoRecord{Name: "序列校验片"})
	if err != nil {
		t.Fatal(err)
	}
	if newID <= videoID {
		t.Fatalf("serial sequence not advanced after restore: newID=%d videoID=%d", newID, videoID)
	}

	// merge 恢复应全部跳过（主键冲突）
	merged, err := s.RestoreDatabase(ctx, backup.Filename, "merge")
	if err != nil {
		t.Fatal(err)
	}
	if merged.Inserted != 0 {
		t.Fatalf("merge after replace should insert nothing: %+v", merged)
	}

	// vacuum 在 PG 下应为 VACUUM (ANALYZE)
	results, err := s.RunCleanup(ctx, []string{"vacuum", "orphan_play_sources"})
	if err != nil {
		t.Fatal(err)
	}
	if results[0].Error != "" {
		t.Fatalf("vacuum failed on postgres: %+v", results[0])
	}
	if results[1].Error == "" {
		t.Fatal("orphan_play_sources should report missing table on postgres")
	}

	_ = s.DeleteVideo(ctx, newID)
	_ = s.DeleteVideo(ctx, videoID)
	if err := s.DeleteBackup(ctx, backup.Filename); err != nil {
		t.Fatal(err)
	}
}
