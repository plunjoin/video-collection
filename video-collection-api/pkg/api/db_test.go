package api

import (
	"fmt"
	"testing"

	"video-collection-api/pkg/store"
)

func TestDatabaseAdminEndpoints(t *testing.T) {
	f := newContentFixture(t)

	// 管理员鉴权：未登录与普通用户均被拦截
	f.request("GET", "/api/admin/db/info", "", nil, 401)
	f.request("GET", "/api/admin/db/info", "", f.alice, 401)
	f.request("GET", "/api/admin/db/tables", "", f.bob, 401)

	// 引擎信息
	info := decodeContentData[store.DBInfo](t, f.request("GET", "/api/admin/db/info", "", f.admin, 200))
	if info.Engine != "sqlite" || info.TableCount == 0 || info.BackupsDir == "" {
		t.Fatalf("bad db info: %+v", info)
	}
	f.request("POST", "/api/admin/db/info", "", f.admin, 405)

	// 表列表统计
	tables := decodeContentData[[]store.DBTableInfo](t, f.request("GET", "/api/admin/db/tables", "", f.admin, 200))
	if len(tables) == 0 {
		t.Fatal("empty table list")
	}

	// 表数据浏览：写入两条视频后分页浏览
	videoID, err := f.s.SaveVideoManual(t.Context(), &store.VideoRecord{Name: "接口测试片甲"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.s.SaveVideoManual(t.Context(), &store.VideoRecord{Name: "接口测试片乙"}); err != nil {
		t.Fatal(err)
	}
	browse := decodeContentData[store.TableBrowseResult](t,
		f.request("GET", "/api/admin/db/table?table=videos&page=1&page_size=1&order_by=id", "", f.admin, 200))
	if browse.Total != 2 || len(browse.Rows) != 1 || browse.PageSize != 1 || len(browse.Columns) == 0 {
		t.Fatalf("bad browse result: %+v", browse)
	}
	if browse.Rows[0]["name"] != "接口测试片甲" {
		t.Fatalf("bad browse row: %+v", browse.Rows[0])
	}
	keyword := decodeContentData[store.TableBrowseResult](t,
		f.request("GET", "/api/admin/db/table?table=videos&keyword=%E7%94%B2", "", f.admin, 200))
	if keyword.Total != 1 || keyword.Rows[0]["id"].(float64) != float64(videoID) {
		t.Fatalf("bad keyword browse: %+v", keyword)
	}
	f.request("GET", "/api/admin/db/table?table=no_such_table", "", f.admin, 400)
	f.request("GET", "/api/admin/db/table", "", f.admin, 400)

	// 备份创建与列表
	backup := decodeContentData[store.BackupResult](t, f.request("POST", "/api/admin/db/backup", `{}`, f.admin, 200))
	if backup.Filename == "" || backup.Tables == 0 || backup.Rows == 0 {
		t.Fatalf("bad backup: %+v", backup)
	}
	list := decodeContentData[[]store.BackupMeta](t, f.request("GET", "/api/admin/db/backups", "", f.admin, 200))
	if len(list) != 1 || list[0].Filename != backup.Filename || list[0].Engine != "sqlite" {
		t.Fatalf("bad backup list: %+v", list)
	}

	// 恢复：dry_run 预览 → 未确认 400 → 确认后执行
	preview := decodeContentData[store.RestorePreview](t,
		f.request("POST", "/api/admin/db/restore", fmt.Sprintf(`{"file":%q,"mode":"merge","dry_run":true}`, backup.Filename), f.admin, 200))
	if preview.Engine != "sqlite" || len(preview.Tables) == 0 {
		t.Fatalf("bad restore preview: %+v", preview)
	}
	f.request("POST", "/api/admin/db/restore", fmt.Sprintf(`{"file":%q,"mode":"merge"}`, backup.Filename), f.admin, 400)
	f.request("POST", "/api/admin/db/restore", fmt.Sprintf(`{"file":%q,"mode":"bad_mode","confirm":true}`, backup.Filename), f.admin, 400)
	f.request("POST", "/api/admin/db/restore", `{"mode":"merge","confirm":true}`, f.admin, 400)
	restored := decodeContentData[store.RestoreResult](t,
		f.request("POST", "/api/admin/db/restore", fmt.Sprintf(`{"file":%q,"mode":"merge","confirm":true}`, backup.Filename), f.admin, 200))
	if restored.Mode != "merge" || restored.File != backup.Filename {
		t.Fatalf("bad restore result: %+v", restored)
	}

	// 清理维护：未确认 400 → 确认后执行并返回逐项结果
	f.request("POST", "/api/admin/db/cleanup", `{"actions":["vacuum"]}`, f.admin, 400)
	f.request("POST", "/api/admin/db/cleanup", `{"actions":[],"confirm":true}`, f.admin, 400)
	cleanups := decodeContentData[[]store.CleanupResult](t,
		f.request("POST", "/api/admin/db/cleanup", `{"actions":["vacuum","orphan_play_sources"],"confirm":true}`, f.admin, 200))
	if len(cleanups) != 2 || cleanups[0].Action != "vacuum" || cleanups[0].Error != "" {
		t.Fatalf("bad cleanup results: %+v", cleanups)
	}

	// SQL 执行器：只读直接执行、写语句需确认、多条语句拒绝
	selectRes := decodeContentData[store.SQLExecResult](t,
		f.request("POST", "/api/admin/db/sql", `{"sql":"SELECT COUNT(*) AS n FROM videos"}`, f.admin, 200))
	if selectRes.Type != "select" || len(selectRes.Rows) != 1 || selectRes.Rows[0]["n"].(float64) != 2 {
		t.Fatalf("bad sql select: %+v", selectRes)
	}
	f.request("POST", "/api/admin/db/sql", `{"sql":"DELETE FROM feedbacks"}`, f.admin, 400)
	f.request("POST", "/api/admin/db/sql", `{"sql":"SELECT 1; SELECT 2"}`, f.admin, 400)
	f.request("POST", "/api/admin/db/sql", `{"sql":""}`, f.admin, 400)
	f.request("POST", "/api/admin/db/sql", `{"sql":"SELECT * FROM no_such_table"}`, f.admin, 400)
	writeRes := decodeContentData[store.SQLExecResult](t,
		f.request("POST", "/api/admin/db/sql", `{"sql":"UPDATE videos SET hits = 5 WHERE id = 1","confirm":true}`, f.admin, 200))
	if writeRes.Type != "write" || writeRes.Affected != 1 {
		t.Fatalf("bad sql write: %+v", writeRes)
	}
	ddlRes := decodeContentData[store.SQLExecResult](t,
		f.request("POST", "/api/admin/db/sql", `{"sql":"CREATE TABLE IF NOT EXISTS tmp_probe (id INTEGER)","confirm":true}`, f.admin, 200))
	if ddlRes.Type != "ddl" {
		t.Fatalf("bad sql ddl: %+v", ddlRes)
	}

	// 删除备份：未确认 400 → 确认后删除
	f.request("DELETE", "/api/admin/db/backups?file="+backup.Filename, "", f.admin, 400)
	f.request("DELETE", "/api/admin/db/backups", "", f.admin, 400)
	f.request("DELETE", fmt.Sprintf("/api/admin/db/backups?file=%s&confirm=1", backup.Filename), "", f.admin, 200)
	list = decodeContentData[[]store.BackupMeta](t, f.request("GET", "/api/admin/db/backups", "", f.admin, 200))
	if len(list) != 0 {
		t.Fatalf("backup should be deleted: %+v", list)
	}
}
