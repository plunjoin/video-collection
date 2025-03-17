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

	if cfg.Database.Driver != "postgres" && cfg.Database.Driver != "sqlite" {
		log.Fatalf("[FATAL] 不支持的数据库驱动: %s", cfg.Database.Driver)
	}
	// 2. 初始化持久化存储 (优先连接 PostgreSQL，失败则平滑降级至 SQLite 保证系统高可用)
	var dbStore store.Store
	if strings.ToLower(cfg.Database.Driver) == "postgres" {
		fmt.Printf("[*] 正在连接 PostgreSQL 数据库: %s\n", config.MaskDSN(cfg.Database.DSN))
		pgStore, pgErr := store.NewPostgresStore(cfg.Database.DSN)
		if pgErr == nil {
			dbStore = pgStore
			fmt.Println("[OK] PostgreSQL 数据库连接成功！已开启原生 JSONB 与高并发支持。")
		} else {
			if os.Getenv("DB_REQUIRE_PRIMARY") == "true" {
				log.Fatalf("[FATAL] PostgreSQL 不可用，已禁止降级: %v", pgErr)
			}
			log.Printf("[WARN] 连接 PostgreSQL 失败 (%v)，正在平滑降级至本地 SQLite 模式...", pgErr)
		}
	}

	if dbStore == nil {
		sqlitePath := cfg.Database.SQLitePath
		sqStore, sqErr := store.NewSQLiteStore(sqlitePath)
		if sqErr != nil {
			log.Fatalf("[FATAL] 初始化本地 SQLite 数据库也失败: %v", sqErr)
		}
		dbStore = sqStore
		fmt.Printf("[OK] 已启动本地 SQLite 数据库引擎: %s\n", sqlitePath)
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
	// 未配置 REDIS_ADDR 或连接失败时自动降级为内存会话 + 无缓存，不影响主流程
	var cacheClient *cache.Client
	if c, cacheErr := cache.Connect(context.Background(), cache.ConfigFromEnv()); cacheErr != nil {
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
	apiServer := api.NewServer(dbStore, sc, themeManager, playerManager)
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
			"status":      "running",
			"admin_url":   "/admin",
			"docs_url":    "/docs",
			"openapi_url": "/openapi.json",
			"redoc_url":   "/redoc",
			"cache":       cacheStatus(cacheClient),
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
