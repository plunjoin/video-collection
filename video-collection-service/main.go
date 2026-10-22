package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"video-collection-service/config"
	"video-collection-service/pkg/api"
	"video-collection-service/pkg/auth"
	"video-collection-service/pkg/bootstrap"
	"video-collection-service/pkg/cache"
	"video-collection-service/pkg/openapi"
	"video-collection-service/pkg/player"
	"video-collection-service/pkg/rss"
	"video-collection-service/pkg/scheduler"
	"video-collection-service/pkg/store"
	"video-collection-service/pkg/theme"
	videoAdmin "video-collection-service/web/admin"
)

func main() {
	fmt.Println("==================================================================")
	fmt.Println("   Bllii 可配置采集聚合平台 - 统一服务 (Go: RESTful API + 管理后台) ")
	fmt.Printf("   构建标识: %s\n", config.BuildInfo())
	fmt.Println("==================================================================")

	// 1. 加载 .env 与主配置文件（优先级：环境变量 > .env > YAML > 默认值）
	workDir, _ := os.Getwd()
	envFile := os.Getenv("ENV_FILE")
	if envFile == "" {
		envFile = ".env"
	}
	isEnvLoaded, err := config.LoadDotEnv(envFile)
	switch {
	case err != nil:
		log.Printf("[WARN] 读取 %s 失败: %v", envFile, err)
	case isEnvLoaded:
		fmt.Printf("[OK] 已加载环境配置文件: %s (工作目录: %s)\n", envFile, workDir)
	default:
		fmt.Printf("[*] 未找到环境配置文件 %s (工作目录: %s)，仅使用系统/容器环境变量\n", envFile, workDir)
	}
	configPath := os.Getenv("CONFIG_PATH")
	if configPath == "" {
		configPath = "config/collector_rules.yaml"
	}
	cfg, err := config.LoadConfig(configPath)
	if err != nil {
		log.Printf("[WARN] 读取 %s 失败，使用系统内置默认配置: %v", configPath, err)
		cfg = &config.AppConfig{
			Database: config.DatabaseConfig{
				Driver: "postgres",
				DSN:    "postgres://postgres:postgres@localhost:5432/videodb?sslmode=disable",
			},
		}
	}
	dsnSource := config.ApplyEnvOverrides(cfg)
	fmt.Printf("[*] 数据库配置来源: %s\n", dsnSource)

	// 1.5 打开 bootstrap 基础配置（SQLite）：数据库/Redis/初始管理员等启动引导信息
	// 注意：SQLite 不再是 PostgreSQL 故障时的数据兜底库，而是基础配置的存储位置。
	sqlitePath := resolveSQLitePath(cfg)
	bsStore, bsErr := bootstrap.Open(sqlitePath)
	if bsErr != nil {
		log.Printf("[WARN] 打开基础配置 SQLite (%s) 失败，仅使用环境变量/YAML 配置: %v", sqlitePath, bsErr)
	}
	var bsCfg *bootstrap.Config
	if bsStore != nil {
		defer bsStore.Close()
		loaded, err := bootstrap.Load(bsStore)
		if err != nil {
			log.Printf("[WARN] 读取基础配置失败: %v", err)
		} else {
			bsCfg = loaded
		}
	}

	// 历史降级数据一次性迁移：无任何数据库配置但本地 SQLite 已有业务数据时，
	// 显式切换为 SQLite 单文件模式并记录到基础配置。
	maybeMigrateLegacySQLite(cfg, bsStore, bsCfg, sqlitePath)

	// 从未配置数据库时开箱使用 SQLite 单文件模式；显式配置过 PostgreSQL 则连接失败即退出
	maybeDefaultToSQLite(cfg, bsCfg)

	// 环境变量 > bootstrap SQLite > YAML
	dbSource := applyBootstrapDatabase(cfg, bsCfg)
	if dbSource != "环境变量 / YAML 配置" {
		fmt.Printf("[*] 数据库配置来源: %s\n", dbSource)
	}
	// 初始管理员账号密码 / Webhook 加密主密钥由 bootstrap 注入环境变量读取点
	applyBootstrapRuntime(bsStore, bsCfg)

	if cfg.Database.Driver != "postgres" && cfg.Database.Driver != "sqlite" {
		log.Fatalf("[FATAL] 不支持的数据库驱动: %s", cfg.Database.Driver)
	}

	// 1.9 连接串规范化与校验：所有配置来源合并完成后统一处理
	// 典型错误：主机写成 "//1panel-postgresql-hi3r/"，解析后 host 为空，
	// lib/pq 会连到本机 :5432，甚至拿垃圾库名去 CREATE DATABASE。
	if strings.EqualFold(cfg.Database.Driver, "postgres") {
		rawDSN := cfg.Database.DSN
		normalized, warnings := config.NormalizeDSN(rawDSN)
		for _, w := range warnings {
			fmt.Printf("[WARN] %s\n", w)
		}
		cfg.Database.DSN = normalized
		// 修正前后不一致时把两行都打出来，避免只看一行分不清到底生效的是哪个
		if strings.TrimSpace(rawDSN) != strings.TrimSpace(normalized) {
			fmt.Printf("[*] 连接串原始值: %s\n", config.MaskDSN(strings.TrimSpace(rawDSN)))
			fmt.Printf("[*] 连接串已修正: %s\n", config.MaskDSN(normalized))
		}
		if err := config.ValidatePostgresDSN(cfg.Database.DSN); err != nil {
			log.Fatalf(`[FATAL] PostgreSQL 连接串无效: %v

  当前配置来源：%s
  修正后请重启服务。也可以：
  1) 管理后台「基础配置」页面修改并保存（持久化在 %s 的 bootstrap_config 表）
  2) 修改环境变量 DB_DSN，或改用 DB_HOST/DB_PORT/DB_USER/DB_PASSWORD/DB_NAME 分项配置`,
				err, dsnSource, sqlitePath)
		}
	}

	// 2. 初始化持久化存储（SQLite 仅作为显式配置的单文件模式，不再作为 PostgreSQL 的兜底）
	var dbStore store.Store
	switch strings.ToLower(cfg.Database.Driver) {
	case "postgres":
		fmt.Printf("[*] 正在连接 PostgreSQL 数据库: %s\n", config.MaskDSN(cfg.Database.DSN))
		fmt.Printf("[*] 连接目标: %s\n", config.DescribePostgresTarget(cfg.Database.DSN))
		pgStore, pgErr := store.NewPostgresStore(cfg.Database.DSN)
		if pgErr != nil {
			log.Fatalf(`[FATAL] PostgreSQL 连接失败（系统不再自动降级到 SQLite 兜底）: %v

  常见原因排查：
  1) 连接串格式：应为 postgres://用户:密码@主机:端口/库名?sslmode=disable
     容器部署时主机请填服务名/容器名（如 1panel-postgresql-hi3r），不要用 127.0.0.1 或带斜杠的写法
  2) 主机/端口不可达：在容器内执行 nc -zv <主机> 5432 确认连通性
  3) 账号密码错误，或该数据库不存在
  4) PostgreSQL 15+ 默认不再给 public schema 建表权限，用超级管理员执行：
       GRANT ALL ON SCHEMA public TO <用户>;
     或把库的 owner 改为该用户：ALTER DATABASE <库名> OWNER TO <用户>;

  修正配置后重启即可：
  1) 管理后台「基础配置」页面 / API： GET|PUT /api/admin/bootstrap
     （配置持久化在 %s 的 bootstrap_config 表中）
  2) 环境变量：DB_DSN 或 DB_HOST/DB_PORT/DB_USER/DB_PASSWORD/DB_NAME
  3) 若确需 SQLite 单文件模式，将 db.driver 显式设为 sqlite`, pgErr, sqlitePath)
		}
		dbStore = pgStore
		fmt.Printf("[OK] PostgreSQL 数据库连接成功（%s）！已开启原生 JSONB 与高并发支持。\n",
			config.DescribePostgresTarget(cfg.Database.DSN))
	case "sqlite":
		sqStore, sqErr := store.NewSQLiteStore(sqlitePath)
		if sqErr != nil {
			log.Fatalf("[FATAL] 初始化 SQLite 单文件模式失败: %v", sqErr)
		}
		dbStore = sqStore
		fmt.Printf("[OK] 已启动 SQLite 单文件模式: %s（基础配置与业务数据同库）\n", sqlitePath)
	default:
		log.Fatalf("[FATAL] 不支持的数据库驱动: %s", cfg.Database.Driver)
	}

	// 3. 初始采集源同步
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	sources, _ := dbStore.GetSources(ctx)
	if len(sources) == 0 && len(cfg.Sources) > 0 {
		fmt.Println("[+] 数据库暂无采集点，正在导入默认采集源...")
		for _, src := range cfg.Sources {
			_ = dbStore.SaveSource(ctx, src)
			fmt.Printf("    -> 导入采集源: [%s] (%s)\n", src.Name, src.API)
		}
	}
	cancel()

	// 4. 初始化主题管理器、播放器管理器与采集调度器
	themeManager := theme.NewManager(dbStore, "themes")
	playerManager := player.NewManager(dbStore, "players")
	sc := scheduler.NewScheduler(dbStore)

	// 5. 接入 radix (Redis)：启用分布式会话与公开读接口缓存
	// 配置来源：环境变量 > bootstrap 基础配置（管理后台「基础配置」可维护）
	// 未配置或连接失败时降级为内存会话 + 无缓存，不影响主流程
	redisCfg := cache.ConfigFromEnv()
	if redisCfg.Addr == "" {
		addr, password, db, prefix := bsRedisValues(bsCfg)
		redisCfg = cache.ConfigFromValues(addr, password, db, prefix)
	}
	var cacheClient *cache.Client
	if c, cacheErr := cache.Connect(context.Background(), redisCfg); cacheErr != nil {
		log.Printf("[WARN] Redis 未接入，会话与缓存降级为本地模式: %v", cacheErr)
	} else if c != nil {
		cacheClient = c
		fmt.Println("[OK] Redis (radix) 连接成功，已启用分布式会话与接口缓存")
		auth.DefaultSessionManager.SetStore(auth.NewRedisSessionStore(cacheClient))
	}

	// 6. 构建 HTTP 路由中心
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()
		if _, err := dbStore.GetSetting(ctx, "health_check", ""); err != nil {
			http.Error(w, "database unavailable", http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte("{\"status\":\"ok\"}"))
	})

	// (A) OpenAPI 3.0 & Swagger UI / Redoc 交互式接口文档中心
	openapi.RegisterRoutes(mux)

	// (B) 网页 RSS 2.0 聚合订阅服务 (支持 /rss.xml, /rss, /feed.xml, /feed, /api/rss)
	rssHandler := rss.NewHandler(dbStore)
	mux.Handle("/rss.xml", rssHandler)
	mux.Handle("/rss", rssHandler)
	mux.Handle("/feed.xml", rssHandler)
	mux.Handle("/feed", rssHandler)
	mux.Handle("/api/rss", rssHandler)

	// (C) 系统 RESTful API 服务 (包含数据采集、检索、用户、管理等纯 JSON 接口)
	apiServer := api.NewServer(dbStore, sc, themeManager, playerManager, bsStore)
	if cacheClient != nil {
		apiServer.UseCache(cacheClient, 0)
	}
	apiServer.RegisterRoutes(mux)

	// (D) 管理后台 SPA (Go 直接托管，构建产物经 go:embed 随二进制分发)
	// 注意：需在根路径兜底之前注册，/admin/* 由 SPA history 路由处理
	adminHandler := videoAdmin.Handler()
	mux.Handle("/admin", adminHandler)
	mux.Handle("/admin/", adminHandler)

	// (E) 根路径直接跳转管理后台（服务即后台：默认端口 80 的根目录即登录页）
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/" || r.URL.Path == "" {
			// 不论浏览器还是程序访问，统一跳转到管理后台
			http.Redirect(w, r, "/admin", http.StatusFound)
			return
		}

		// 严防 API 路径意外穿透，统一输出规范 JSON 404
		if strings.HasPrefix(r.URL.Path, "/api/") || strings.HasPrefix(r.URL.Path, "/api.php") {
			w.Header().Set("Content-Type", "application/json; charset=utf-8")
			w.WriteHeader(http.StatusNotFound)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"code":  0,
				"error": "API route not found: " + r.URL.Path,
			})
			return
		}

		// 其他未注册路径均统一以规范 JSON 404 响应
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.WriteHeader(http.StatusNotFound)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"code":     0,
			"error":    "Not Found: " + r.URL.Path,
			"docs_url": "/docs",
		})
	})

	// (F) 服务状态索引（供程序 / 运维访问；浏览器访问根路径会直接落到 /admin）
	mux.HandleFunc("/status", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"name":        "Video Collection Service (API + Admin)",
			"version":     "2.0.0",
			"build":       config.BuildInfo(),
			"status":      "running",
			"admin_url":   "/admin",
			"docs_url":    "/docs",
			"openapi_url": "/openapi.json",
			"redoc_url":   "/redoc",
			"cache":       cacheStatus(cacheClient),
			"database": map[string]any{
				"driver":         cfg.Database.Driver,
				"target":         config.DescribePostgresTarget(cfg.Database.DSN),
				"bootstrap_path": sqlitePath,
			},
			"apis": map[string]string{
				"videos":     "/api/videos",
				"categories": "/api/categories",
				"rankings":   "/api/rankings",
				"latest":     "/api/latest",
				"rss":        "/rss.xml",
			},
		})
	})

	// 6. 启动服务监听
	port := os.Getenv("PORT")
	if port == "" {
		port = "80"
	}
	addr := ":" + port

	fmt.Println("\n------------------------------------------------------------------")
	fmt.Printf("  >> 根路径即后台 (默认端口 %s):    http://localhost:%s/   ->   /admin\n", port, port)
	fmt.Printf("  >> 管理后台 (Go 托管 SPA):        http://localhost:%s/admin\n", port)
	fmt.Printf("  >> OpenAPI 交互文档 (Swagger UI): http://localhost:%s/docs\n", port)
	fmt.Printf("  >> 服务状态 (程序访问):           http://localhost:%s/status\n", port)
	fmt.Printf("  >> OpenAPI 规范 JSON:             http://localhost:%s/openapi.json\n", port)
	fmt.Printf("  >> Redoc 静态文档视角:            http://localhost:%s/redoc\n", port)
	fmt.Printf("  >> 视频检索 RESTful API:          http://localhost:%s/api/videos\n", port)
	fmt.Printf("  >> 网页 RSS 2.0 聚合订阅:         http://localhost:%s/rss.xml\n", port)
	fmt.Println("------------------------------------------------------------------")
	fmt.Println("[*] 统一服务（API + 管理后台）启动就绪，正在监听请求...")

	server := &http.Server{
		Addr:         addr,
		Handler:      mux,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
	}

	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("[FATAL] 服务运行异常: %v", err)
	}
}

// cacheStatus 返回 /status 中的缓存层状态描述。
func cacheStatus(c *cache.Client) map[string]any {
	if c == nil || !c.Enabled() {
		return map[string]any{"redis": false, "mode": "memory"}
	}
	return map[string]any{"redis": true, "mode": "radix"}
}
