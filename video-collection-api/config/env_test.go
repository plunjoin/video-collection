package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadDotEnvDoesNotOverrideExisting(t *testing.T) {
	envPath := filepath.Join(t.TempDir(), ".env")
	content := "\uFEFFDB_SSLMODE=require\r\n# 注释\r\nDB_HOST=db-from-file\nexport DB_NAME=\"quoted_db\"\nDB_USER=file_user # 行尾注释\n"
	if err := os.WriteFile(envPath, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("DB_HOST", "db-from-container")
	t.Setenv("DB_NAME", "")
	os.Unsetenv("DB_NAME")
	t.Setenv("DB_USER", "")
	os.Unsetenv("DB_USER")
	t.Setenv("DB_SSLMODE", "")
	os.Unsetenv("DB_SSLMODE")

	isLoaded, err := LoadDotEnv(envPath)
	if err != nil || !isLoaded {
		t.Fatalf("isLoaded=%v err=%v", isLoaded, err)
	}
	if got := os.Getenv("DB_SSLMODE"); got != "require" {
		t.Errorf("DB_SSLMODE = %q, 首行 BOM 与 CRLF 应被正确处理", got)
	}
	if got := os.Getenv("DB_HOST"); got != "db-from-container" {
		t.Errorf("DB_HOST = %q, 容器变量应优先", got)
	}
	if got := os.Getenv("DB_NAME"); got != "quoted_db" {
		t.Errorf("DB_NAME = %q, 应去除引号", got)
	}
	if got := os.Getenv("DB_USER"); got != "file_user" {
		t.Errorf("DB_USER = %q, 应去除行尾注释", got)
	}
}

func TestApplyEnvOverrides(t *testing.T) {
	t.Setenv("DB_DSN", "")
	t.Setenv("DATABASE_URL", "")
	t.Setenv("DB_DRIVER", "postgres")
	t.Setenv("DB_HOST", "postgres")
	t.Setenv("DB_PORT", "5433")
	t.Setenv("DB_USER", "app")
	t.Setenv("DB_PASSWORD", "p@ss:word")
	t.Setenv("DB_NAME", "videodb")
	t.Setenv("DB_SSLMODE", "")
	t.Setenv("SQLITE_PATH", "")

	cfg := &AppConfig{Database: DatabaseConfig{DSN: "postgres://postgres:postgres@localhost:5432/videodb"}}
	ApplyEnvOverrides(cfg)

	want := "postgres://app:p%40ss%3Aword@postgres:5433/videodb?sslmode=disable"
	if cfg.Database.DSN != want {
		t.Errorf("DSN = %q, want %q", cfg.Database.DSN, want)
	}
	if cfg.Database.SQLitePath != "data/collection.db" {
		t.Errorf("SQLitePath = %q", cfg.Database.SQLitePath)
	}

	t.Setenv("DB_DSN", "postgres://u:secret@h:5432/d")
	ApplyEnvOverrides(cfg)
	if cfg.Database.DSN != "postgres://u:secret@h:5432/d" {
		t.Errorf("DB_DSN 应优先于分项配置, got %q", cfg.Database.DSN)
	}
}

func TestMaskDSN(t *testing.T) {
	got := MaskDSN("postgres://u:secret@h:5432/d?sslmode=disable")
	if got != "postgres://u:******@h:5432/d?sslmode=disable" {
		t.Errorf("MaskDSN = %q", got)
	}
}
