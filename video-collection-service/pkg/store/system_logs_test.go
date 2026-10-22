package store

import (
	"context"
	"path/filepath"
	"testing"
)

func TestAppendAndListSystemLogs(t *testing.T) {
	s, err := NewSQLiteStore(filepath.Join(t.TempDir(), "system_logs.db"))
	if err != nil {
		t.Fatalf("init store: %v", err)
	}
	defer s.Close()
	ctx := context.Background()

	if err := s.AppendSystemLog(ctx, SystemLog{
		Level:     "INFO",
		Category:  "auth",
		Message:   "管理员登录成功",
		ActorID:   1,
		ActorName: "admin",
		Meta:      map[string]any{"ip": "127.0.0.1"},
	}); err != nil {
		t.Fatalf("append info: %v", err)
	}
	if err := s.AppendSystemLog(ctx, SystemLog{
		Level:    "warn",
		Category: "admin",
		Message:  "删除业务类型 demo",
		ActorID:  2,
		ActorName: "ops",
	}); err != nil {
		t.Fatalf("append warn: %v", err)
	}
	if err := s.AppendSystemLog(ctx, SystemLog{
		Level:    "error",
		Category: "collect",
		Message:  "触发采集失败",
	}); err != nil {
		t.Fatalf("append error: %v", err)
	}

	all, total, err := s.ListSystemLogs(ctx, SystemLogQuery{Page: 1, PageSize: 10})
	if err != nil {
		t.Fatalf("list all: %v", err)
	}
	if total != 3 || len(all) != 3 {
		t.Fatalf("expected 3 logs, got total=%d len=%d", total, len(all))
	}
	if all[0].Level != "error" || all[1].Level != "warn" || all[2].Level != "info" {
		t.Fatalf("unexpected order/levels: %+v", all)
	}
	if all[2].Meta["ip"] != "127.0.0.1" {
		t.Fatalf("expected meta ip preserved, got %+v", all[2].Meta)
	}

	filtered, total, err := s.ListSystemLogs(ctx, SystemLogQuery{Level: "warn", Category: "admin", Page: 1, PageSize: 10})
	if err != nil {
		t.Fatalf("list filtered: %v", err)
	}
	if total != 1 || len(filtered) != 1 || filtered[0].Message != "删除业务类型 demo" {
		t.Fatalf("unexpected filtered result total=%d data=%+v", total, filtered)
	}

	byQ, total, err := s.ListSystemLogs(ctx, SystemLogQuery{Q: "登录", Page: 1, PageSize: 10})
	if err != nil {
		t.Fatalf("list q: %v", err)
	}
	if total != 1 || len(byQ) != 1 || byQ[0].Category != "auth" {
		t.Fatalf("unexpected keyword result total=%d data=%+v", total, byQ)
	}

	if err := s.AppendSystemLog(ctx, SystemLog{Message: "   "}); err == nil {
		t.Fatal("expected empty message to fail")
	}
}

func TestSystemLogPruneKeepsLast5000(t *testing.T) {
	s, err := NewSQLiteStore(filepath.Join(t.TempDir(), "system_logs_prune.db"))
	if err != nil {
		t.Fatalf("init store: %v", err)
	}
	defer s.Close()
	ctx := context.Background()

	// Insert slightly over the retain limit using direct SQL for speed, then Append to trigger prune.
	tx, err := s.db.Begin()
	if err != nil {
		t.Fatalf("begin: %v", err)
	}
	for i := 0; i < systemLogRetainLimit+3; i++ {
		if _, err := tx.Exec(`INSERT INTO system_logs(level,category,message,actor_id,actor_name,meta,created_at) VALUES('info','system',$1,0,'','',CURRENT_TIMESTAMP)`, "seed"); err != nil {
			t.Fatalf("seed insert: %v", err)
		}
	}
	if err := tx.Commit(); err != nil {
		t.Fatalf("commit: %v", err)
	}
	if err := s.AppendSystemLog(ctx, SystemLog{Level: "info", Category: "system", Message: "trigger-prune"}); err != nil {
		t.Fatalf("append trigger: %v", err)
	}
	var count int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM system_logs`).Scan(&count); err != nil {
		t.Fatalf("count: %v", err)
	}
	if count != systemLogRetainLimit {
		t.Fatalf("expected retain %d, got %d", systemLogRetainLimit, count)
	}
	var newest string
	if err := s.db.QueryRow(`SELECT message FROM system_logs ORDER BY id DESC LIMIT 1`).Scan(&newest); err != nil {
		t.Fatalf("newest: %v", err)
	}
	if newest != "trigger-prune" {
		t.Fatalf("expected newest trigger-prune, got %q", newest)
	}
}
