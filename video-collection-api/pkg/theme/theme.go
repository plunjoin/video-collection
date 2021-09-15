package theme

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

	"video-collection-api/pkg/store"
)

// ThemeInfo 主题元信息
type ThemeInfo struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Version     string `json:"version"`
	Author      string `json:"author"`
	Description string `json:"description"`
	Preview     string `json:"preview"`
	IsActive    bool   `json:"is_active"`
	Path        string `json:"path"`
}

type Manager struct {
	store    store.Store
	themeDir string
	mu       sync.RWMutex
}

func NewManager(s store.Store, dir string) *Manager {
	if dir == "" {
		dir = "themes"
	}
	_ = os.MkdirAll(dir, 0755)
	return &Manager{
		store:    s,
		themeDir: dir,
	}
}

// GetActiveThemeID 获取当前激活的主题ID
func (m *Manager) GetActiveThemeID(ctx context.Context) string {
	val, err := m.store.GetSetting(ctx, "active_theme", "default")
	if err != nil || val == "" {
		return "default"
	}
	return val
}

// SetActiveTheme 切换激活的主题
func (m *Manager) SetActiveTheme(ctx context.Context, themeID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	themePath := filepath.Join(m.themeDir, themeID)
	if fi, err := os.Stat(themePath); err != nil || !fi.IsDir() {
		return fmt.Errorf("theme directory %s not found", themeID)
	}

	return m.store.SetSetting(ctx, "active_theme", themeID)
}

// ListThemes 扫描并列出所有已安装主题
func (m *Manager) ListThemes(ctx context.Context) ([]ThemeInfo, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	activeID := m.GetActiveThemeID(ctx)
	entries, err := os.ReadDir(m.themeDir)
	if err != nil {
		return nil, err
	}

	var list []ThemeInfo
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		themeID := entry.Name()
		jsonPath := filepath.Join(m.themeDir, themeID, "theme.json")

		info := ThemeInfo{
			ID:          themeID,
			Name:        themeID,
			Version:     "1.0.0",
			Author:      "未知",
			Description: "影视主题模板",
			Preview:     "",
			IsActive:    themeID == activeID,
			Path:        filepath.Join(m.themeDir, themeID),
		}

		if data, err := os.ReadFile(jsonPath); err == nil {
			_ = json.Unmarshal(data, &info)
			info.ID = themeID
			info.IsActive = (themeID == activeID)
			info.Path = filepath.Join(m.themeDir, themeID)
		}

		list = append(list, info)
	}

	return list, nil
}

// ImportThemeZip 从 ZIP 压缩包安全解压并导入新主题
func (m *Manager) ImportThemeZip(r io.ReaderAt, size int64) (*ThemeInfo, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	zr, err := zip.NewReader(r, size)
	if err != nil {
		return nil, fmt.Errorf("invalid zip file: %w", err)
	}

	// 探测根目录名或者 theme.json 所在位置
	var themeID string
	var hasThemeJSON bool

	for _, f := range zr.File {
		cleanName := filepath.Clean(f.Name)
		if strings.HasPrefix(cleanName, "..") {
			return nil, fmt.Errorf("unsafe file path detected in zip")
		}
		if filepath.Base(cleanName) == "theme.json" {
			hasThemeJSON = true
			parts := strings.Split(cleanName, string(filepath.Separator))
			if len(parts) > 1 {
				themeID = parts[0]
			}
		}
	}

	if themeID == "" {
		themeID = fmt.Sprintf("theme_%d", time.Now().Unix())
	}

	targetDir := filepath.Join(m.themeDir, themeID)
	_ = os.MkdirAll(targetDir, 0755)

	for _, f := range zr.File {
		cleanName := filepath.Clean(f.Name)
		// 剥离可能存在的顶层文件夹前缀
		relPath := cleanName
		if strings.HasPrefix(relPath, themeID+string(filepath.Separator)) {
			relPath = strings.TrimPrefix(relPath, themeID+string(filepath.Separator))
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

	info := &ThemeInfo{
		ID:          themeID,
		Name:        themeID,
		Version:     "1.0.0",
		Description: "导入的主题",
		Path:        targetDir,
	}

	jsonPath := filepath.Join(targetDir, "theme.json")
	if data, err := os.ReadFile(jsonPath); err == nil {
		_ = json.Unmarshal(data, info)
		info.ID = themeID
		info.Path = targetDir
	}

	_ = hasThemeJSON
	return info, nil
}

// GetThemeFilePath 获取当前激活主题中的文件绝对路径
func (m *Manager) GetThemeFilePath(ctx context.Context, relativeFile string) (string, error) {
	activeID := m.GetActiveThemeID(ctx)
	target := filepath.Join(m.themeDir, activeID, relativeFile)
	if _, err := os.Stat(target); err == nil {
		return target, nil
	}
	// 回退至 default 主题
	fallback := filepath.Join(m.themeDir, "default", relativeFile)
	if _, err := os.Stat(fallback); err == nil {
		return fallback, nil
	}
	return "", fmt.Errorf("file %s not found in theme", relativeFile)
}
