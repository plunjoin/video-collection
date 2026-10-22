package api

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	_ "github.com/lib/pq"
	"video-collection-service/pkg/auth"
	"video-collection-service/pkg/bootstrap"
)

// registerBootstrapRoutes 注册「基础配置」管理接口。
// 基础配置持久化在 bootstrap SQLite（默认 data/collection.db）的 bootstrap_config 表中，
// 覆盖数据库连接、Redis 连接、初始管理员账号密码、Webhook 加密主密钥。
func (srv *Server) registerBootstrapRoutes(mux *http.ServeMux) {
	if srv.bootstrap == nil {
		return
	}
	adminAuth := func(next http.HandlerFunc) http.HandlerFunc {
		return auth.AdminRequired(srv.store, next)
	}
	mux.HandleFunc("/api/admin/bootstrap", adminAuth(srv.handleBootstrap))
	mux.HandleFunc("/api/admin/bootstrap/test-db", adminAuth(srv.handleBootstrapTestDB))
}

// bootstrapEnvKeys 环境变量对基础配置各键的覆盖开关（用于展示「当前生效来源」）
var bootstrapEnvKeys = map[string]string{
	bootstrap.KeyDBDriver:             "DB_DRIVER",
	bootstrap.KeyDBDSN:                "DB_DSN",
	bootstrap.KeyDBHost:               "DB_HOST",
	bootstrap.KeyDBUser:               "DB_USER",
	bootstrap.KeyDBPassword:           "DB_PASSWORD",
	bootstrap.KeyDBName:               "DB_NAME",
	bootstrap.KeyDBSSLMode:            "DB_SSLMODE",
	bootstrap.KeyRedisAddr:            "REDIS_ADDR",
	bootstrap.KeyRedisPassword:        "REDIS_PASSWORD",
	bootstrap.KeyRedisDB:              "REDIS_DB",
	bootstrap.KeyRedisPrefix:          "REDIS_PREFIX",
	bootstrap.KeyAdminUsername:        "ADMIN_INITIAL_USERNAME",
	bootstrap.KeyAdminPassword:        "ADMIN_INITIAL_PASSWORD",
	bootstrap.KeyWebhookEncryptionKey: "WEBHOOK_ENCRYPTION_KEY",
}

// handleBootstrap GET 读取 / PUT 保存基础配置（敏感字段掩码返回；保存后需重启生效）
func (srv *Server) handleBootstrap(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		srv.handleBootstrapGet(w, r)
	case http.MethodPut, http.MethodPost:
		srv.handleBootstrapSave(w, r)
	default:
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	}
}

func (srv *Server) handleBootstrapGet(w http.ResponseWriter, r *http.Request) {
	masked, err := srv.bootstrap.MaskedAll()
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "读取基础配置失败: "+err.Error())
		return
	}

	// 标注每一项的生效来源：环境变量覆盖 or bootstrap SQLite
	sources := make(map[string]string, len(masked))
	for key := range bootstrapEnvKeys {
		envName := bootstrapEnvKeys[key]
		if envName == bootstrap.KeyDBDSN && os.Getenv("DATABASE_URL") != "" {
			sources[key] = "env:DATABASE_URL"
			continue
		}
		if os.Getenv(envName) != "" {
			sources[key] = "env:" + envName
			continue
		}
		if _, ok := masked[key]; ok {
			sources[key] = "bootstrap"
		}
	}

	jsonResponse(w, http.StatusOK, map[string]any{
		"code": 1,
		"data": map[string]any{
			"path":    srv.bootstrap.Path(),
			"config":  masked,
			"sources": sources,
			"note":    "数据库/Redis 连接信息修改后需重启服务生效；初始管理员仅首次初始化数据库时生效",
		},
	})
}

// bootstrapSaveRequest 保存基础配置请求体（敏感字段传掩码占位符表示保持不变）
type bootstrapSaveRequest struct {
	Driver               string `json:"db_driver"`
	DSN                  string `json:"db_dsn"`
	Host                 string `json:"db_host"`
	Port                 string `json:"db_port"`
	User                 string `json:"db_user"`
	Password             string `json:"db_password"`
	Name                 string `json:"db_name"`
	SSLMode              string `json:"db_sslmode"`
	RedisAddr            string `json:"redis_addr"`
	RedisPassword        string `json:"redis_password"`
	RedisDB              string `json:"redis_db"`
	RedisPrefix          string `json:"redis_prefix"`
	AdminUsername        string `json:"admin_username"`
	AdminPassword        string `json:"admin_password"`
	WebhookEncryptionKey string `json:"webhook_encryption_key"`
}

func (req *bootstrapSaveRequest) entries() map[string]string {
	return map[string]string{
		bootstrap.KeyDBDriver:             req.Driver,
		bootstrap.KeyDBDSN:                req.DSN,
		bootstrap.KeyDBHost:               req.Host,
		bootstrap.KeyDBPort:               req.Port,
		bootstrap.KeyDBUser:               req.User,
		bootstrap.KeyDBPassword:           req.Password,
		bootstrap.KeyDBName:               req.Name,
		bootstrap.KeyDBSSLMode:            req.SSLMode,
		bootstrap.KeyRedisAddr:            req.RedisAddr,
		bootstrap.KeyRedisPassword:        req.RedisPassword,
		bootstrap.KeyRedisDB:              req.RedisDB,
		bootstrap.KeyRedisPrefix:          req.RedisPrefix,
		bootstrap.KeyAdminUsername:        req.AdminUsername,
		bootstrap.KeyAdminPassword:        req.AdminPassword,
		bootstrap.KeyWebhookEncryptionKey: req.WebhookEncryptionKey,
	}
}

func (srv *Server) handleBootstrapSave(w http.ResponseWriter, r *http.Request) {
	var req bootstrapSaveRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		errorResponse(w, http.StatusBadRequest, "请求体解析失败: "+err.Error())
		return
	}

	driver := strings.ToLower(strings.TrimSpace(req.Driver))
	if driver != "" && driver != "postgres" && driver != "sqlite" {
		errorResponse(w, http.StatusBadRequest, "不支持的数据库驱动: "+req.Driver+"（可选 postgres / sqlite）")
		return
	}

	// 掩码占位符 = 不修改原值（前端回显的是 ********）
	stored, err := srv.bootstrap.All()
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "读取基础配置失败: "+err.Error())
		return
	}
	entries := make(map[string]string, 16)
	for key, val := range req.entries() {
		if val == bootstrap.Masked || val == strings.Repeat("*", 6) {
			entries[key] = stored[key]
			continue
		}
		entries[key] = val
	}

	if err := srv.bootstrap.Save(entries); err != nil {
		errorResponse(w, http.StatusInternalServerError, "保存基础配置失败: "+err.Error())
		return
	}

	jsonResponse(w, http.StatusOK, map[string]any{
		"code": 1,
		"data": map[string]any{
			"saved": true,
			"note":  "已保存到基础配置（bootstrap SQLite），数据库/Redis 连接信息需重启服务后生效",
		},
	})
}

// bootstrapTestDBRequest 数据库连接测试请求（分项配置或完整 DSN 二选一）
type bootstrapTestDBRequest struct {
	Driver   string `json:"db_driver"`
	DSN      string `json:"db_dsn"`
	Host     string `json:"db_host"`
	Port     string `json:"db_port"`
	User     string `json:"db_user"`
	Password string `json:"db_password"`
	Name     string `json:"db_name"`
	SSLMode  string `json:"db_sslmode"`
}

func (srv *Server) handleBootstrapTestDB(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	var req bootstrapTestDBRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		errorResponse(w, http.StatusBadRequest, "请求体解析失败: "+err.Error())
		return
	}

	driver := strings.ToLower(strings.TrimSpace(req.Driver))
	if driver == "" {
		driver = "postgres"
	}
	if driver == "sqlite" {
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": map[string]any{"ok": true, "message": "SQLite 单文件模式无需连接测试"}})
		return
	}
	if driver != "postgres" {
		errorResponse(w, http.StatusBadRequest, "不支持的数据库驱动: "+req.Driver)
		return
	}

	// 掩码占位符时沿用已存储的密码
	stored, _ := srv.bootstrap.All()
	if req.Password == bootstrap.Masked || req.Password == strings.Repeat("*", 6) {
		req.Password = stored[bootstrap.KeyDBPassword]
	}
	if strings.TrimSpace(req.DSN) == "" && strings.TrimSpace(req.Host) != "" {
		req.DSN = "postgres://" + url.UserPassword(firstNonEmptyStr(req.User, "postgres"), req.Password).String() +
			"@" + req.Host + ":" + firstNonEmptyStr(req.Port, "5432") +
			"/" + firstNonEmptyStr(req.Name, "videodb") +
			"?sslmode=" + firstNonEmptyStr(req.SSLMode, "disable")
	}
	if strings.TrimSpace(req.DSN) == "" {
		errorResponse(w, http.StatusBadRequest, "请提供完整 DSN 或数据库分项配置")
		return
	}

	db, err := sql.Open("postgres", req.DSN)
	if err != nil {
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": map[string]any{"ok": false, "message": err.Error()}})
		return
	}
	defer db.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": map[string]any{"ok": false, "message": "连接失败: " + err.Error()}})
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": map[string]any{"ok": true, "message": "连接成功"}})
}

func firstNonEmptyStr(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return strings.TrimSpace(v)
		}
	}
	return ""
}
