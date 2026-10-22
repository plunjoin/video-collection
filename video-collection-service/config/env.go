package config

import (
	"bufio"
	"fmt"
	"net/url"
	"os"
	"regexp"
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

// ---------- 连接串规范化与校验 ----------
//
// 线上最常见的两类连接串错误：
//  1) 主机被写成 "//1panel-postgresql-hi3r/"（多出斜杠），拼出的 DSN 形如
//     postgres://user:pw@//host/:5432/db —— url 解析后 host 为空、库名变成 "/host/:5432/db"，
//     lib/pq 会连到 ":5432"（即本机），甚至用这个垃圾库名去 CREATE DATABASE。
//  2) 干脆没写主机，或库名里带了斜杠/冒号。
// 这里先做保守修复，修不好就带着明确提示拒绝启动。

var (
	pgSchemeRe = regexp.MustCompile(`^(?i)postgres(ql)?://`)
	pgIdentRe  = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_$-]*$`)
)

// PostgresDSNTemplate 正确的连接串格式说明
const PostgresDSNTemplate = "postgres://用户名:密码@主机:端口/库名?sslmode=disable（示例：postgres://x21_admin:PASS@1panel-postgresql-hi3r:5432/videodb?sslmode=disable）"

// NormalizeDSN 修正常见的连接串写法错误，返回修正后的 DSN 与需要提示给用户的说明
func NormalizeDSN(dsn string) (string, []string) {
	trimmed := strings.TrimSpace(dsn)
	if trimmed == "" || !pgSchemeRe.MatchString(trimmed) {
		// key=value 形式或空串：不做改写
		return trimmed, nil
	}
	u, err := url.Parse(trimmed)
	if err != nil {
		return trimmed, nil
	}

	var warnings []string

	// 情形一：host 为空但路径里塞了 "//host/:port/db"
	if strings.TrimSpace(u.Host) == "" && strings.HasPrefix(u.Path, "//") {
		host, port, db, ok := parseAuthorityLikePath(u.Path)
		if ok {
			u.Host = host
			if port != "" {
				u.Host = host + ":" + port
			}
			u.Path = "/" + db
			warnings = append(warnings, fmt.Sprintf("连接串缺少主机名（写成了 %q），已自动修正为 %s",
				strings.TrimSpace(dsn), MaskDSN(u.String())))
		}
	}

	// 情形二：host 里混进了斜杠，例如 "//host/" 或 "host/:5432"
	if h := u.Host; strings.Contains(h, "/") {
		cleaned := strings.Trim(h, "/")
		// "host/:5432" -> host + port
		if before, after, found := strings.Cut(cleaned, "/:"); found {
			u.Host = before + ":" + after
		} else {
			u.Host = strings.ReplaceAll(cleaned, "/", "")
		}
		warnings = append(warnings, fmt.Sprintf("连接串主机名含多余斜杠，已修正为 %q", u.Host))
	}

	// 情形三：端口写在了路径里（host 正常，但 path 形如 "/:5432/db"）
	if strings.HasPrefix(u.Path, "/:") {
		portPart, rest, _ := strings.Cut(strings.TrimPrefix(u.Path, "/:"), "/")
		if portPart != "" {
			u.Host = u.Hostname() + ":" + portPart
			u.Path = "/" + rest
			warnings = append(warnings, fmt.Sprintf("连接串端口写在路径里，已修正为 %q", u.Host))
		}
	}

	return u.String(), warnings
}

// parseAuthorityLikePath 解析 "//host/:port/db"、"//host/db"、"//host:port/db" 三种写法
func parseAuthorityLikePath(path string) (host, port, db string, ok bool) {
	rest := strings.TrimPrefix(path, "//")
	if rest == "" {
		return "", "", "", false
	}
	head, tail, _ := strings.Cut(rest, "/")
	if head == "" {
		return "", "", "", false
	}
	host = head
	// 端口被斜杠隔开："host" + "/:5432/db"
	if strings.HasPrefix(tail, ":") {
		portPart, dbPart, _ := strings.Cut(strings.TrimPrefix(tail, ":"), "/")
		port, db = portPart, dbPart
	} else {
		db = tail
	}
	// "host:5432/db" 这种 head 自带端口的情况
	if h, p, found := strings.Cut(host, ":"); found {
		host, port = h, p
	}
	if db == "" {
		return "", "", "", false
	}
	return host, port, db, true
}

// ValidatePostgresDSN 校验 PostgreSQL 连接串；错误信息里带上正确格式，避免只看到一句 "连接失败"
func ValidatePostgresDSN(dsn string) error {
	trimmed := strings.TrimSpace(dsn)
	if trimmed == "" {
		return fmt.Errorf("连接串为空，正确格式：%s", PostgresDSNTemplate)
	}
	if !pgSchemeRe.MatchString(trimmed) {
		// key=value 形式（host=... dbname=...）
		if !regexp.MustCompile(`(^|\s)host=`).MatchString(trimmed) {
			return fmt.Errorf("连接串缺少 host，正确格式：%s", PostgresDSNTemplate)
		}
		return nil
	}

	u, err := url.Parse(trimmed)
	if err != nil {
		return fmt.Errorf("连接串无法解析（%v），正确格式：%s", err, PostgresDSNTemplate)
	}
	if u.User == nil || u.User.Username() == "" {
		return fmt.Errorf("连接串缺少用户名，正确格式：%s", PostgresDSNTemplate)
	}
	if strings.TrimSpace(u.Host) == "" {
		return fmt.Errorf("连接串缺少主机名（@ 后面为空），正确格式：%s", PostgresDSNTemplate)
	}
	if strings.Contains(u.Host, "/") {
		return fmt.Errorf("连接串主机名含斜杠：%q，正确格式：%s", u.Host, PostgresDSNTemplate)
	}
	dbName := strings.TrimPrefix(u.Path, "/")
	if dbName == "" {
		return fmt.Errorf("连接串缺少数据库名，正确格式：%s", PostgresDSNTemplate)
	}
	if strings.ContainsAny(dbName, "/:") {
		return fmt.Errorf("数据库名不合法：%q（不应包含 / 或 :），正确格式：%s", dbName, PostgresDSNTemplate)
	}
	if !pgIdentRe.MatchString(dbName) {
		return fmt.Errorf("数据库名不合法：%q（只允许字母、数字、下划线与连字符，且不能以数字开头），正确格式：%s", dbName, PostgresDSNTemplate)
	}
	return nil
}

// DescribePostgresTarget 返回 "主机:端口/库名"，用于启动日志确认连的是哪个库
func DescribePostgresTarget(dsn string) string {
	u, err := url.Parse(strings.TrimSpace(dsn))
	if err != nil {
		return ""
	}
	dbName := strings.TrimPrefix(u.Path, "/")
	if u.Host == "" && dbName == "" {
		return ""
	}
	return u.Host + "/" + dbName
}
