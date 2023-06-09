package api

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"video-collection-api/config"
	"video-collection-api/pkg/auth"
	"video-collection-api/pkg/ingest"
	"video-collection-api/pkg/m3u8cleaner"
	"video-collection-api/pkg/maccms"
	"video-collection-api/pkg/player"
	"video-collection-api/pkg/scheduler"
	"video-collection-api/pkg/store"
	"video-collection-api/pkg/theme"
)

type Server struct {
	store         store.Store
	scheduler     *scheduler.Scheduler
	themeManager  *theme.Manager
	playerManager *player.Manager
	m3u8Cleaner   *m3u8cleaner.Handler
}

func NewServer(s store.Store, sc *scheduler.Scheduler, tm *theme.Manager, pm *player.Manager) *Server {
	cleanerHandler := m3u8cleaner.NewHandler(m3u8cleaner.DefaultOptions())
	return &Server{
		store:         s,
		scheduler:     sc,
		themeManager:  tm,
		playerManager: pm,
		m3u8Cleaner:   cleanerHandler,
	}
}

func (srv *Server) RegisterRoutes(mux *http.ServeMux) {
	srv.registerContentRoutes(mux)
	srv.registerCollectionRoutes(mux)
	// 公开接口
	mux.Handle("/api/m3u8/clean", srv.m3u8Cleaner)
	mux.Handle("/api/m3u8", srv.m3u8Cleaner)
	mux.HandleFunc("/api/login", srv.handleLogin)
	mux.HandleFunc("/api/register", srv.handleRegister)
	mux.HandleFunc("/api/logout", srv.handleLogout)
	mux.HandleFunc("/api/me", srv.handleMe)
	mux.HandleFunc("/api/categories", srv.handleCategories)
	mux.HandleFunc("/api/videos", srv.handleVideos)
	mux.HandleFunc("/api/video", srv.handleVideoDetail)
	mux.HandleFunc("/api/video/detail", srv.handleVideoDetail)
	mux.HandleFunc("/api/video/hit", srv.handleVideoHit)
	mux.HandleFunc("/api/rankings", srv.handleRankings)
	mux.HandleFunc("/api/latest", srv.handleLatest)
	mux.HandleFunc("/api/site/config", srv.handleSiteConfig)
	mux.HandleFunc("/api/feedback", srv.handleFeedback)

	// 用户播放历史与追剧收藏 (云端多设备同步)
	mux.HandleFunc("/api/user/history", srv.handleUserHistory)
	mux.HandleFunc("/api/user/history/sync", srv.handleUserHistorySync)
	mux.HandleFunc("/api/user/favorites", srv.handleUserFavorites)

	// 管理员专属接口 (带 AdminRequired 鉴权拦截)
	adminAuth := func(next http.HandlerFunc) http.HandlerFunc {
		return auth.AdminRequired(srv.store, next)
	}

	mux.HandleFunc("/api/admin/stats", adminAuth(srv.handleAdminStats))
	mux.HandleFunc("/api/admin/sources", adminAuth(srv.handleAdminSources))
	mux.HandleFunc("/api/admin/sources/test", adminAuth(srv.handleTestRemoteSource))
	mux.HandleFunc("/api/admin/sources/collect", adminAuth(srv.handleTriggerCollect))
	mux.HandleFunc("/api/admin/sources/collect-all", adminAuth(srv.handleAdminCollectAll))
	mux.HandleFunc("/api/admin/logs", adminAuth(srv.handleAdminLogs))
	mux.HandleFunc("/api/admin/videos", adminAuth(srv.handleAdminDeleteVideo))
	mux.HandleFunc("/api/admin/videos/save", adminAuth(srv.handleAdminSaveVideo))
	mux.HandleFunc("/api/admin/videos/batch-delete", adminAuth(srv.handleAdminBatchDeleteVideos))

	// 用户管理接口
	mux.HandleFunc("/api/admin/users", adminAuth(srv.handleAdminUsers))

	// 客户端主题管理与导入接口
	mux.HandleFunc("/api/admin/themes", adminAuth(srv.handleAdminThemes))
	mux.HandleFunc("/api/admin/themes/switch", adminAuth(srv.handleAdminSwitchTheme))
	mux.HandleFunc("/api/admin/themes/upload", adminAuth(srv.handleAdminUploadTheme))

	// 播放器公开接口与管理接口 (支持Video.js、第三方播放器与在线导入)
	mux.HandleFunc("/api/player/active", srv.handleActivePlayer)
	mux.HandleFunc("/api/admin/players", adminAuth(srv.handleAdminPlayers))
	mux.HandleFunc("/api/admin/players/switch", adminAuth(srv.handleAdminSwitchPlayer))
	mux.HandleFunc("/api/admin/players/upload", adminAuth(srv.handleAdminUploadPlayer))
	mux.HandleFunc("/api/admin/players/config", adminAuth(srv.handleAdminUpdatePlayerConfig))

	// 网站全局配置与定时计划任务
	mux.HandleFunc("/api/admin/site/config", adminAuth(srv.handleAdminSaveSiteConfig))
	mux.HandleFunc("/api/admin/scheduler/auto", adminAuth(srv.handleAdminAutoCollect))

	// 用户求片留言管理
	mux.HandleFunc("/api/admin/feedbacks", adminAuth(srv.handleAdminFeedbacks))
	mux.HandleFunc("/api/admin/feedbacks/reply", adminAuth(srv.handleAdminReplyFeedback))

	// 数据库管理 (引擎信息、表统计与浏览、备份恢复、清理维护与 SQL 执行器)
	mux.HandleFunc("/api/admin/db/info", adminAuth(srv.handleDBInfo))
	mux.HandleFunc("/api/admin/db/tables", adminAuth(srv.handleDBTables))
	mux.HandleFunc("/api/admin/db/table", adminAuth(srv.handleDBTable))
	mux.HandleFunc("/api/admin/db/backup", adminAuth(srv.handleDBBackup))
	mux.HandleFunc("/api/admin/db/backups", adminAuth(srv.handleDBBackups))
	mux.HandleFunc("/api/admin/db/restore", adminAuth(srv.handleDBRestore))
	mux.HandleFunc("/api/admin/db/cleanup", adminAuth(srv.handleDBCleanup))
	mux.HandleFunc("/api/admin/db/sql", adminAuth(srv.handleDBSQL))
}

func jsonResponse(w http.ResponseWriter, code int, data any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(data)
}

func errorResponse(w http.ResponseWriter, code int, msg string) {
	jsonResponse(w, code, map[string]any{"code": 0, "error": msg})
}

// 登录处理
func (srv *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}

	var req struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		errorResponse(w, http.StatusBadRequest, "参数解析失败")
		return
	}

	user, err := srv.store.GetUserByUsername(r.Context(), req.Username)
	if err != nil || user == nil {
		errorResponse(w, http.StatusUnauthorized, "用户名或密码错误")
		return
	}

	if user.Status != 1 {
		errorResponse(w, http.StatusForbidden, "该账号已被禁用封禁")
		return
	}

	if !auth.CheckPassword(user.PasswordHash, req.Password) {
		errorResponse(w, http.StatusUnauthorized, "用户名或密码错误")
		return
	}

	token := auth.DefaultSessionManager.CreateSession(user)
	auth.SetAuthCookie(w, token)

	jsonResponse(w, http.StatusOK, map[string]any{
		"code":  1,
		"msg":   "登录成功",
		"token": token,
		"user": map[string]any{
			"id":       user.ID,
			"username": user.Username,
			"nickname": user.Nickname,
			"role":     user.Role,
		},
	})
}

func (srv *Server) handleLogout(w http.ResponseWriter, r *http.Request) {
	if c, err := r.Cookie(auth.CookieAuthToken); err == nil {
		auth.DefaultSessionManager.DeleteSession(c.Value)
	}
	auth.ClearAuthCookie(w)
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "已退出登录"})
}

func (srv *Server) handleMe(w http.ResponseWriter, r *http.Request) {
	u := auth.GetCurrentUser(r, srv.store)
	if u == nil {
		errorResponse(w, http.StatusUnauthorized, "未登录")
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{
		"code": 1,
		"data": map[string]any{
			"id":       u.ID,
			"username": u.Username,
			"nickname": u.Nickname,
			"avatar":   u.Avatar,
			"role":     u.Role,
		},
	})
}

func (srv *Server) handleAdminStats(w http.ResponseWriter, r *http.Request) {
	stats, err := srv.store.GetStats(r.Context())
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": stats})
}

func (srv *Server) handleAdminSources(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	switch r.Method {
	case http.MethodGet:
		sources, err := srv.store.GetSources(ctx)
		if err != nil {
			errorResponse(w, http.StatusInternalServerError, err.Error())
			return
		}
		for i := range sources {
			sources[i].Active = sources[i].Enabled
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": sources})

	case http.MethodPost:
		bodyBytes, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 1024*1024))
		if err != nil {
			errorResponse(w, http.StatusBadRequest, "读取请求体失败")
			return
		}
		var rawMap map[string]any
		_ = json.Unmarshal(bodyBytes, &rawMap)

		var src config.SourceConfig
		if err := json.Unmarshal(bodyBytes, &src); err != nil {
			errorResponse(w, http.StatusBadRequest, "解析请求参数失败: "+err.Error())
			return
		}
		if activeVal, ok := rawMap["active"].(bool); ok {
			src.Enabled = activeVal
			src.Active = activeVal
		} else if src.Active {
			src.Enabled = true
		}
		if src.ID == "" {
			src.ID = "src_" + strconv.FormatInt(time.Now().Unix(), 10)
		}
		if src.Type == "pipeline" {
			if err := ingest.Validate(src); err != nil {
				errorResponse(w, http.StatusBadRequest, err.Error())
				return
			}
		}
		if src.Name == "" || (src.API == "" && src.Type != "pipeline") {
			errorResponse(w, http.StatusBadRequest, "采集源名称和API地址不能为空")
			return
		}
		if src.Type == "" {
			src.Type = "json"
		}
		if src.Type == "custom" {
			src.Type = "custom_json"
		}
		if src.CollectHours <= 0 {
			src.CollectHours = 24
		}
		if err := srv.store.SaveSource(ctx, src); err != nil {
			errorResponse(w, http.StatusInternalServerError, err.Error())
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "保存成功", "id": src.ID})

	case http.MethodDelete:
		id := r.URL.Query().Get("id")
		if id == "" {
			errorResponse(w, http.StatusBadRequest, "缺少 id 参数")
			return
		}
		if err := srv.store.DeleteSource(ctx, id); err != nil {
			errorResponse(w, http.StatusInternalServerError, err.Error())
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "删除成功"})
	default:
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	}
}

// 触发采集：支持 hours=24 增量采集和 hours=0 全量采集
func (srv *Server) handleTriggerCollect(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}

	var req struct {
		SourceID string `json:"source_id"`
		Hours    int    `json:"hours"` // 0 为全量，24 为过去24小时
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	if req.SourceID == "" {
		errorResponse(w, http.StatusBadRequest, "缺少 source_id")
		return
	}

	if err := srv.scheduler.TriggerCollect(req.SourceID, req.Hours); err != nil {
		errorResponse(w, http.StatusBadRequest, err.Error())
		return
	}

	modeStr := "全量采集"
	if req.Hours > 0 {
		modeStr = strconv.Itoa(req.Hours) + "小时增量采集"
	}
	jsonResponse(w, http.StatusOK, map[string]any{
		"code": 1,
		"msg":  "已在后台启动 " + modeStr + " 任务",
	})
}

func (srv *Server) handleTestRemoteSource(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}

	var req struct {
		API           string               `json:"api"`
		Type          string               `json:"type"`
		Headers       map[string]string    `json:"headers"`
		CustomParams  map[string]string    `json:"custom_params"`
		CustomMapping config.CustomMapping `json:"custom_mapping"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		errorResponse(w, http.StatusBadRequest, "参数解析错误: "+err.Error())
		return
	}
	if req.API == "" {
		errorResponse(w, http.StatusBadRequest, "API 接口地址不能为空")
		return
	}
	if req.Type == "" {
		req.Type = "json"
	}

	client := maccms.NewClient(config.SourceConfig{
		API:           req.API,
		Type:          req.Type,
		Headers:       req.Headers,
		CustomParams:  req.CustomParams,
		CustomMapping: req.CustomMapping,
		TimeoutSec:    12,
		RetryCount:    2,
	})

	ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
	defer cancel()

	classes, _ := client.GetClassList(ctx)

	// 同时尝试探测抓取第一页数据验证视频解析
	cleaned, rawResp, err := client.CollectPage(ctx, maccms.QueryParams{Action: "detail", Page: 1, Hours: 24})
	if err != nil && len(classes) == 0 {
		errorResponse(w, http.StatusBadRequest, "连接或探测失败: "+err.Error())
		return
	}

	var sampleTitles []string
	if rawResp != nil {
		for i, it := range rawResp.List {
			if i >= 5 {
				break
			}
			if it.VodName != "" {
				sampleTitles = append(sampleTitles, it.VodName)
			}
		}
	}

	jsonResponse(w, http.StatusOK, map[string]any{
		"code":          1,
		"msg":           "探测连接成功",
		"classes":       classes,
		"classes_total": len(classes),
		"samples":       sampleTitles,
		"sample_count":  len(cleaned),
		"total":         len(classes),
	})
}

func (srv *Server) handleAdminLogs(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 {
		limit = 100
	}
	jsonResponse(w, http.StatusOK, map[string]any{
		"code": 1,
		"data": srv.scheduler.GetRecentLogs(limit),
	})
}

func (srv *Server) handleAdminDeleteVideo(w http.ResponseWriter, r *http.Request) {
	id, _ := strconv.Atoi(r.URL.Query().Get("id"))
	if id <= 0 {
		errorResponse(w, http.StatusBadRequest, "缺少有效 id 参数")
		return
	}
	if err := srv.store.DeleteVideo(r.Context(), id); err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "删除视频成功"})
}

// 用户管理 API
func (srv *Server) handleAdminUsers(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	switch r.Method {
	case http.MethodGet:
		users, err := srv.store.ListUsers(ctx)
		if err != nil {
			errorResponse(w, http.StatusInternalServerError, err.Error())
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": users})

	case http.MethodPost:
		var req struct {
			ID       int    `json:"id"`
			Username string `json:"username"`
			Password string `json:"password"`
			Nickname string `json:"nickname"`
			Role     string `json:"role"`
			Status   int    `json:"status"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			errorResponse(w, http.StatusBadRequest, "解析请求参数失败: "+err.Error())
			return
		}

		if req.ID > 0 {
			// 修改用户
			u, err := srv.store.GetUserByID(ctx, req.ID)
			if err != nil || u == nil {
				errorResponse(w, http.StatusNotFound, "用户不存在")
				return
			}
			u.Nickname = req.Nickname
			if req.Role != "" {
				u.Role = req.Role
			}
			u.Status = req.Status
			if req.Password != "" {
				hash, err := auth.HashPassword(req.Password)
				if err != nil {
					errorResponse(w, http.StatusInternalServerError, "密码加密失败")
					return
				}
				u.PasswordHash = hash
			}
			if err := srv.store.UpdateUser(ctx, u); err != nil {
				errorResponse(w, http.StatusInternalServerError, err.Error())
				return
			}
			jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "用户修改成功"})
		} else {
			// 新增用户
			if req.Username == "" || req.Password == "" {
				errorResponse(w, http.StatusBadRequest, "用户名和密码不能为空")
				return
			}
			hash, err := auth.HashPassword(req.Password)
			if err != nil {
				errorResponse(w, http.StatusInternalServerError, "密码加密失败")
				return
			}
			if req.Role == "" {
				req.Role = "user"
			}
			newUser := &store.User{
				Username:     req.Username,
				PasswordHash: hash,
				Nickname:     req.Nickname,
				Role:         req.Role,
				Status:       req.Status,
			}
			if err := srv.store.CreateUser(ctx, newUser); err != nil {
				errorResponse(w, http.StatusBadRequest, "创建用户失败(用户名可能已存在): "+err.Error())
				return
			}
			jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "创建用户成功", "id": newUser.ID})
		}

	case http.MethodDelete:
		id, _ := strconv.Atoi(r.URL.Query().Get("id"))
		if id <= 0 {
			errorResponse(w, http.StatusBadRequest, "缺少有效 id 参数")
			return
		}
		if id == 1 {
			errorResponse(w, http.StatusBadRequest, "不能删除默认超级管理员")
			return
		}
		if err := srv.store.DeleteUser(ctx, id); err != nil {
			errorResponse(w, http.StatusInternalServerError, err.Error())
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "删除用户成功"})

	default:
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	}
}

// 主题管理 API
func (srv *Server) handleAdminThemes(w http.ResponseWriter, r *http.Request) {
	themes, err := srv.themeManager.ListThemes(r.Context())
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": themes})
}

func (srv *Server) handleAdminSwitchTheme(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}

	var req struct {
		ThemeID string `json:"theme_id"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	if req.ThemeID == "" {
		errorResponse(w, http.StatusBadRequest, "缺少 theme_id")
		return
	}

	if err := srv.themeManager.SetActiveTheme(r.Context(), req.ThemeID); err != nil {
		errorResponse(w, http.StatusBadRequest, err.Error())
		return
	}

	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "主题切换成功"})
}

func (srv *Server) handleAdminUploadTheme(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}

	// 限制文件大小 30MB
	_ = r.ParseMultipartForm(30 << 20)
	file, handler, err := r.FormFile("file")
	if err != nil {
		errorResponse(w, http.StatusBadRequest, "读取上传文件失败: "+err.Error())
		return
	}
	defer file.Close()

	if !strings.HasSuffix(strings.ToLower(handler.Filename), ".zip") {
		errorResponse(w, http.StatusBadRequest, "仅支持上传 .zip 格式的主题压缩包")
		return
	}

	info, err := srv.themeManager.ImportThemeZip(file, handler.Size)
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "解压导入主题失败: "+err.Error())
		return
	}

	jsonResponse(w, http.StatusOK, map[string]any{
		"code": 1,
		"msg":  "主题导入成功",
		"data": info,
	})
}

// 视频检索与分类 (公开，前台与后台共用，支持级联父子分类树展开)
func (srv *Server) handleVideos(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	page, _ := strconv.Atoi(q.Get("page"))
	if page <= 0 {
		page = 1
	}
	pageSize, _ := strconv.Atoi(q.Get("page_size"))
	if pageSize <= 0 || pageSize > 100 {
		pageSize = 18
	}
	typeID, _ := strconv.Atoi(q.Get("type_id"))
	keyword := strings.TrimSpace(q.Get("keyword"))
	area := strings.TrimSpace(q.Get("area"))
	year := strings.TrimSpace(q.Get("year"))
	orderBy := strings.TrimSpace(q.Get("order_by"))
	if orderBy == "" {
		orderBy = strings.TrimSpace(q.Get("sort"))
	}
	orderDesc := true
	if q.Get("order_desc") == "false" || q.Get("order_dir") == "asc" {
		orderDesc = false
	}

	records, total, err := srv.store.QueryVideos(r.Context(), store.VideoQuery{
		Page:      page,
		PageSize:  pageSize,
		TypeID:    typeID,
		Keyword:   keyword,
		Area:      area,
		Year:      year,
		OrderBy:   orderBy,
		OrderDesc: orderDesc,
	})
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}

	jsonResponse(w, http.StatusOK, map[string]any{
		"code":      1,
		"page":      page,
		"page_size": pageSize,
		"total":     total,
		"data":      records,
	})
}

func (srv *Server) handleCategories(w http.ResponseWriter, r *http.Request) {
	cats, err := srv.store.GetCategories(r.Context())
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": cats})
}

// 获取当前激活的播放器及配置 (公开接口，客户端门户据此渲染)
func (srv *Server) handleActivePlayer(w http.ResponseWriter, r *http.Request) {
	p, err := srv.playerManager.GetActivePlayer(r.Context())
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": p})
}

// 播放器管理：列出所有已安装的播放器
func (srv *Server) handleAdminPlayers(w http.ResponseWriter, r *http.Request) {
	players, err := srv.playerManager.ListPlayers(r.Context())
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": players})
}

// 播放器管理：切换激活的播放器
func (srv *Server) handleAdminSwitchPlayer(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}

	var req struct {
		PlayerID string `json:"player_id"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	if req.PlayerID == "" {
		errorResponse(w, http.StatusBadRequest, "缺少 player_id")
		return
	}

	if err := srv.playerManager.SetActivePlayer(r.Context(), req.PlayerID); err != nil {
		errorResponse(w, http.StatusBadRequest, err.Error())
		return
	}

	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "播放器已成功切换"})
}

// 播放器管理：上传并解压 ZIP 导入播放器插件
func (srv *Server) handleAdminUploadPlayer(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}

	_ = r.ParseMultipartForm(30 << 20)
	file, handler, err := r.FormFile("file")
	if err != nil {
		errorResponse(w, http.StatusBadRequest, "读取上传文件失败: "+err.Error())
		return
	}
	defer file.Close()

	if !strings.HasSuffix(strings.ToLower(handler.Filename), ".zip") {
		errorResponse(w, http.StatusBadRequest, "仅支持上传 .zip 格式的播放器扩展包")
		return
	}

	info, err := srv.playerManager.ImportPlayerZip(file, handler.Size)
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "解压导入播放器失败: "+err.Error())
		return
	}

	jsonResponse(w, http.StatusOK, map[string]any{
		"code": 1,
		"msg":  "播放器扩展导入成功",
		"data": info,
	})
}

// 播放器管理：保存特定播放器的配置参数 (如第三方解析接口模板)
func (srv *Server) handleAdminUpdatePlayerConfig(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}

	var req struct {
		PlayerID string                 `json:"player_id"`
		Config   map[string]interface{} `json:"config"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.PlayerID == "" {
		errorResponse(w, http.StatusBadRequest, "参数格式错误")
		return
	}

	if err := srv.playerManager.UpdatePlayerConfig(r.Context(), req.PlayerID, req.Config); err != nil {
		errorResponse(w, http.StatusInternalServerError, "更新配置失败: "+err.Error())
		return
	}

	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "播放器配置已更新"})
}

// 视频详情与相关推荐接口 (公开，支持按 ID 精确获取全部线路与剧集)
func (srv *Server) handleVideoDetail(w http.ResponseWriter, r *http.Request) {
	idStr := r.URL.Query().Get("id")
	id, _ := strconv.Atoi(idStr)
	if id <= 0 {
		errorResponse(w, http.StatusBadRequest, "缺少有效视频 ID 参数")
		return
	}

	video, err := srv.store.GetVideoByID(r.Context(), id)
	if err != nil || video == nil {
		errorResponse(w, http.StatusNotFound, "未找到该影片详情")
		return
	}

	// 相关推荐：严格按照 名称/同系列/类型 顺序智能推荐 (提取系列名 -> 同系列 -> 同类型补齐)
	related := srv.getRelatedVideos(r.Context(), video, 10)

	jsonResponse(w, http.StatusOK, map[string]any{
		"code":    1,
		"data":    video,
		"related": related,
	})
}

var (
	seasonRegex      = regexp.MustCompile(`(?i)(第[0-9一二三四五六七八九十百]+[季部期卷篇话回册次章集]|Season\s*\d+|S\d+|Part\s*\d+|Vol\s*\d+|The\s+Final\s+Season|The\s+Movie)`)
	tagRegex         = regexp.MustCompile(`(?i)(最终季|完结篇|终篇|前篇|后篇|剧场版|特别篇|总集篇|重制版|重置版|真人版|电影版|电视版|TV版|先行版|精编版|年番|篇|OVA|OAD|SP|BD|HD|4K|动态漫|动态漫画|普通话|国语|日语|中字|双语)`)
	bracketRegex     = regexp.MustCompile(`[（(\[【].*?[）)\]】]`)
	delimiterRegex   = regexp.MustCompile(`[:：·\-_—/]+`)
	trailingNumRegex = regexp.MustCompile(`(?i)(II|III|IV|V|VI|VII|VIII|IX|X|\d+)$`)
)

func cleanSeriesRoot(raw string) string {
	s := strings.TrimSpace(raw)
	if s == "" {
		return ""
	}
	s = bracketRegex.ReplaceAllString(s, " ")
	s = seasonRegex.ReplaceAllString(s, " ")
	s = tagRegex.ReplaceAllString(s, " ")

	parts := delimiterRegex.Split(s, -1)
	if len(parts) > 0 && strings.TrimSpace(parts[0]) != "" {
		s = parts[0]
	}

	fields := strings.Fields(s)
	if len(fields) > 0 {
		s = fields[0]
	}

	s = trailingNumRegex.ReplaceAllString(s, "")
	s = strings.TrimSpace(s)
	return s
}

func extractSeriesKeywords(name, subName string) []string {
	var kws []string
	seen := make(map[string]bool)

	addKw := func(kw string) {
		kw = strings.TrimSpace(kw)
		if utf8.RuneCountInString(kw) >= 2 && !seen[kw] {
			seen[kw] = true
			kws = append(kws, kw)
		}
	}

	root := cleanSeriesRoot(name)
	if root != "" {
		addKw(root)
	}

	subRoot := cleanSeriesRoot(subName)
	if subRoot != "" {
		addKw(subRoot)
	}

	rawTrim := strings.TrimSpace(name)
	if rawTrim != root && utf8.RuneCountInString(rawTrim) >= 2 && utf8.RuneCountInString(rawTrim) <= 12 {
		addKw(rawTrim)
	}

	return kws
}

func (srv *Server) getRelatedVideos(ctx context.Context, video *store.VideoRecord, limit int) []store.VideoRecord {
	if limit <= 0 {
		limit = 10
	}
	var related []store.VideoRecord
	addedIDs := make(map[int]bool)
	addedIDs[video.ID] = true
	excludeIDs := []int{video.ID}

	// 1. 优先按照同系列/名称智能匹配 (同系列与同名作品优先)
	kws := extractSeriesKeywords(video.Name, video.SubName)
	for _, kw := range kws {
		if len(related) >= limit {
			break
		}
		seriesList, _, err := srv.store.QueryVideos(ctx, store.VideoQuery{
			NameKeyword: kw,
			ExcludeIDs:  excludeIDs,
			Page:        1,
			PageSize:    limit,
			OrderBy:     "hits",
			OrderDesc:   true,
		})
		if err == nil {
			for _, v := range seriesList {
				if !addedIDs[v.ID] {
					addedIDs[v.ID] = true
					excludeIDs = append(excludeIDs, v.ID)
					related = append(related, v)
					if len(related) >= limit {
						break
					}
				}
			}
		}
	}

	// 2. 其次按照同分类/同类型补充 (同类型热门)
	if len(related) < limit && video.TypeID > 0 {
		needed := limit - len(related)
		typeList, _, err := srv.store.QueryVideos(ctx, store.VideoQuery{
			TypeID:     video.TypeID,
			ExcludeIDs: excludeIDs,
			Page:       1,
			PageSize:   needed * 2,
			OrderBy:    "hits",
			OrderDesc:  true,
		})
		if err == nil {
			for _, v := range typeList {
				if !addedIDs[v.ID] {
					addedIDs[v.ID] = true
					excludeIDs = append(excludeIDs, v.ID)
					related = append(related, v)
					if len(related) >= limit {
						break
					}
				}
			}
		}
	}

	// 3. 兜底策略：若仍不足，取全站最热门影片
	if len(related) < limit {
		needed := limit - len(related)
		hotList, _, err := srv.store.QueryVideos(ctx, store.VideoQuery{
			ExcludeIDs: excludeIDs,
			Page:       1,
			PageSize:   needed * 2,
			OrderBy:    "hits",
			OrderDesc:  true,
		})
		if err == nil {
			for _, v := range hotList {
				if !addedIDs[v.ID] {
					addedIDs[v.ID] = true
					excludeIDs = append(excludeIDs, v.ID)
					related = append(related, v)
					if len(related) >= limit {
						break
					}
				}
			}
		}
	}

	return related
}

// 用户公开注册
func (srv *Server) handleRegister(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	var req struct {
		Username string `json:"username"`
		Password string `json:"password"`
		Nickname string `json:"nickname"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		errorResponse(w, http.StatusBadRequest, "参数解析失败")
		return
	}
	req.Username = strings.TrimSpace(req.Username)
	req.Password = strings.TrimSpace(req.Password)
	if req.Username == "" || req.Password == "" {
		errorResponse(w, http.StatusBadRequest, "用户名和密码不能为空")
		return
	}
	if len(req.Password) < 6 {
		errorResponse(w, http.StatusBadRequest, "密码长度不能少于6位")
		return
	}
	if req.Nickname == "" {
		req.Nickname = req.Username
	}
	hash, err := auth.HashPassword(req.Password)
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "密码加密失败")
		return
	}
	newUser := &store.User{
		Username:     req.Username,
		PasswordHash: hash,
		Nickname:     req.Nickname,
		Role:         "user",
		Status:       1,
	}
	if err := srv.store.CreateUser(r.Context(), newUser); err != nil {
		errorResponse(w, http.StatusBadRequest, "用户名已存在或注册失败: "+err.Error())
		return
	}
	token := auth.DefaultSessionManager.CreateSession(newUser)
	auth.SetAuthCookie(w, token)
	jsonResponse(w, http.StatusOK, map[string]any{
		"code":  1,
		"msg":   "注册成功并已登录",
		"token": token,
		"user": map[string]any{
			"id":       newUser.ID,
			"username": newUser.Username,
			"nickname": newUser.Nickname,
			"role":     newUser.Role,
		},
	})
}

// 站点公开全局配置
func (srv *Server) handleSiteConfig(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	settings, _ := srv.store.GetAllSettings(ctx)
	if settings == nil {
		settings = make(map[string]string)
	}
	defaults := map[string]string{
		"site_name":                   "Bllii 动漫聚合",
		"site_subtitle":               "追番库 • 让生活多一种可能",
		"site_announcement":           "欢迎访问Bllii二次元番剧聚合平台！全新升级流媒体视觉、极光画质增强引擎与全站新番排行榜已全面开启！",
		"site_keywords":               "高清动漫,番剧新番,日漫,国漫,免费在线观看,苹果CMS接口",
		"site_description":            "Bllii致力于提供全面、快速的高清二次元番剧与动漫流媒体在线观看服务与智能聚合。",
		"site_notice_enabled":         "1",
		"auto_collect_enabled":        "0",
		"auto_collect_interval_hours": "2",
		"site_friend_links":           `[{"name":"Bangumi 番组计划","url":"https://bangumi.tv","description":"动画与游戏分享社区"},{"name":"萌娘百科","url":"https://zh.moegirl.org.cn","description":"万物皆可萌的ACG百科全书"},{"name":"ACG 动漫社区","url":"https://acg.rip","description":"动漫资源分享与爱好者交流"},{"name":"MyAnimeList","url":"https://myanimelist.net","description":"全球知名动漫资料库"},{"name":"AnimeDB","url":"https://anidb.net","description":"动漫数据库与档案"}]`,
		"site_contact_email":          "contact@Bllii.com",
		"site_contact_group":          "官方交流群: 876543210 (TG: @Bllii)",
		"site_disclaimer":             "【免责声明】本站所有视频资源均系第三方公开网络接口与网络爬虫自动检索聚合，本站服务器不存储、不制作、不上传任何视听节目及视频文件。若相关内容无意侵犯了贵司版权或合法权益，请通过上方联系方式提供权利证明与侵权链接，我们将在收到通知后24小时内断开相关播放解析并配合清理。本站提倡支持正版影视与动漫。",
	}
	for k, v := range defaults {
		if _, exists := settings[k]; !exists {
			settings[k] = v
		}
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": settings})
}

func (srv *Server) handleAdminSaveSiteConfig(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	var req map[string]string
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		errorResponse(w, http.StatusBadRequest, "解析参数失败: "+err.Error())
		return
	}
	if err := srv.store.SetSettings(r.Context(), req); err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "站点配置已保存"})
}

// 排行榜列表 (公开)
func (srv *Server) handleRankings(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	q := r.URL.Query()
	typeID, _ := strconv.Atoi(q.Get("type_id"))
	limit, _ := strconv.Atoi(q.Get("limit"))
	if limit <= 0 || limit > 50 {
		limit = 10
	}

	hotList, err := srv.store.GetHotVideos(ctx, typeID, limit)
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}

	movies, _ := srv.store.GetHotVideos(ctx, 1, 10)
	tv, _ := srv.store.GetHotVideos(ctx, 2, 10)
	variety, _ := srv.store.GetHotVideos(ctx, 3, 10)
	anime, _ := srv.store.GetHotVideos(ctx, 4, 10)

	jsonResponse(w, http.StatusOK, map[string]any{
		"code":    1,
		"top":     hotList,
		"movies":  movies,
		"tv":      tv,
		"variety": variety,
		"anime":   anime,
	})
}

// 最近更新时间线 (公开)
func (srv *Server) handleLatest(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	typeID, _ := strconv.Atoi(r.URL.Query().Get("type_id"))

	list, total, err := srv.store.QueryVideos(ctx, store.VideoQuery{
		Page:      1,
		PageSize:  60,
		TypeID:    typeID,
		OrderBy:   "updated_at",
		OrderDesc: true,
	})
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}

	todayDate := time.Now().Format("2006-01-02")
	yesterdayDate := time.Now().AddDate(0, 0, -1).Format("2006-01-02")

	var todayList, yesterdayList, earlierList []store.VideoRecord
	for _, v := range list {
		dStr := v.UpdatedAt.Format("2006-01-02")
		if dStr == todayDate {
			todayList = append(todayList, v)
		} else if dStr == yesterdayDate {
			yesterdayList = append(yesterdayList, v)
		} else {
			earlierList = append(earlierList, v)
		}
	}

	jsonResponse(w, http.StatusOK, map[string]any{
		"code":      1,
		"total":     total,
		"today":     todayList,
		"yesterday": yesterdayList,
		"earlier":   earlierList,
	})
}

// 视频点击播放量打点
func (srv *Server) handleVideoHit(w http.ResponseWriter, r *http.Request) {
	id, _ := strconv.Atoi(r.URL.Query().Get("id"))
	if id <= 0 {
		errorResponse(w, http.StatusBadRequest, "缺少有效 id 参数")
		return
	}
	_ = srv.store.IncrementVideoHits(r.Context(), id)
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "ok"})
}

// 用户留言与求片报错 (公开提交与查询)
func (srv *Server) handleFeedback(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	switch r.Method {
	case http.MethodGet:
		page, _ := strconv.Atoi(r.URL.Query().Get("page"))
		if page <= 0 {
			page = 1
		}
		pageSize, _ := strconv.Atoi(r.URL.Query().Get("page_size"))
		if pageSize <= 0 || pageSize > 100 {
			pageSize = 20
		}
		status := r.URL.Query().Get("status")
		fbType := r.URL.Query().Get("type")

		list, total, err := srv.store.ListFeedbacks(ctx, page, pageSize, status, fbType)
		if err != nil {
			errorResponse(w, http.StatusInternalServerError, err.Error())
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{
			"code":      1,
			"page":      page,
			"page_size": pageSize,
			"total":     total,
			"data":      list,
		})

	case http.MethodPost:
		var req struct {
			Type    string `json:"type"`
			Title   string `json:"title"`
			Content string `json:"content"`
			Contact string `json:"contact"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			errorResponse(w, http.StatusBadRequest, "参数解析失败")
			return
		}
		req.Title = strings.TrimSpace(req.Title)
		req.Content = strings.TrimSpace(req.Content)
		if req.Title == "" || req.Content == "" {
			errorResponse(w, http.StatusBadRequest, "标题和内容不能为空")
			return
		}
		if req.Type == "" {
			req.Type = "request"
		}
		fb := &store.Feedback{
			Type:    req.Type,
			Title:   req.Title,
			Content: req.Content,
			Contact: req.Contact,
			Status:  "pending",
		}
		if err := srv.store.CreateFeedback(ctx, fb); err != nil {
			errorResponse(w, http.StatusInternalServerError, "提交失败: "+err.Error())
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{
			"code": 1,
			"msg":  "留言提交成功，管理员会尽快跟进处理！",
			"id":   fb.ID,
		})
	default:
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	}
}

// 管理员手动保存/编辑视频
func (srv *Server) handleAdminSaveVideo(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	var rec store.VideoRecord
	if err := json.NewDecoder(r.Body).Decode(&rec); err != nil {
		errorResponse(w, http.StatusBadRequest, "参数解析失败: "+err.Error())
		return
	}
	if rec.Name == "" {
		errorResponse(w, http.StatusBadRequest, "视频名称不能为空")
		return
	}
	id, err := srv.store.SaveVideoManual(r.Context(), &rec)
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, "保存视频失败: "+err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "视频保存成功", "id": id})
}

// 管理员批量删除视频
func (srv *Server) handleAdminBatchDeleteVideos(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	var req struct {
		IDs []int `json:"ids"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || len(req.IDs) == 0 {
		errorResponse(w, http.StatusBadRequest, "请选择要删除的视频ID列表")
		return
	}
	if err := srv.store.BatchDeleteVideos(r.Context(), req.IDs); err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": fmt.Sprintf("已成功批量删除 %d 部视频", len(req.IDs))})
}

// 管理员管理留言反馈
func (srv *Server) handleAdminFeedbacks(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	switch r.Method {
	case http.MethodGet:
		srv.handleFeedback(w, r)
	case http.MethodDelete:
		id, _ := strconv.Atoi(r.URL.Query().Get("id"))
		if id <= 0 {
			errorResponse(w, http.StatusBadRequest, "缺少有效 id 参数")
			return
		}
		if err := srv.store.DeleteFeedback(ctx, id); err != nil {
			errorResponse(w, http.StatusInternalServerError, err.Error())
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "删除反馈成功"})
	default:
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	}
}

func (srv *Server) handleAdminReplyFeedback(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	var req struct {
		ID     int    `json:"id"`
		Status string `json:"status"`
		Reply  string `json:"reply"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.ID <= 0 {
		errorResponse(w, http.StatusBadRequest, "参数解析失败")
		return
	}
	if err := srv.store.UpdateFeedback(r.Context(), req.ID, req.Status, req.Reply); err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "反馈处理状态已更新"})
}

// 管理员配置定时采集与全网一键采集
func (srv *Server) handleAdminAutoCollect(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		status := srv.scheduler.GetAutoCollectStatus()
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": status})
	case http.MethodPost:
		var req struct {
			Enabled       bool `json:"enabled"`
			IntervalHours int  `json:"interval_hours"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			errorResponse(w, http.StatusBadRequest, "参数错误: "+err.Error())
			return
		}
		if err := srv.scheduler.SetAutoCollectConfig(r.Context(), req.Enabled, req.IntervalHours); err != nil {
			errorResponse(w, http.StatusInternalServerError, err.Error())
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "定时自动采集配置已更新"})
	default:
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	}
}

func (srv *Server) handleAdminCollectAll(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	var req struct {
		Hours int `json:"hours"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	if err := srv.scheduler.TriggerCollectAll(req.Hours); err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "已触发全网采集源并发采集任务"})
}

// handleUserHistory 处理用户云端单条历史的查询、上报与删除
func (srv *Server) handleUserHistory(w http.ResponseWriter, r *http.Request) {
	u := auth.GetCurrentUser(r, srv.store)
	if u == nil {
		errorResponse(w, http.StatusUnauthorized, "未登录")
		return
	}

	switch r.Method {
	case http.MethodGet:
		limit := 50
		if lStr := r.URL.Query().Get("limit"); lStr != "" {
			if l, err := strconv.Atoi(lStr); err == nil && l > 0 {
				limit = l
			}
		}
		list, err := srv.store.GetUserHistory(r.Context(), u.ID, limit)
		if err != nil {
			errorResponse(w, http.StatusInternalServerError, err.Error())
			return
		}
		if list == nil {
			list = []store.UserHistoryItem{}
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": list})

	case http.MethodPost:
		var req struct {
			VideoID      int     `json:"video_id"`
			VideoName    string  `json:"video_name"`
			Picture      string  `json:"picture"`
			EpisodeName  string  `json:"episode_name"`
			RouteIndex   int     `json:"route_index"`
			EpisodeIndex int     `json:"episode_index"`
			CurrentTime  int     `json:"current_time"`
			Duration     int     `json:"duration"`
			Progress     float64 `json:"progress"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			errorResponse(w, http.StatusBadRequest, "参数解析失败")
			return
		}
		if req.VideoID <= 0 {
			errorResponse(w, http.StatusBadRequest, "无效的影片ID")
			return
		}
		item := &store.UserHistoryItem{
			UserID:       u.ID,
			VideoID:      req.VideoID,
			VideoName:    req.VideoName,
			Picture:      req.Picture,
			EpisodeName:  req.EpisodeName,
			RouteIndex:   req.RouteIndex,
			EpisodeIndex: req.EpisodeIndex,
			CurrentTime:  req.CurrentTime,
			Duration:     req.Duration,
			Progress:     req.Progress,
		}
		if err := srv.store.SaveUserHistory(r.Context(), item); err != nil {
			errorResponse(w, http.StatusInternalServerError, err.Error())
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "进度已同步至云端"})

	case http.MethodDelete:
		idStr := r.URL.Query().Get("id")
		if idStr == "" || idStr == "all" || r.URL.Query().Get("clear") == "1" {
			if err := srv.store.ClearUserHistory(r.Context(), u.ID); err != nil {
				errorResponse(w, http.StatusInternalServerError, err.Error())
				return
			}
			jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "已清空云端播放历史"})
			return
		}
		vid, err := strconv.Atoi(idStr)
		if err != nil {
			errorResponse(w, http.StatusBadRequest, "无效的影片ID")
			return
		}
		if err := srv.store.DeleteUserHistory(r.Context(), u.ID, vid); err != nil {
			errorResponse(w, http.StatusInternalServerError, err.Error())
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "已移除该条播放记录"})

	default:
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	}
}

// handleUserHistorySync 处理登录后多设备双向合并同步
func (srv *Server) handleUserHistorySync(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	u := auth.GetCurrentUser(r, srv.store)
	if u == nil {
		errorResponse(w, http.StatusUnauthorized, "未登录")
		return
	}

	var localList []struct {
		ID           int     `json:"id"`
		Name         string  `json:"name"`
		Picture      string  `json:"picture"`
		EpisodeName  string  `json:"episodeName"`
		RouteIndex   int     `json:"routeIndex"`
		EpisodeIndex int     `json:"episodeIndex"`
		CurrentTime  int     `json:"currentTime"`
		Duration     int     `json:"duration"`
		Progress     float64 `json:"progress"`
		WatchedAt    int64   `json:"watchedAt"`
	}
	_ = json.NewDecoder(r.Body).Decode(&localList)

	ctx := r.Context()
	for _, it := range localList {
		if it.ID <= 0 {
			continue
		}
		h := &store.UserHistoryItem{
			UserID:       u.ID,
			VideoID:      it.ID,
			VideoName:    it.Name,
			Picture:      it.Picture,
			EpisodeName:  it.EpisodeName,
			RouteIndex:   it.RouteIndex,
			EpisodeIndex: it.EpisodeIndex,
			CurrentTime:  it.CurrentTime,
			Duration:     it.Duration,
			Progress:     it.Progress,
		}
		_ = srv.store.SaveUserHistory(ctx, h)
	}

	// 重新拉取云端合并后的最新记录回传前端
	latest, err := srv.store.GetUserHistory(ctx, u.ID, 100)
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	if latest == nil {
		latest = []store.UserHistoryItem{}
	}
	jsonResponse(w, http.StatusOK, map[string]any{
		"code": 1,
		"msg":  "多设备播放记录双向同步成功",
		"data": latest,
	})
}

// handleUserFavorites 处理用户云端追剧收藏
func (srv *Server) handleUserFavorites(w http.ResponseWriter, r *http.Request) {
	u := auth.GetCurrentUser(r, srv.store)
	if u == nil {
		errorResponse(w, http.StatusUnauthorized, "未登录")
		return
	}

	switch r.Method {
	case http.MethodGet:
		list, err := srv.store.GetUserFavorites(r.Context(), u.ID, 100)
		if err != nil {
			errorResponse(w, http.StatusInternalServerError, err.Error())
			return
		}
		if list == nil {
			list = []store.UserFavoriteItem{}
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": list})

	case http.MethodPost:
		var req struct {
			VideoID   int    `json:"video_id"`
			VideoName string `json:"video_name"`
			Picture   string `json:"picture"`
			Remarks   string `json:"remarks"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.VideoID <= 0 {
			errorResponse(w, http.StatusBadRequest, "参数解析失败")
			return
		}
		fav := &store.UserFavoriteItem{
			UserID:    u.ID,
			VideoID:   req.VideoID,
			VideoName: req.VideoName,
			Picture:   req.Picture,
			Remarks:   req.Remarks,
		}
		if err := srv.store.SaveUserFavorite(r.Context(), fav); err != nil {
			errorResponse(w, http.StatusInternalServerError, err.Error())
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "已加入云端追剧收藏"})

	case http.MethodDelete:
		idStr := r.URL.Query().Get("id")
		vid, err := strconv.Atoi(idStr)
		if err != nil || vid <= 0 {
			errorResponse(w, http.StatusBadRequest, "无效的影片ID")
			return
		}
		if err := srv.store.DeleteUserFavorite(r.Context(), u.ID, vid); err != nil {
			errorResponse(w, http.StatusInternalServerError, err.Error())
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "已取消追剧收藏"})

	default:
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	}
}
