package player

import (
	"archive/zip"
	"bytes"
	"context"
	"os"
	"path/filepath"
	"testing"
)

type mockStore struct {
	settings map[string]string
}

func (m *mockStore) GetSetting(ctx context.Context, key, defaultVal string) (string, error) {
	if val, ok := m.settings[key]; ok {
		return val, nil
	}
	return defaultVal, nil
}

func (m *mockStore) SetSetting(ctx context.Context, key, val string) error {
	m.settings[key] = val
	return nil
}

func TestPlayerManager(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "players_test_*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	ms := &mockStore{settings: make(map[string]string)}
	mgr := NewManager(nil, tmpDir)
	mgr.store = ms

	ctx := context.Background()

	// 1. 测试默认播放器是否存在
	players, err := mgr.ListPlayers(ctx)
	if err != nil {
		t.Fatalf("ListPlayers failed: %v", err)
	}
	if len(players) < 2 {
		t.Fatalf("expected at least 2 default players, got %d", len(players))
	}

	// 2. 测试默认激活播放器为 videojs
	active := mgr.GetActivePlayerID(ctx)
	if active != "videojs" {
		t.Errorf("expected default active player 'videojs', got %s", active)
	}

	// 3. 测试切换播放器
	if err := mgr.SetActivePlayer(ctx, "iframe"); err != nil {
		t.Fatalf("SetActivePlayer failed: %v", err)
	}
	active = mgr.GetActivePlayerID(ctx)
	if active != "iframe" {
		t.Errorf("expected active player 'iframe', got %s", active)
	}

	// 4. 测试更新配置
	newCfg := map[string]interface{}{
		"api_url_template": "https://example.com/play?url={url}",
	}
	if err := mgr.UpdatePlayerConfig(ctx, "iframe", newCfg); err != nil {
		t.Fatalf("UpdatePlayerConfig failed: %v", err)
	}

	activeInfo, err := mgr.GetActivePlayer(ctx)
	if err != nil {
		t.Fatalf("GetActivePlayer failed: %v", err)
	}
	if activeInfo.Config["api_url_template"] != "https://example.com/play?url={url}" {
		t.Errorf("expected updated api_url_template, got %v", activeInfo.Config["api_url_template"])
	}

	// 5. 测试 ZIP 导入播放器包
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	manifestData := `{"id":"custom_test","name":"测试第三方播放器","type":"custom"}`
	f, err := zw.Create("custom_test/player.json")
	if err != nil {
		t.Fatalf("create zip entry failed: %v", err)
	}
	_, _ = f.Write([]byte(manifestData))
	_ = zw.Close()

	reader := bytes.NewReader(buf.Bytes())
	imported, err := mgr.ImportPlayerZip(reader, int64(buf.Len()))
	if err != nil {
		t.Fatalf("ImportPlayerZip failed: %v", err)
	}
	if imported.ID != "custom_test" || imported.Name != "测试第三方播放器" {
		t.Errorf("imported player mismatch: %+v", imported)
	}

	// 验证在列表中能列出新导入的播放器
	allPlayers, _ := mgr.ListPlayers(ctx)
	found := false
	for _, p := range allPlayers {
		if p.ID == "custom_test" {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("imported player custom_test not found in ListPlayers")
	}

	_ = filepath.Walk
}
