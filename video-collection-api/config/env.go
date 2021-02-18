package config

import (
	"bufio"
	"fmt"
	"net/url"
	"os"
	"strings"
)

// LoadDotEnv 读取 .env 文件写入进程环境变量；已存在的环境变量不会被覆盖（容器注入的变量优先）
// 返回是否找到并加载了文件，文件不存在时不报错
func LoadDotEnv(path string) (bool, error) {
	file, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return false, nil
		}
		return false, fmt.Errorf("open %s failed: %w", path, err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	isFirstLine := true
	for scanner.Scan() {
		line := scanner.Text()
		if isFirstLine {
			line = strings.TrimPrefix(line, "\uFEFF")
			isFirstLine = false
		}
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		line = strings.TrimPrefix(line, "export ")

		key, value, isFound := strings.Cut(line, "=")
		if !isFound {
			continue
		}
		key = strings.TrimSpace(key)
		value = unquoteEnvValue(strings.TrimSpace(value))

		if _, isSet := os.LookupEnv(key); isSet {
			continue
		}
		os.Setenv(key, value)
	}
	return true, scanner.Err()
}

// ApplyEnvOverrides 使用环境变量覆盖数据库配置
//
// 支持的变量：
//   DB_DRIVER                 postgres / sqlite
//   DB_DSN 或 DATABASE_URL     完整连接串，优先级最高
//   DB_HOST DB_PORT DB_USER DB_PASSWORD DB_NAME DB_SSLMODE  分项配置，未提供 DSN 时拼接
//   SQLITE_PATH               SQLite 数据文件路径
//
// 返回最终 DSN 的来源，用于启动日志排查配置是否生效
func ApplyEnvOverrides(cfg *AppConfig) string {
	db := &cfg.Database

	if driver := os.Getenv("DB_DRIVER"); driver != "" {
		db.Driver = driver
	}
	if path := os.Getenv("SQLITE_PATH"); path != "" {
		db.SQLitePath = path
	}
	if db.SQLitePath == "" {
		db.SQLitePath = "data/collection.db"
	}

	if dsn := os.Getenv("DB_DSN"); dsn != "" {
		db.DSN = dsn
		return "环境变量 DB_DSN"
	}
	if dsn := os.Getenv("DATABASE_URL"); dsn != "" {
		db.DSN = dsn
		return "环境变量 DATABASE_URL"
	}
	if os.Getenv("DB_HOST") != "" {
		db.DSN = buildPostgresDSN()
		return "环境变量 DB_HOST 等分项配置"
	}
	return "YAML 配置文件 / 内置默认值（未检测到 DB_DSN、DATABASE_URL、DB_HOST 环境变量）"
}

// MaskDSN 隐藏连接串中的密码，用于日志输出
func MaskDSN(dsn string) string {
	parsed, err := url.Parse(dsn)
	if err != nil || parsed.User == nil {
		return dsn
	}
	if _, hasPassword := parsed.User.Password(); !hasPassword {
		return dsn
	}
	parsed.User = url.UserPassword(parsed.User.Username(), "******")
	return strings.Replace(parsed.String(), "%2A%2A%2A%2A%2A%2A", "******", 1)
}

func buildPostgresDSN() string {
	dsn := url.URL{
		Scheme: "postgres",
		User:   url.UserPassword(envOrDefault("DB_USER", "postgres"), os.Getenv("DB_PASSWORD")),
		Host:   os.Getenv("DB_HOST") + ":" + envOrDefault("DB_PORT", "5432"),
		Path:   "/" + envOrDefault("DB_NAME", "videodb"),
	}
	query := url.Values{}
	query.Set("sslmode", envOrDefault("DB_SSLMODE", "disable"))
	dsn.RawQuery = query.Encode()
	return dsn.String()
}

func envOrDefault(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func unquoteEnvValue(value string) string {
	if len(value) >= 2 {
		first, last := value[0], value[len(value)-1]
		if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
			return value[1 : len(value)-1]
		}
	}
	if idx := strings.Index(value, " #"); idx >= 0 {
		return strings.TrimSpace(value[:idx])
	}
	return value
}
