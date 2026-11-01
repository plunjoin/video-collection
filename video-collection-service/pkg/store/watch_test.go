package store

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"
	"time"
)

// 回归：早期版本创建的 watch_rooms 表没有 rate 列，打开旧库时应自动补齐，
// 否则建房会一直报 "table watch_rooms has no column named rate"。
func TestWatchOldDBUpgradeAddsRateColumn(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "old.db")
	raw, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatal(err)
	}
	oldSchema := `CREATE TABLE IF NOT EXISTS watch_rooms (
	 id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT NOT NULL UNIQUE, video_id INTEGER NOT NULL,
	 group_index INTEGER NOT NULL DEFAULT 0, episode_index INTEGER NOT NULL DEFAULT 0,
	 title TEXT NOT NULL DEFAULT '', host_id INTEGER NOT NULL,
	 version INTEGER NOT NULL DEFAULT 1, playing INTEGER NOT NULL DEFAULT 0,
	 position_ms INTEGER NOT NULL DEFAULT 0, anchor_ms INTEGER NOT NULL DEFAULT 0,
	 updated_by INTEGER NOT NULL DEFAULT 0,
	 created_at DATETIME NOT NULL, updated_at DATETIME NOT NULL
	);`
	if _, err = raw.Exec(oldSchema); err != nil {
		t.Fatal(err)
	}
	if err = raw.Close(); err != nil {
		t.Fatal(err)
	}

	s, err := NewSQLiteStore(dbPath)
	if err != nil {
		t.Fatalf("open old db: %v", err)
	}
	defer s.Close()

	room := &WatchRoom{Code: "ABC234", VideoID: 1, HostID: 1, Title: "旧库升级"}
	if err = s.CreateWatchRoom(context.Background(), room); err != nil {
		t.Fatalf("create room on upgraded db: %v", err)
	}
	got, err := s.GetWatchRoomByCode(context.Background(), "ABC234")
	if err != nil {
		t.Fatal(err)
	}
	if got.Rate <= 0 {
		t.Fatalf("rate should default to 1, got %v", got.Rate)
	}
}

// 回归：进度外推必须按房主倍速换算。
// 2x 倍速时成员目标进度每墙钟秒应前进 2 秒；0.5x 时只前进 0.5 秒，
// 否则倍速观看时成员会系统性领先/落后房主。
func TestWatchTargetPositionExtrapolatesWithRate(t *testing.T) {
	now := time.UnixMilli(1_000_000)
	room := &WatchRoom{Playing: true, PositionMs: 60_000, AnchorMs: now.UnixMilli()}

	room.Rate = 2
	if got := room.TargetPositionMs(now.Add(2 * time.Second)); got != 64_000 {
		t.Fatalf("2x rate: want 64000, got %d", got)
	}

	room.Rate = 0.5
	if got := room.TargetPositionMs(now.Add(3 * time.Second)); got != 61_500 {
		t.Fatalf("0.5x rate: want 61500, got %d", got)
	}

	// 暂停时不外推；倍速异常时按 1x 兜底。
	room.Rate = 2
	room.Playing = false
	if got := room.TargetPositionMs(now.Add(3 * time.Second)); got != 60_000 {
		t.Fatalf("paused: want 60000, got %d", got)
	}
	room.Playing = true
	room.Rate = 0
	if got := room.TargetPositionMs(now.Add(3 * time.Second)); got != 63_000 {
		t.Fatalf("zero rate fallback: want 63000, got %d", got)
	}

	// 外推硬上限 5 秒仍然生效。
	room.Rate = 4
	if got := room.TargetPositionMs(now.Add(60 * time.Second)); got != 65_000 {
		t.Fatalf("cap: want 65000, got %d", got)
	}
}
