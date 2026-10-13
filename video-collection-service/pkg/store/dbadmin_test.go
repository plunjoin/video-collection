package store

import (
	"context"
	"path/filepath"
	"testing"
)

func newDBAdminFixture(t *testing.T) *SQLiteStore {
	t.Helper()
	s, err := NewSQLiteStore(filepath.Join(t.TempDir(), "dbadmin.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = s.Close() })
	return s
}

func TestDBAdminInfoAndTables(t *testing.T) {
	s := newDBAdminFixture(t)
	ctx := context.Background()

	if s.Engine() != "sqlite" {
		t.Fatalf("engine = %s, want sqlite", s.Engine())
	}

	info, err := s.GetDBInfo(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if info.Engine != "sqlite" || info.Version == "" || info.FilePath == "" ||
		info.TableCount == 0 || info.SizeBytes <= 0 || info.BackupsDir == "" || info.ServerTime == "" {
		t.Fatalf("bad db info: %+v", info)
	}

	tables, err := s.ListDBTables(ctx)
	if err != nil {
		t.Fatal(err)
	}
	found := make(map[string]DBTableInfo)
	for _, tb := range tables {
		found[tb.Name] = tb
		if tb.ColumnCount == 0 || tb.Rows < 0 {
			t.Fatalf("bad table stats: %+v", tb)
		}
	}
	for _, name := range []string{"users", "videos", "settings", "play_sources", "categories"} {
		if _, ok := found[name]; !ok {
			t.Fatalf("missing table %s in %v", name, found)
		}
	}
}

func TestDBAdminBrowseTable(t *testing.T) {
	s := newDBAdminFixture(t)
	ctx := context.Background()
	for _, name := range []string{"孤岛惊魂", "海贼王", "火影忍者"} {
		if _, err := s.SaveVideoManual(ctx, &VideoRecord{Name: name}); err != nil {
			t.Fatal(err)
		}
	}

	result, err := s.BrowseTable(ctx, TableBrowseQuery{Table: "videos", Page: 1, PageSize: 2, OrderBy: "id"})
	if err != nil {
		t.Fatal(err)
	}
	if result.Total != 3 || len(result.Rows) != 2 || result.Page != 1 || result.PageSize != 2 {
		t.Fatalf("bad pagination: total=%d rows=%d %+v", result.Total, len(result.Rows), result)
	}
	if len(result.Columns) == 0 || result.Columns[0].Name != "id" {
		t.Fatalf("bad columns: %+v", result.Columns)
	}

	result, err = s.BrowseTable(ctx, TableBrowseQuery{Table: "videos", Page: 2, PageSize: 2, OrderBy: "id"})
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Rows) != 1 {
		t.Fatalf("page 2 should have 1 row, got %d", len(result.Rows))
	}

	// keyword 全列模糊匹配
	result, err = s.BrowseTable(ctx, TableBrowseQuery{Table: "videos", Keyword: "海贼"})
	if err != nil {
		t.Fatal(err)
	}
	if result.Total != 1 || len(result.Rows) != 1 || result.Rows[0]["name"] != "海贼王" {
		t.Fatalf("bad keyword search: %+v", result)
	}

	// keyword 含 LIKE 通配符时按字面匹配（无结果）
	result, err = s.BrowseTable(ctx, TableBrowseQuery{Table: "videos", Keyword: "100%"})
	if err != nil {
		t.Fatal(err)
	}
	if result.Total != 0 {
		t.Fatalf("escaped wildcard should not match: %+v", result)
	}

	if _, err := s.BrowseTable(ctx, TableBrowseQuery{Table: "no_such_table"}); err == nil {
		t.Fatal("want error for missing table")
	}
	if _, err := s.BrowseTable(ctx, TableBrowseQuery{Table: "videos", OrderBy: "bad_col"}); err == nil {
		t.Fatal("want error for unknown order column")
	}
	if _, err := s.BrowseTable(ctx, TableBrowseQuery{Table: ""}); err == nil {
		t.Fatal("want error for empty table name")
	}
}

func TestDBAdminBackupRestoreLifecycle(t *testing.T) {
	s := newDBAdminFixture(t)
	ctx := context.Background()
	videoID, err := s.SaveVideoManual(ctx, &VideoRecord{Name: "备份目标片"})
	if err != nil {
		t.Fatal(err)
	}

	backup, err := s.BackupDatabase(ctx, BackupOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if backup.Tables == 0 || backup.Rows == 0 || backup.SizeBytes <= 0 || backup.Filename == "" {
		t.Fatalf("bad backup result: %+v", backup)
	}

	list, err := s.ListBackups(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0].Filename != backup.Filename || list[0].Engine != "sqlite" || list[0].Rows == 0 {
		t.Fatalf("bad backup list: %+v", list)
	}

	// 指定表子集备份
	partial, err := s.BackupDatabase(ctx, BackupOptions{Tables: []string{"videos"}})
	if err != nil {
		t.Fatal(err)
	}
	if partial.Tables != 1 {
		t.Fatalf("partial backup should cover 1 table: %+v", partial)
	}
	// 指定不存在的表会被过滤，全部无效时报错
	if _, err := s.BackupDatabase(ctx, BackupOptions{Tables: []string{"no_such"}}); err == nil {
		t.Fatal("want error when no valid tables selected")
	}

	// dry-run 预览不写库
	preview, err := s.PreviewRestore(ctx, backup.Filename, "merge")
	if err != nil {
		t.Fatal(err)
	}
	if preview.Engine != "sqlite" || preview.Mode != "merge" || len(preview.Tables) == 0 {
		t.Fatalf("bad restore preview: %+v", preview)
	}
	if _, err := s.PreviewRestore(ctx, backup.Filename, "bad_mode"); err == nil {
		t.Fatal("want error for invalid restore mode")
	}
	if _, err := s.PreviewRestore(ctx, "missing_file.json", "merge"); err == nil {
		t.Fatal("want error for missing backup file")
	}

	// merge 恢复：删除该视频后恢复应原样找回
	if err := s.DeleteVideo(ctx, videoID); err != nil {
		t.Fatal(err)
	}
	restored, err := s.RestoreDatabase(ctx, backup.Filename, "merge")
	if err != nil {
		t.Fatal(err)
	}
	if restored.Mode != "merge" || restored.Inserted == 0 {
		t.Fatalf("bad merge restore: %+v", restored)
	}
	video, err := s.GetVideoByID(ctx, videoID)
	if err != nil || video == nil || video.Name != "备份目标片" {
		t.Fatalf("merge restore did not recover video: err=%v video=%+v", err, video)
	}

	// merge 再次恢复：主键冲突应全部跳过
	again, err := s.RestoreDatabase(ctx, backup.Filename, "merge")
	if err != nil {
		t.Fatal(err)
	}
	if again.Inserted != 0 || again.Skipped == 0 {
		t.Fatalf("second merge should skip all rows: %+v", again)
	}

	// replace 模式：清空目标表后重新导入
	replaced, err := s.RestoreDatabase(ctx, backup.Filename, "replace")
	if err != nil {
		t.Fatal(err)
	}
	if replaced.Mode != "replace" || replaced.Inserted == 0 {
		t.Fatalf("bad replace restore: %+v", replaced)
	}
	video, err = s.GetVideoByID(ctx, videoID)
	if err != nil || video == nil {
		t.Fatalf("replace restore lost video: err=%v", err)
	}

	// 删除备份后不可再恢复
	if err := s.DeleteBackup(ctx, backup.Filename); err != nil {
		t.Fatal(err)
	}
	if err := s.DeleteBackup(ctx, backup.Filename); err == nil {
		t.Fatal("want error deleting missing backup")
	}
	if _, err := s.RestoreDatabase(ctx, backup.Filename, "merge"); err == nil {
		t.Fatal("want error restoring deleted backup")
	}
	if err := s.DeleteBackup(ctx, "../etc/passwd"); err == nil {
		t.Fatal("want error for illegal backup filename")
	}
}

func TestDBAdminCleanup(t *testing.T) {
	s := newDBAdminFixture(t)
	ctx := context.Background()

	videoID, err := s.SaveVideoManual(ctx, &VideoRecord{Name: "清理测试片"})
	if err != nil {
		t.Fatal(err)
	}
	// 直接 SQL 造孤儿数据：play_sources 指向不存在的视频、孤儿评论、重复线路
	if _, err := s.db.Exec("INSERT INTO play_sources (video_id, player_code, episodes, updated_at) VALUES (9999, 'm3u8', '[]', CURRENT_TIMESTAMP)"); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec("INSERT INTO comments (target_type, target_id, user_id, content, created_at) VALUES ('video', 9999, 1, '孤儿评论', CURRENT_TIMESTAMP)"); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec("INSERT INTO play_sources (video_id, player_code, episodes, updated_at) VALUES (?, 'm3u8', '[]', CURRENT_TIMESTAMP)", videoID); err != nil {
		t.Fatal(err)
	}

	results, err := s.RunCleanup(ctx, []string{"orphan_play_sources", "orphan_comments", "dup_play_sources", "vacuum", "no_such_action"})
	if err != nil {
		t.Fatal(err)
	}
	byAction := make(map[string]CleanupResult)
	for _, res := range results {
		byAction[res.Action] = res
	}
	if res := byAction["orphan_play_sources"]; res.Affected != 1 || res.Error != "" {
		t.Fatalf("orphan_play_sources should remove 1: %+v", res)
	}
	if res := byAction["orphan_comments"]; res.Affected != 1 || res.Error != "" {
		t.Fatalf("orphan_comments should remove 1: %+v", res)
	}
	if res := byAction["dup_play_sources"]; res.Error != "" {
		t.Fatalf("dup_play_sources should not fail: %+v", res)
	}
	if res := byAction["vacuum"]; res.Error != "" {
		t.Fatalf("vacuum should not fail: %+v", res)
	}
	if res := byAction["no_such_action"]; res.Error == "" {
		t.Fatal("unknown action should report error")
	}

	// 清空类动作
	if _, err := s.db.Exec("INSERT INTO feedbacks (type, title, content) VALUES ('request', 't', 'c')"); err != nil {
		t.Fatal(err)
	}
	results, err = s.RunCleanup(ctx, []string{"clear_feedbacks"})
	if err != nil {
		t.Fatal(err)
	}
	if results[0].Affected != 1 {
		t.Fatalf("clear_feedbacks should remove 1: %+v", results[0])
	}

	if _, err := s.RunCleanup(ctx, []string{}); err != nil {
		t.Fatal(err)
	}
}

func TestDBAdminExecSQL(t *testing.T) {
	s := newDBAdminFixture(t)
	ctx := context.Background()

	result, err := s.ExecSQL(ctx, "SELECT COUNT(*) AS n FROM users")
	if err != nil {
		t.Fatal(err)
	}
	if result.Type != "select" || len(result.Columns) != 1 || len(result.Rows) != 1 {
		t.Fatalf("bad select result: %+v", result)
	}
	if n, ok := result.Rows[0]["n"].(int64); !ok || n != 1 {
		t.Fatalf("admin user count = %v, want 1", result.Rows[0]["n"])
	}

	result, err = s.ExecSQL(ctx, "DELETE FROM feedbacks")
	if err != nil {
		t.Fatal(err)
	}
	if result.Type != "write" || result.Message == "" {
		t.Fatalf("bad write result: %+v", result)
	}

	result, err = s.ExecSQL(ctx, "CREATE TABLE IF NOT EXISTS tmp_dbadmin_probe (id INTEGER)")
	if err != nil {
		t.Fatal(err)
	}
	if result.Type != "ddl" {
		t.Fatalf("bad ddl result: %+v", result)
	}

	if _, err := s.ExecSQL(ctx, "SELECT 1; SELECT 2"); err == nil {
		t.Fatal("want error for multiple statements")
	}
	if _, err := s.ExecSQL(ctx, "SELECT 1;"); err != nil {
		t.Fatalf("trailing semicolon should be accepted: %v", err)
	}
	if _, err := s.ExecSQL(ctx, "SELECT 'a;b' AS x"); err != nil {
		t.Fatalf("semicolon inside string literal should be accepted: %v", err)
	}
	if _, err := s.ExecSQL(ctx, "   "); err == nil {
		t.Fatal("want error for empty sql")
	}
	if _, err := s.ExecSQL(ctx, "SELECT * FROM no_such_table"); err == nil {
		t.Fatal("want error for invalid select")
	}
}

func TestDBAdminSQLHelpers(t *testing.T) {
	if !IsSingleStatement("SELECT 1") || !IsSingleStatement("SELECT 1;") ||
		IsSingleStatement("SELECT 1; SELECT 2") || IsSingleStatement("UPDATE t SET a=';;'; DROP TABLE t") {
		t.Fatal("IsSingleStatement misclassifies statements")
	}
	if ClassifySQL("select 1") != "select" || ClassifySQL("with x as (select 1) select * from x") != "select" ||
		ClassifySQL("DELETE FROM t") != "write" || ClassifySQL("CREATE TABLE t (id int)") != "ddl" ||
		ClassifySQL("VACUUM") != "ddl" {
		t.Fatal("ClassifySQL misclassifies statements")
	}
}
