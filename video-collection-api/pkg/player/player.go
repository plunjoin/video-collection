package player

import (
	"archive/zip"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// SettingStore 设置存储接口
type SettingStore interface {
	GetSetting(ctx context.Context, key, defaultVal string) (string, error)
	SetSetting(ctx context.Context, key, val string) error
}

// PlayerInfo 播放器元信息
type PlayerInfo struct {
	ID          string                 `json:"id"`
	Name        string                 `json:"name"`
	Version     string                 `json:"version"`
	Author      string                 `json:"author"`
	Description string                 `json:"description"`
	Type        string                 `json:"type"` // "videojs", "iframe", "custom"
	Entry       string                 `json:"entry"`
	IsActive    bool                   `json:"is_active"`
	Config      map[string]interface{} `json:"config"`
	Path        string                 `json:"path"`
}

type Manager struct {
	store     SettingStore
	playerDir string
	mu        sync.RWMutex
}

func NewManager(s SettingStore, dir string) *Manager {
	if dir == "" {
		dir = "players"
	}
	_ = os.MkdirAll(dir, 0755)
	m := &Manager{
		store:     s,
		playerDir: dir,
	}
	m.EnsureDefaultPlayers()
	return m
}

// EnsureDefaultPlayers 确保默认播放器存在
func (m *Manager) EnsureDefaultPlayers() {
	m.mu.Lock()
	defer m.mu.Unlock()

	// 1. 内置 Video.js 现代化超清播放器
	videojsDir := filepath.Join(m.playerDir, "videojs")
	_ = os.MkdirAll(videojsDir, 0755)
	videojsJson := filepath.Join(videojsDir, "player.json")
	if _, err := os.Stat(videojsJson); os.IsNotExist(err) {
		p := PlayerInfo{
			ID:          "videojs",
			Name:        "极光超清播放器 (Video.js 深度增强版)",
			Version:     "2.0.0",
			Author:      "Antigravity Team",
			Description: "基于 Video.js 现代流媒体引擎，内置画质超清增强引擎(支持开关)、ControlBar 线路切换与选集抽屉、自动播放下一集(默认开启)",
			Type:        "videojs",
			Entry:       "player.html",
			Config: map[string]interface{}{
				"enhance_default":   true,
				"autoplay_next":     true,
				"next_countdown":    3,
				"enable_shortcuts":  true,
			},
		}
		data, _ := json.MarshalIndent(p, "", "  ")
		_ = os.WriteFile(videojsJson, data, 0644)
	}

	// 2. 第三方/解析接口播放器
	iframeDir := filepath.Join(m.playerDir, "iframe")
	_ = os.MkdirAll(iframeDir, 0755)
	iframeJson := filepath.Join(iframeDir, "player.json")
	if _, err := os.Stat(iframeJson); os.IsNotExist(err) {
		p := PlayerInfo{
			ID:          "iframe",
			Name:        "第三方解析/嵌入式播放器 (iFrame)",
			Version:     "1.0.0",
			Author:      "Antigravity Team",
			Description: "支持接入任意第三方解析接口或播放器页面，直接通过 URL 模板传入视频源地址进行 iframe 嵌入播放",
			Type:        "iframe",
			Entry:       "",
			Config: map[string]interface{}{
				"api_url_template": "https://jx.jsonplayer.com/player/?url={url}",
				"allow_fullscreen": true,
			},
		}
		data, _ := json.MarshalIndent(p, "", "  ")
		_ = os.WriteFile(iframeJson, data, 0644)
	}
}

// GetActivePlayerID 获取当前激活的播放器ID
func (m *Manager) GetActivePlayerID(ctx context.Context) string {
	val, err := m.store.GetSetting(ctx, "active_player", "videojs")
	if err != nil || val == "" {
		return "videojs"
	}
	return val
}

// SetActivePlayer 切换激活的播放器
func (m *Manager) SetActivePlayer(ctx context.Context, playerID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	pPath := filepath.Join(m.playerDir, playerID)
	if fi, err := os.Stat(pPath); err != nil || !fi.IsDir() {
		return fmt.Errorf("播放器目录 %s 不存在", playerID)
	}

	return m.store.SetSetting(ctx, "active_player", playerID)
}

// GetActivePlayer 获取当前激活的播放器详细信息
func (m *Manager) GetActivePlayer(ctx context.Context) (*PlayerInfo, error) {
	activeID := m.GetActivePlayerID(ctx)
	players, err := m.ListPlayers(ctx)
	if err != nil {
		return nil, err
	}
	for _, p := range players {
		if p.ID == activeID {
			return &p, nil
		}
	}
	// 如果未找到，默认返回第一个或者默认配置
	if len(players) > 0 {
		return &players[0], nil
	}
	return &PlayerInfo{
		ID:       "videojs",
		Name:     "Video.js 默认播放器",
		Type:     "videojs",
		IsActive: true,
	}, nil
}

// ListPlayers 扫描并列出所有已安装的播放器
func (m *Manager) ListPlayers(ctx context.Context) ([]PlayerInfo, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	activeID := m.GetActivePlayerID(ctx)
	entries, err := os.ReadDir(m.playerDir)
	if err != nil {
		return nil, err
	}

	var list []PlayerInfo
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		playerID := entry.Name()
		jsonPath := filepath.Join(m.playerDir, playerID, "player.json")

		info := PlayerInfo{
			ID:          playerID,
			Name:        playerID,
			Version:     "1.0.0",
			Author:      "未知",
			Description: "自定义播放器",
			Type:        "custom",
			IsActive:    playerID == activeID,
			Path:        filepath.Join(m.playerDir, playerID),
			Config:      make(map[string]interface{}),
		}

		if data, err := os.ReadFile(jsonPath); err == nil {
			_ = json.Unmarshal(data, &info)
			info.ID = playerID
			info.IsActive = (playerID == activeID)
			info.Path = filepath.Join(m.playerDir, playerID)
		}

		list = append(list, info)
	}

	return list, nil
}

// UpdatePlayerConfig 更新特定播放器的配置项
func (m *Manager) UpdatePlayerConfig(ctx context.Context, playerID string, newConfig map[string]interface{}) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	jsonPath := filepath.Join(m.playerDir, playerID, "player.json")
	var info PlayerInfo
	if data, err := os.ReadFile(jsonPath); err == nil {
		_ = json.Unmarshal(data, &info)
	} else {
		info = PlayerInfo{
			ID:   playerID,
			Name: playerID,
			Type: "custom",
		}
	}

	if info.Config == nil {
		info.Config = make(map[string]interface{})
	}
	for k, v := range newConfig {
		info.Config[k] = v
	}

	data, err := json.MarshalIndent(info, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(jsonPath, data, 0644)
}

// ImportPlayerZip 从 ZIP 压缩包安全解压并导入新播放器（类似主题导入）
func (m *Manager) ImportPlayerZip(r io.ReaderAt, size int64) (*PlayerInfo, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	zr, err := zip.NewReader(r, size)
	if err != nil {
		return nil, fmt.Errorf("无效的 ZIP 压缩包: %w", err)
	}

	var playerID string
	var hasPlayerJSON bool

	for _, f := range zr.File {
		cleanName := filepath.Clean(f.Name)
		if strings.HasPrefix(cleanName, "..") {
			return nil, fmt.Errorf("ZIP 文件内检测到不安全的相对路径")
		}
		if filepath.Base(cleanName) == "player.json" {
			hasPlayerJSON = true
			parts := strings.Split(cleanName, string(filepath.Separator))
			if len(parts) > 1 {
				playerID = parts[0]
			}
		}
	}

	if playerID == "" {
		playerID = fmt.Sprintf("player_%d", time.Now().Unix())
	}

	targetDir := filepath.Join(m.playerDir, playerID)
	_ = os.MkdirAll(targetDir, 0755)

	for _, f := range zr.File {
		cleanName := filepath.Clean(f.Name)
		relPath := cleanName
		if strings.HasPrefix(relPath, playerID+string(filepath.Separator)) {
			relPath = strings.TrimPrefix(relPath, playerID+string(filepath.Separator))
		}
		if relPath == "." || relPath == "" {
			continue
		}

		destPath := filepath.Join(targetDir, relPath)
		if f.FileInfo().IsDir() {
			_ = os.MkdirAll(destPath, 0755)
			continue
		}

		_ = os.MkdirAll(filepath.Dir(destPath), 0755)
		outFile, err := os.OpenFile(destPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, f.Mode())
		if err != nil {
			return nil, err
		}
		rc, err := f.Open()
		if err != nil {
			outFile.Close()
			return nil, err
		}
		_, err = io.Copy(outFile, rc)
		rc.Close()
		outFile.Close()
		if err != nil {
			return nil, err
		}
	}

	info := &PlayerInfo{
		ID:          playerID,
		Name:        playerID,
		Version:     "1.0.0",
		Description: "导入的播放器插件",
		Type:        "custom",
		Path:        targetDir,
		Config:      make(map[string]interface{}),
	}

	jsonPath := filepath.Join(targetDir, "player.json")
	if data, err := os.ReadFile(jsonPath); err == nil {
		_ = json.Unmarshal(data, info)
		info.ID = playerID
		info.Path = targetDir
	}

	_ = hasPlayerJSON
	return info, nil
}
