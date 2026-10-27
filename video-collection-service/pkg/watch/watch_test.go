package watch

import (
	"testing"
	"time"
)

// TestRoomCode 测试房间码生成
func TestRoomCode(t *testing.T) {
	codes := make(map[string]bool)
	
	// 生成100个房间码,确保都是唯一的
	for i := 0; i < 100; i++ {
		code, err := generateRoomCode()
		if err != nil {
			t.Fatalf("生成房间码失败: %v", err)
		}
		
		if len(code) != 6 {
			t.Errorf("房间码长度应该是6,实际是 %d: %s", len(code), code)
		}
		
		if codes[code] {
			t.Errorf("房间码重复: %s", code)
		}
		codes[code] = true
	}
}

// TestPlaybackState 测试播放状态更新
func TestPlaybackState(t *testing.T) {
	state := &PlaybackState{
		Playing:      false,
		PositionMs:   0,
		Rate:         1.0,
		ServerTsMs:   time.Now().UnixMilli(),
		Revision:     0,
		VideoID:      1,
		RouteIndex:   0,
		EpisodeIndex: 0,
		HostUserID:   1,
		UpdatedAt:    time.Now(),
	}
	
	// 测试播放
	state.Playing = true
	state.Revision++
	
	if !state.Playing {
		t.Error("播放状态应该为true")
	}
	if state.Revision != 1 {
		t.Errorf("版本号应该是1,实际是 %d", state.Revision)
	}
	
	// 测试seek
	state.PositionMs = 5000
	state.Revision++
	
	if state.PositionMs != 5000 {
		t.Errorf("位置应该是5000,实际是 %d", state.PositionMs)
	}
	if state.Revision != 2 {
		t.Errorf("版本号应该是2,实际是 %d", state.Revision)
	}
}

// TestMaxParticipants 测试最大参与人数限制
func TestMaxParticipants(t *testing.T) {
	room := &Room{
		MaxParticipants: 6,
	}
	
	if room.MaxParticipants != 6 {
		t.Errorf("最大参与人数应该是6,实际是 %d", room.MaxParticipants)
	}
}

// TestRoomExpiration 测试房间过期时间
func TestRoomExpiration(t *testing.T) {
	now := time.Now()
	room := &Room{
		CreatedAt: now,
		ExpiresAt: now.Add(4 * time.Hour),
	}
	
	duration := room.ExpiresAt.Sub(room.CreatedAt)
	expectedDuration := 4 * time.Hour
	
	if duration != expectedDuration {
		t.Errorf("过期时间应该是4小时,实际是 %v", duration)
	}
}
