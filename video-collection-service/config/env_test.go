package config

import (
	"net/url"
	"os"
	"path/filepath"
	"strings"
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
	// 密码含未转义字符时 url.Parse 会失败，必须走字符串兜底脱敏，绝不能把明文写进日志
	raw := "postgres://u:p%ss@//h/:5432/d?sslmode=disable"
	if masked := MaskDSN(raw); strings.Contains(masked, "p%ss") {
		t.Errorf("密码明文泄漏: %q", masked)
	} else if masked != "postgres://u:******@//h/:5432/d?sslmode=disable" {
		t.Errorf("MaskDSN = %q", masked)
	}
}

func TestNormalizeDSNRepairsSlashHost(t *testing.T) {
	cases := []struct {
		name     string
		in       string
		wantHost string
		wantDB   string
		warned   bool
	}{
		{
			name:     "主机被写成 //host/ 且端口前多斜杠",
			in:       "postgres://x21_admin:pw@//1panel-postgresql-hi3r/:5432/videodb?sslmode=disable",
			wantHost: "1panel-postgresql-hi3r:5432",
			wantDB:   "videodb",
			warned:   true,
		},
		{
			name:     "主机写成 //host/ 但没写端口",
			in:       "postgres://u:p@//pg-host/videodb?sslmode=disable",
			wantHost: "pg-host",
			wantDB:   "videodb",
			warned:   true,
		},
		{
			name:     "正常连接串保持不变",
			in:       "postgres://u:p@pg-host:5432/videodb?sslmode=disable",
			wantHost: "pg-host:5432",
			wantDB:   "videodb",
			warned:   false,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, warnings := NormalizeDSN(tc.in)
			u, err := url.Parse(got)
			if err != nil {
				t.Fatalf("修正后的 DSN 无法解析: %v (%s)", err, got)
			}
			if u.Host != tc.wantHost {
				t.Fatalf("host = %q, want %q (dsn=%s)", u.Host, tc.wantHost, got)
			}
			if dbName := strings.TrimPrefix(u.Path, "/"); dbName != tc.wantDB {
				t.Fatalf("dbname = %q, want %q (dsn=%s)", dbName, tc.wantDB, got)
			}
			if tc.warned && len(warnings) == 0 {
				t.Fatalf("期望产生修正提示，实际没有")
			}
			if !tc.warned && len(warnings) != 0 {
				t.Fatalf("不应产生提示，实际: %v", warnings)
			}
			if err := ValidatePostgresDSN(got); err != nil {
				t.Fatalf("修正后应通过校验，实际: %v", err)
			}
		})
	}
}

func TestNormalizeDSNRepairsEvenWhenURLParseFails(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{
			name: "密码含未转义的百分号（url.Parse 会直接失败）",
			in:   "postgres://x21_admin:p%ss@//1panel-postgresql-hi3r/:5432/videodb?sslmode=disable",
			want: "postgres://x21_admin:p%25ss@1panel-postgresql-hi3r:5432/videodb?sslmode=disable",
		},
		{
			name: "密码里含 @（按最后一个 @ 切分，不切错主机）",
			in:   "postgres://x21_admin:p@ss@//pg-host/:5432/videodb",
			want: "postgres://x21_admin:p%40ss@pg-host:5432/videodb",
		},
		{
			name: "主机正常但端口被斜杠隔开",
			in:   "postgres://u:p@pg-host/:5432/videodb",
			want: "postgres://u:p@pg-host:5432/videodb",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, warnings := NormalizeDSN(tc.in)
			if got != tc.want {
				t.Fatalf("NormalizeDSN = %q, want %q", got, tc.want)
			}
			if len(warnings) == 0 {
				t.Fatalf("修正后应产生提示")
			}
			if err := ValidatePostgresDSN(got); err != nil {
				t.Fatalf("修正后应通过校验，实际: %v", err)
			}
		})
	}
}

func TestValidatePostgresDSNRejectsBadInput(t *testing.T) {
	bad := []string{
		"",
		"postgres://u:p@/videodb",                                        // 缺主机
		"postgres://u:p@pg-host:5432/",                                   // 缺库名
		"postgres://u:p@pg-host:5432/1panel-postgresql-hi3r/:5432/videodb", // 库名带斜杠冒号
		"postgres://u:p@pg-host:5432/bad name",                           // 库名含空格
	}
	for _, dsn := range bad {
		if err := ValidatePostgresDSN(dsn); err == nil {
			t.Fatalf("应校验失败: %s", dsn)
		} else if !strings.Contains(err.Error(), "postgres://") {
			t.Fatalf("错误信息应带正确格式示例，实际: %v", err)
		}
	}

	good := "postgres://x21_admin:pw@1panel-postgresql-hi3r:5432/videodb?sslmode=disable"
	if err := ValidatePostgresDSN(good); err != nil {
		t.Fatalf("合法连接串不应报错: %v", err)
	}
	// key=value 形式
	if err := ValidatePostgresDSN("host=pg-host port=5432 user=u password=p dbname=videodb sslmode=disable"); err != nil {
		t.Fatalf("key=value 形式不应报错: %v", err)
	}
}
