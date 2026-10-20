package bootstrap

import "strings"

// Config 基础配置的结构化视图（全部从 SQLite 读取）
type Config struct {
	// 数据库（PostgreSQL）
	Driver   string
	DSN      string
	Host     string
	Port     string
	User     string
	Password string
	Name     string
	SSLMode  string

	// Redis
	RedisAddr     string
	RedisPassword string
	RedisDB       string
	RedisPrefix   string

	// 初始管理员
	AdminUsername string
	AdminPassword string

	// Webhook 加密主密钥
	WebhookEncryptionKey string
}

// Load 从 store 读取全部基础配置
func Load(s *Store) (*Config, error) {
	raw, err := s.All()
	if err != nil {
		return nil, err
	}
	return ConfigFrom(raw), nil
}

// ConfigFrom 由原始键值映射构造结构化配置
func ConfigFrom(raw map[string]string) *Config {
	return &Config{
		Driver:               raw[KeyDBDriver],
		DSN:                  raw[KeyDBDSN],
		Host:                 raw[KeyDBHost],
		Port:                 raw[KeyDBPort],
		User:                 raw[KeyDBUser],
		Password:             raw[KeyDBPassword],
		Name:                 raw[KeyDBName],
		SSLMode:              raw[KeyDBSSLMode],
		RedisAddr:            raw[KeyRedisAddr],
		RedisPassword:        raw[KeyRedisPassword],
		RedisDB:              raw[KeyRedisDB],
		RedisPrefix:          raw[KeyRedisPrefix],
		AdminUsername:        raw[KeyAdminUsername],
		AdminPassword:        raw[KeyAdminPassword],
		WebhookEncryptionKey: raw[KeyWebhookEncryptionKey],
	}
}

// Entries 将结构化配置还原为键值映射（仅回写非空字段；空字段由调用方决定是否清除）
func (c *Config) Entries() map[string]string {
	return map[string]string{
		KeyDBDriver:             c.Driver,
		KeyDBDSN:                c.DSN,
		KeyDBHost:               c.Host,
		KeyDBPort:               c.Port,
		KeyDBUser:               c.User,
		KeyDBPassword:           c.Password,
		KeyDBName:               c.Name,
		KeyDBSSLMode:            c.SSLMode,
		KeyRedisAddr:            c.RedisAddr,
		KeyRedisPassword:        c.RedisPassword,
		KeyRedisDB:              c.RedisDB,
		KeyRedisPrefix:          c.RedisPrefix,
		KeyAdminUsername:        c.AdminUsername,
		KeyAdminPassword:        c.AdminPassword,
		KeyWebhookEncryptionKey: c.WebhookEncryptionKey,
	}
}

// HasDatabase 是否配置了数据库连接信息（driver 或任一连接参数）
func (c *Config) HasDatabase() bool {
	if c == nil {
		return false
	}
	return strings.TrimSpace(c.Driver) != "" ||
		strings.TrimSpace(c.DSN) != "" ||
		strings.TrimSpace(c.Host) != ""
}
