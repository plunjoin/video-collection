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

	"video-collection-api/config"
	"video-collection-api/pkg/api"
	"video-collection-api/pkg/openapi"
	"video-collection-api/pkg/player"
	"video-collection-api/pkg/rss"
	"video-collection-api/pkg/scheduler"
	"video-collection-api/pkg/store"
	"video-collection-api/pkg/theme"
)

func main() {
	fmt.Println("==================================================================")
	fmt.Println("   MacCMS v10 智能采集聚合平台 - RESTful 纯后端 API 服务 (Go版)   ")
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

	// 2. 初始化持久化存储 (优先连接 PostgreSQL，失败则平滑降级至 SQLite 保证系统高可用)
	var dbStore store.Store
	if strings.ToLower(cfg.Database.Driver) == "postgres" {
		fmt.Printf("[*] 正在连接 PostgreSQL 数据库: %s\n", config.MaskDSN(cfg.Database.DSN))
		pgStore, pgErr := store.NewPostgresStore(cfg.Database.DSN)
		if pgErr == nil {
			dbStore = pgStore
			fmt.Println("[OK] PostgreSQL 数据库连接成功！已开启原生 JSONB 与高并发支持。")
		} else {
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

	// 5. 构建 HTTP 路由中心
	mux := http.NewServeMux()

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
	apiServer.RegisterRoutes(mux)

	// (D) 根路径服务 (浏览器访问自动跳转至 OpenAPI 交互式文档，程序访问返回 API 网关状态及规范索引)
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
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

		if r.URL.Path == "/" || r.URL.Path == "" {
			// 浏览器直接访问根目录时，自动重定向至 OpenAPI Swagger UI 交互文档
			if strings.Contains(r.Header.Get("Accept"), "text/html") {
				http.Redirect(w, r, "/docs", http.StatusFound)
				return
			}

			// API 工具或程序访问时返回在线状态及 OpenAPI 规范地址
			w.Header().Set("Content-Type", "application/json; charset=utf-8")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"name":        "Video Collection RESTful API Service",
				"version":     "1.0.0",
				"status":      "running",
				"docs_url":    "/docs",
				"openapi_url": "/openapi.json",
				"redoc_url":   "/redoc",
				"apis": map[string]string{
					"videos":     "/api/videos",
					"categories": "/api/categories",
					"rankings":   "/api/rankings",
					"latest":     "/api/latest",
					"rss":        "/rss.xml",
				},
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

	// 6. 启动服务监听
	port := os.Getenv("PORT")
	if port == "" {
		port = "80"
	}
	addr := ":" + port

	fmt.Println("\n------------------------------------------------------------------")
	fmt.Printf("  >> OpenAPI 交互文档 (Swagger UI): http://localhost:%s/docs\n", port)
	fmt.Printf("  >> OpenAPI 规范 JSON:             http://localhost:%s/openapi.json\n", port)
	fmt.Printf("  >> Redoc 静态文档视角:            http://localhost:%s/redoc\n", port)
	fmt.Printf("  >> 视频检索 RESTful API:          http://localhost:%s/api/videos\n", port)
	fmt.Printf("  >> 网页 RSS 2.0 聚合订阅:         http://localhost:%s/rss.xml\n", port)
	fmt.Println("------------------------------------------------------------------")
	fmt.Println("[*] 纯后端 API 服务启动就绪，正在监听请求...")

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
