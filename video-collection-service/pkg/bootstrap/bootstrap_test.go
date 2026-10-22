package bootstrap

import (
	"path/filepath"
	"testing"
)

func TestOpenSaveLoadMasked(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nested", "collection.db")
	st, err := Open(path)
	if err != nil {
		t.Fatalf("Open failed: %v", err)
	}
	defer st.Close()

	if st.Path() != path {
		t.Errorf("Path() = %q, want %q", st.Path(), path)
	}

	entries := map[string]string{
		KeyDBDriver:      "postgres",
		KeyDBHost:        "postgres",
		KeyDBPort:        "5432",
		KeyDBUser:        "video",
		KeyDBPassword:    "s3cret",
		KeyDBName:        "videodb",
		KeyDBSSLMode:     "disable",
		KeyRedisAddr:     "redis:6379",
		KeyRedisDB:       "0",
		KeyRedisPrefix:   "vc",
		KeyAdminUsername: "root",
		KeyAdminPassword: "p@ss",
	}
	if err := st.Save(entries); err != nil {
		t.Fatalf("Save failed: %v", err)
	}

	cfg, err := Load(st)
	if err != nil {
		t.Fatalf("Load failed: %v", err)
	}
	if cfg.Driver != "postgres" || cfg.Host != "postgres" || cfg.Port != "5432" {
		t.Errorf("db config mismatch: %+v", cfg)
	}
	if cfg.RedisAddr != "redis:6379" || cfg.RedisDB != "0" || cfg.RedisPrefix != "vc" {
		t.Errorf("redis config mismatch: %+v", cfg)
	}
	if cfg.AdminUsername != "root" || !cfg.HasDatabase() {
		t.Errorf("admin/HasDatabase mismatch: %+v", cfg)
	}

	// 覆盖写（upsert）
	if err := st.Save(map[string]string{KeyDBDriver: "sqlite"}); err != nil {
		t.Fatalf("Save upsert failed: %v", err)
	}
	if v, _ := st.Get(KeyDBDriver); v != "sqlite" {
		t.Errorf("after upsert db.driver = %q", v)
	}
	// 其他键不受影响
	if v, _ := st.Get(KeyDBPassword); v != "s3cret" {
		t.Errorf("db.password changed unexpectedly: %q", v)
	}

	masked, err := st.MaskedAll()
	if err != nil {
		t.Fatalf("MaskedAll failed: %v", err)
	}
	if masked[KeyDBPassword] != Masked || masked[KeyAdminPassword] != Masked {
		t.Errorf("sensitive keys not masked: %v", masked)
	}
	if masked[KeyDBHost] != "postgres" {
		t.Errorf("non-sensitive key should stay plain: %v", masked)
	}
}

func TestConfigFromEmpty(t *testing.T) {
	cfg := ConfigFrom(map[string]string{})
	if cfg.HasDatabase() {
		t.Error("empty config should not report database configured")
	}
	if cfg.Driver != "" || cfg.RedisAddr != "" {
		t.Errorf("unexpected values: %+v", cfg)
	}
}

func TestGenerateRandomPassword(t *testing.T) {
	a, err := GenerateRandomPassword()
	if err != nil {
		t.Fatalf("GenerateRandomPassword failed: %v", err)
	}
	b, _ := GenerateRandomPassword()
	if len(a) != 24 || a == b {
		t.Errorf("random password not unique or wrong length: %q / %q", a, b)
	}
}
