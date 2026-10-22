// Package bootstrap 提供「基础配置」存储。
//
// 定位：SQLite 不再作为 PostgreSQL 故障时的数据兜底库，而是整个系统的
// 基础配置信息存储——数据库连接、Redis 连接、初始管理员账号密码、
// Webhook 加密主密钥等启动引导信息都持久化在本地 SQLite 文件中
// （默认 data/collection.db），可在管理后台「基础配置」页面修改。
//
// 优先级：环境变量/容器注入 > bootstrap SQLite > YAML 配置文件 > 内置默认值。
package bootstrap

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	_ "modernc.org/sqlite"
)

// bootstrap_config 表中的键名
const (
	// 数据库（PostgreSQL）
	KeyDBDriver   = "db.driver"
	KeyDBDSN      = "db.dsn"
	KeyDBHost     = "db.host"
	KeyDBPort     = "db.port"
	KeyDBUser     = "db.user"
	KeyDBPassword = "db.password"
	KeyDBName     = "db.name"
	KeyDBSSLMode  = "db.sslmode"

	// Redis（radix）
	KeyRedisAddr     = "redis.addr"
	KeyRedisPassword = "redis.password"
	KeyRedisDB       = "redis.db"
	KeyRedisPrefix   = "redis.prefix"

	// 初始管理员（仅在数据库无用户时首次初始化生效）
	KeyAdminUsername = "admin.username"
	KeyAdminPassword = "admin.password"

	// Webhook 密钥信封加密主密钥
	KeyWebhookEncryptionKey = "webhook.encryption_key"
)

// SensitiveKeys 命中后 API 返回时做掩码处理
var SensitiveKeys = map[string]bool{
	KeyDBPassword:           true,
	KeyAdminPassword:        true,
	KeyWebhookEncryptionKey: true,
	KeyDBDSN:                true, // 连接串内含密码，按串整体掩码
}

// Masked 掩码占位符
const Masked = "********"

// Store 基础配置存储（SQLite 键值表）
type Store struct {
	db   *sql.DB
	path string
	mu   sync.Mutex
}

// Open 打开（不存在则创建）基础配置 SQLite 文件
func Open(path string) (*Store, error) {
	if path == "" {
		path = DefaultPath
	}
	dir := filepath.Dir(path)
	if dir != "" && dir != "." {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return nil, fmt.Errorf("create bootstrap dir failed: %w", err)
		}
	}
	db, err := sql.Open("sqlite", path+"?_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)")
	if err != nil {
		return nil, fmt.Errorf("open bootstrap sqlite failed: %w", err)
	}
	db.SetMaxOpenConns(1)

	st := &Store{db: db, path: path}
	if err := st.initSchema(); err != nil {
		_ = db.Close()
		return nil, err
	}
	return st, nil
}

// DefaultPath 基础配置 SQLite 默认路径
const DefaultPath = "data/collection.db"

func (s *Store) initSchema() error {
	_, err := s.db.Exec(`
	CREATE TABLE IF NOT EXISTS bootstrap_config (
		key        TEXT PRIMARY KEY,
		val        TEXT NOT NULL DEFAULT '',
		updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
	);`)
	if err != nil {
		return fmt.Errorf("init bootstrap_config schema failed: %w", err)
	}
	return nil
}

// Path 返回基础配置文件路径
func (s *Store) Path() string { return s.path }

// Close 关闭底层连接
func (s *Store) Close() error { return s.db.Close() }

// All 返回全部原始配置（未掩码）
func (s *Store) All() (map[string]string, error) {
	rows, err := s.db.Query(`SELECT key, val FROM bootstrap_config`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make(map[string]string)
	for rows.Next() {
		var k, v string
		if err := rows.Scan(&k, &v); err != nil {
			return nil, err
		}
		out[k] = v
	}
	return out, rows.Err()
}

// MaskedAll 返回掩码后的配置（敏感值以 ******** 占位，空值保持为空）
func (s *Store) MaskedAll() (map[string]string, error) {
	raw, err := s.All()
	if err != nil {
		return nil, err
	}
	for k, v := range raw {
		if SensitiveKeys[k] && strings.TrimSpace(v) != "" {
			raw[k] = Masked
		}
	}
	return raw, nil
}

// Get 读取单个键
func (s *Store) Get(key string) (string, error) {
	var v string
	err := s.db.QueryRow(`SELECT val FROM bootstrap_config WHERE key = ?`, key).Scan(&v)
	if err == sql.ErrNoRows {
		return "", nil
	}
	return v, err
}

// Set 写入单个键
func (s *Store) Set(key, val string) error {
	return s.Save(map[string]string{key: val})
}

// Save 批量写入（upsert）；空字符串表示清除该项
func (s *Store) Save(entries map[string]string) error {
	if len(entries) == 0 {
		return nil
	}
	s.mu.Lock()
	defer s.mu.Unlock()

	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	stmt, err := tx.Prepare(`
		INSERT INTO bootstrap_config (key, val, updated_at)
		VALUES (?, ?, CURRENT_TIMESTAMP)
		ON CONFLICT(key) DO UPDATE SET val = excluded.val, updated_at = CURRENT_TIMESTAMP`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for k, v := range entries {
		if _, err := stmt.Exec(k, strings.TrimSpace(v)); err != nil {
			return fmt.Errorf("save bootstrap key %s failed: %w", k, err)
		}
	}
	return tx.Commit()
}

// GenerateRandomPassword 生成随机密码（用于初始管理员未配置时的一次性生成并回写）
func GenerateRandomPassword() (string, error) {
	b := make([]byte, 12)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
