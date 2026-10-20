package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/url"
	"os"
	"strings"

	_ "modernc.org/sqlite"
	"video-collection-service/config"
	"video-collection-service/pkg/bootstrap"
)

// resolveSQLitePath 解析基础配置/单文件模式 SQLite 路径
// 优先级：环境变量 SQLITE_PATH > YAML sqlite_path > 默认 data/collection.db
func resolveSQLitePath(cfg *config.AppConfig) string {
	if path := strings.TrimSpace(os.Getenv("SQLITE_PATH")); path != "" {
		return path
	}
	if cfg != nil && strings.TrimSpace(cfg.Database.SQLitePath) != "" {
		return cfg.Database.SQLitePath
	}
	return bootstrap.DefaultPath
}

// applyBootstrapDatabase 用 bootstrap SQLite 中的基础配置覆盖数据库设置。
// 优先级：环境变量 > bootstrap SQLite > YAML 配置。返回最终配置来源描述。
func applyBootstrapDatabase(cfg *config.AppConfig, bs *bootstrap.Config) string {
	db := &cfg.Database

	// 1) driver：环境变量 DB_DRIVER 已由 ApplyEnvOverrides 生效，仅在其未设置时采用 bootstrap 值
	if os.Getenv("DB_DRIVER") == "" && bs != nil && strings.TrimSpace(bs.Driver) != "" {
		db.Driver = strings.ToLower(strings.TrimSpace(bs.Driver))
	}

	// 2) DSN：环境变量提供了完整连接串或分项配置时，环境变量优先，bootstrap 不介入
	envProvidesDSN := os.Getenv("DB_DSN") != "" || os.Getenv("DATABASE_URL") != "" || os.Getenv("DB_HOST") != ""
	if !envProvidesDSN && bs != nil {
		if strings.TrimSpace(bs.DSN) != "" {
			db.DSN = strings.TrimSpace(bs.DSN)
			return "bootstrap SQLite (db.dsn)"
		}
		if strings.TrimSpace(bs.Host) != "" {
			db.DSN = buildDSNFromBootstrap(bs)
			return "bootstrap SQLite (db.host 等分项配置)"
		}
	}
	return "环境变量 / YAML 配置"
}

// buildDSNFromBootstrap 由 bootstrap 分项配置拼装 PostgreSQL 连接串
func buildDSNFromBootstrap(bs *bootstrap.Config) string {
	user := firstNonEmpty(bs.User, "postgres")
	name := firstNonEmpty(bs.Name, "videodb")
	port := firstNonEmpty(bs.Port, "5432")
	sslmode := firstNonEmpty(bs.SSLMode, "disable")

	dsn := url.URL{
		Scheme:   "postgres",
		User:     url.UserPassword(user, bs.Password),
		Host:     bs.Host + ":" + port,
		Path:     "/" + name,
		RawQuery: "sslmode=" + sslmode,
	}
	return dsn.String()
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return strings.TrimSpace(v)
		}
	}
	return ""
}

// defaultSampleDSN 与 LoadConfig / collector_rules.yaml 中的内置示例连接串一致。
// 连接串仍为该示例值且无任何显式配置时，视为「从未配置数据库」。
const defaultSampleDSN = "postgres://postgres:postgres@localhost:5432/videodb?sslmode=disable"

// envConfiguresDatabase 环境变量是否显式配置了数据库
func envConfiguresDatabase() bool {
	return os.Getenv("DB_DRIVER") != "" || os.Getenv("DB_DSN") != "" ||
		os.Getenv("DATABASE_URL") != "" || os.Getenv("DB_HOST") != ""
}

// maybeDefaultToSQLite 从未配置数据库（驱动为 postgres 但连接串仍是内置示例值，
// 且环境变量与 bootstrap 基础配置均无数据库配置）时，启动 SQLite 单文件模式，
// 保证开箱可用；一旦显式配置过 PostgreSQL，连接失败将直接报错退出，不再兜底。
// 返回是否切换为 SQLite。
func maybeDefaultToSQLite(cfg *config.AppConfig, bsCfg *bootstrap.Config) bool {
	if strings.ToLower(cfg.Database.Driver) != "postgres" {
		return false
	}
	if envConfiguresDatabase() || (bsCfg != nil && bsCfg.HasDatabase()) {
		return false
	}
	if cfg.Database.DSN != defaultSampleDSN {
		return false
	}
	cfg.Database.Driver = "sqlite"
	log.Println("[*] 未检测到任何数据库配置（当前仍为内置示例连接串），以 SQLite 单文件模式启动。")
	log.Println("    生产环境请在管理后台「基础配置」或环境变量中配置 PostgreSQL。")
	return true
}

// maybeMigrateLegacySQLite 一次性迁移：历史上 PostgreSQL 故障会静默降级到
// SQLite 兜底库。本次启动若发现既无环境变量、bootstrap 中也无任何数据库配置，
// 且本地 SQLite 文件中已有业务数据，则显式切换为 SQLite 单文件模式，
// 并把该决定写入 bootstrap 基础配置（不再是无记录的兜底行为）。
// 返回是否发生了迁移。
func maybeMigrateLegacySQLite(cfg *config.AppConfig, bs *bootstrap.Store, bsCfg *bootstrap.Config, sqlitePath string) bool {
	if bs == nil {
		return false
	}
	if bsCfg != nil && bsCfg.HasDatabase() {
		return false // bootstrap 已配置数据库，无需迁移
	}
	if os.Getenv("DB_DRIVER") != "" || os.Getenv("DB_DSN") != "" ||
		os.Getenv("DATABASE_URL") != "" || os.Getenv("DB_HOST") != "" {
		return false // 环境变量显式指定，尊重环境变量
	}
	if strings.ToLower(cfg.Database.Driver) != "postgres" {
		return false // YAML 已显式指定 sqlite
	}
	if !sqliteHasBusinessData(sqlitePath) {
		return false
	}
	if err := bs.Save(map[string]string{bootstrap.KeyDBDriver: "sqlite"}); err != nil {
		log.Printf("[WARN] 写入 bootstrap 基础配置失败: %v", err)
		return false
	}
	cfg.Database.Driver = "sqlite"
	log.Printf("[*] 检测到本地 SQLite 数据文件 %s 已有业务数据，且未配置 PostgreSQL：", sqlitePath)
	log.Printf("    已将数据库显式切换为 SQLite 单文件模式，并记录到基础配置（db.driver=sqlite）。")
	return true
}

// sqliteHasBusinessData 检测 SQLite 文件中是否存在业务数据（users/videos 表有行）
func sqliteHasBusinessData(path string) bool {
	if _, err := os.Stat(path); err != nil {
		return false
	}
	db, err := sql.Open("sqlite", path+"?_pragma=busy_timeout(2000)")
	if err != nil {
		return false
	}
	defer db.Close()

	for _, table := range []string{"users", "videos"} {
		var count int
		if err := db.QueryRow(fmt.Sprintf("SELECT COUNT(*) FROM %s", table)).Scan(&count); err == nil && count > 0 {
			return true
		}
	}
	return false
}

// bsRedisValues 从 bootstrap 配置取出 Redis 分项值（addr, password, db, prefix）
func bsRedisValues(bs *bootstrap.Config) (string, string, string, string) {
	if bs == nil {
		return "", "", "", ""
	}
	return bs.RedisAddr, bs.RedisPassword, bs.RedisDB, bs.RedisPrefix
}

// applyBootstrapRuntime 将 bootstrap 中的初始管理员账号密码、Webhook 加密主密钥
// 注入进程环境变量（store/webhook 包的读取点仍为环境变量，保证单一事实来源）。
// 管理员初始密码未配置时随机生成并回写 bootstrap，便于首次登录后修改。
func applyBootstrapRuntime(bs *bootstrap.Store, bsCfg *bootstrap.Config) {
	if bs == nil {
		return
	}
	if os.Getenv("ADMIN_INITIAL_PASSWORD") == "" {
		password := ""
		if bsCfg != nil {
			password = strings.TrimSpace(bsCfg.AdminPassword)
		}
		if password == "" {
			generated, err := bootstrap.GenerateRandomPassword()
			if err != nil {
				log.Printf("[WARN] 生成随机管理员密码失败: %v", err)
			} else {
				password = generated
				if err := bs.Save(map[string]string{bootstrap.KeyAdminPassword: password}); err != nil {
					log.Printf("[WARN] 回写管理员初始密码到基础配置失败: %v", err)
				}
				log.Printf("[*] 未配置管理员初始密码，已随机生成并写入基础配置: %s", password)
				log.Printf("    首次登录后请立即在后台「用户账号管理」中修改。")
			}
		}
		if password != "" {
			_ = os.Setenv("ADMIN_INITIAL_PASSWORD", password)
		}
	}
	if os.Getenv("ADMIN_INITIAL_USERNAME") == "" && bsCfg != nil && strings.TrimSpace(bsCfg.AdminUsername) != "" {
		_ = os.Setenv("ADMIN_INITIAL_USERNAME", strings.TrimSpace(bsCfg.AdminUsername))
	}
	if os.Getenv("WEBHOOK_ENCRYPTION_KEY") == "" && bsCfg != nil && strings.TrimSpace(bsCfg.WebhookEncryptionKey) != "" {
		_ = os.Setenv("WEBHOOK_ENCRYPTION_KEY", strings.TrimSpace(bsCfg.WebhookEncryptionKey))
	}
}
