package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/url"
	"path/filepath"
	"strings"
	"sync"
	"time"

	_ "github.com/lib/pq"
	"golang.org/x/crypto/bcrypt"
	"video-collection-api/config"
	"video-collection-api/pkg/maccms"
)

type PostgresStore struct {
	*SQLContentStore
	*dbAdminHelper
	db        *sql.DB
	dsn       string
	upsertMu  sync.Mutex
	catMu     sync.RWMutex
	catCache  []Category
	lastCatAt time.Time
}

// 编译期断言：PostgresStore 实现数据库管理接口
var _ DBAdmin = (*PostgresStore)(nil)

// NewPostgresStore 初始化 PostgreSQL 存储并自动创建必要表与索引
func NewPostgresStore(dsn string) (*PostgresStore, error) {
	if err := ensureDatabaseExists(dsn); err != nil {
		return nil, fmt.Errorf("ensure database exists failed: %w", err)
	}

	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, fmt.Errorf("open postgres failed: %w", err)
	}

	db.SetMaxOpenConns(50)
	db.SetMaxIdleConns(10)
	db.SetConnMaxLifetime(5 * time.Minute)

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("ping postgres failed: %w", err)
	}

	s := &PostgresStore{db: db, dsn: dsn}
	host, dbName := parsePGDSN(dsn)
	s.dbAdminHelper = &dbAdminHelper{
		db:         db,
		engine:     "postgres",
		host:       host,
		dbName:     dbName,
		backupsDir: filepath.Join("data", "backups"),
	}
	if err := s.initSchema(); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("init postgres schema failed: %w", err)
	}
	s.SQLContentStore = &SQLContentStore{db: db}
	if err := s.SQLContentStore.initSchema(true); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("init content schema failed: %w", err)
	}

	ctx := context.Background()
	_ = s.InitDefaultCategories(ctx)
	_ = s.InitDefaultAdmin(ctx)

	return s, nil
}

// parsePGDSN 从 PostgreSQL 连接串中提取主机与库名，供数据库管理接口展示
func parsePGDSN(dsn string) (host, dbName string) {
	u, err := url.Parse(dsn)
	if err != nil {
		return "", ""
	}
	host = u.Host
	dbName = strings.TrimPrefix(u.Path, "/")
	return host, dbName
}

// ensureDatabaseExists 如果目标数据库不存在，自动连接系统库执行 CREATE DATABASE
func ensureDatabaseExists(dsn string) error {
	u, err := url.Parse(dsn)
	if err != nil {
		return nil // 无法解析则交由后续报错
	}

	dbName := strings.TrimPrefix(u.Path, "/")
	if dbName == "" || dbName == "postgres" {
		return nil
	}

	// 临时修改连接到 postgres 默认管理库
	adminURL := *u
	adminURL.Path = "/postgres"

	adminDB, err := sql.Open("postgres", adminURL.String())
	if err != nil {
		return err
	}
	defer adminDB.Close()

	var exists bool
	checkSQL := "SELECT EXISTS(SELECT 1 FROM pg_database WHERE datname = $1)"
	if err := adminDB.QueryRow(checkSQL, dbName).Scan(&exists); err == nil && !exists {
		// 创建数据库
		createSQL := fmt.Sprintf(`CREATE DATABASE "%s"`, dbName)
		if _, err := adminDB.Exec(createSQL); err != nil {
			return fmt.Errorf("create database %s failed: %w", dbName, err)
		}
	}

	return nil
}

func (s *PostgresStore) initSchema() error {
	schema := `
	CREATE TABLE IF NOT EXISTS users (
		id SERIAL PRIMARY KEY,
		username VARCHAR(64) UNIQUE NOT NULL,
		password_hash VARCHAR(255) NOT NULL,
		nickname VARCHAR(64) DEFAULT '',
		avatar VARCHAR(255) DEFAULT '',
		role VARCHAR(20) NOT NULL DEFAULT 'user',
		status INT NOT NULL DEFAULT 1,
		created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
	);

	CREATE TABLE IF NOT EXISTS settings (
		key VARCHAR(64) PRIMARY KEY,
		val TEXT NOT NULL,
		updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
	);

	CREATE TABLE IF NOT EXISTS sources (
		id VARCHAR(64) PRIMARY KEY,
		name VARCHAR(128) NOT NULL,
		api TEXT NOT NULL,
		type VARCHAR(32) NOT NULL DEFAULT 'json',
		enabled INT NOT NULL DEFAULT 1,
		collect_hours INT NOT NULL DEFAULT 24,
		page_limit INT NOT NULL DEFAULT 0,
		timeout_sec INT NOT NULL DEFAULT 15,
		retry_count INT NOT NULL DEFAULT 3,
		interval_ms INT NOT NULL DEFAULT 300,
		concurrency INT NOT NULL DEFAULT 2,
		category_mappings JSONB NOT NULL DEFAULT '[]'::jsonb,
		filter_rules JSONB NOT NULL DEFAULT '{}'::jsonb,
		created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
	);

	CREATE TABLE IF NOT EXISTS categories (
		id INT PRIMARY KEY,
		pid INT NOT NULL DEFAULT 0,
		name VARCHAR(64) NOT NULL,
		sort INT NOT NULL DEFAULT 0
	);

	CREATE TABLE IF NOT EXISTS videos (
		id SERIAL PRIMARY KEY,
		name VARCHAR(255) NOT NULL,
		sub_name VARCHAR(255) DEFAULT '',
		type_id INT NOT NULL DEFAULT 0,
		type_name VARCHAR(64) DEFAULT '',
		picture TEXT DEFAULT '',
		actor TEXT DEFAULT '',
		director TEXT DEFAULT '',
		area VARCHAR(64) DEFAULT '',
		language VARCHAR(64) DEFAULT '',
		year VARCHAR(16) DEFAULT '',
		remarks VARCHAR(128) DEFAULT '',
		content TEXT DEFAULT '',
		source_id VARCHAR(64) DEFAULT '',
		hits INT DEFAULT 0,
		created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		play_groups JSONB NOT NULL DEFAULT '[]'::jsonb
	);

	CREATE INDEX IF NOT EXISTS idx_videos_name ON videos(name);
	CREATE INDEX IF NOT EXISTS idx_videos_type_id ON videos(type_id);
	CREATE INDEX IF NOT EXISTS idx_videos_updated_at ON videos(updated_at DESC);
	CREATE INDEX IF NOT EXISTS idx_videos_play_groups ON videos USING GIN (play_groups);

	CREATE TABLE IF NOT EXISTS feedbacks (
		id SERIAL PRIMARY KEY,
		type VARCHAR(32) NOT NULL DEFAULT 'request',
		title VARCHAR(255) NOT NULL,
		content TEXT NOT NULL,
		contact VARCHAR(128) DEFAULT '',
		status VARCHAR(32) NOT NULL DEFAULT 'pending',
		reply TEXT DEFAULT '',
		created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
	);
	CREATE INDEX IF NOT EXISTS idx_feedbacks_status ON feedbacks(status);

	CREATE TABLE IF NOT EXISTS user_history (
		id SERIAL PRIMARY KEY,
		user_id INT NOT NULL,
		video_id INT NOT NULL,
		video_name VARCHAR(255) NOT NULL,
		picture TEXT DEFAULT '',
		episode_name VARCHAR(128) DEFAULT '',
		route_index INT DEFAULT 0,
		episode_index INT DEFAULT 0,
		play_time INT DEFAULT 0,
		duration INT DEFAULT 0,
		progress NUMERIC(5,2) DEFAULT 0,
		updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		UNIQUE(user_id, video_id)
	);
	CREATE INDEX IF NOT EXISTS idx_user_history_uid ON user_history(user_id, updated_at DESC);

	CREATE TABLE IF NOT EXISTS user_favorites (
		id SERIAL PRIMARY KEY,
		user_id INT NOT NULL,
		video_id INT NOT NULL,
		video_name VARCHAR(255) NOT NULL,
		picture TEXT DEFAULT '',
		remarks VARCHAR(128) DEFAULT '',
		created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		UNIQUE(user_id, video_id)
	);
	CREATE INDEX IF NOT EXISTS idx_user_fav_uid ON user_favorites(user_id, created_at DESC);
	`
	if _, err := s.db.Exec(schema); err != nil {
		return err
	}
	_, _ = s.db.Exec("ALTER TABLE videos ADD COLUMN IF NOT EXISTS hits INT DEFAULT 0;")
	_, _ = s.db.Exec("CREATE INDEX IF NOT EXISTS idx_videos_hits ON videos(hits DESC);")
	_, _ = s.db.Exec("ALTER TABLE user_history ADD COLUMN IF NOT EXISTS play_time INT DEFAULT 0;")
	return nil
}

func (s *PostgresStore) InitDefaultAdmin(ctx context.Context) error {
	var count int
	_ = s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM users").Scan(&count)
	if count > 0 {
		return nil
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(initialAdminPassword()), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	_, err = s.db.ExecContext(ctx, `
		INSERT INTO users (username, password_hash, nickname, role, status)
		VALUES ($1, $2, $3, $4, $5)
	`, "admin", string(hash), "超级管理员", "admin", 1)
	return err
}

func (s *PostgresStore) InitDefaultCategories(ctx context.Context) error {
	var count int
	_ = s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM categories").Scan(&count)
	if count > 0 {
		return nil
	}

	defaults := []Category{
		{ID: 1, PID: 0, Name: "电影", Sort: 1},
		{ID: 2, PID: 0, Name: "连续剧", Sort: 2},
		{ID: 3, PID: 0, Name: "综艺", Sort: 3},
		{ID: 4, PID: 0, Name: "动漫", Sort: 4},
		{ID: 5, PID: 1, Name: "动作片", Sort: 11},
		{ID: 6, PID: 1, Name: "喜剧片", Sort: 12},
		{ID: 7, PID: 1, Name: "爱情片", Sort: 13},
		{ID: 8, PID: 1, Name: "科幻片", Sort: 14},
		{ID: 9, PID: 1, Name: "恐怖片", Sort: 15},
		{ID: 10, PID: 1, Name: "剧情片", Sort: 16},
		{ID: 11, PID: 2, Name: "国产剧", Sort: 21},
		{ID: 12, PID: 2, Name: "港台剧", Sort: 22},
		{ID: 13, PID: 2, Name: "日韩剧", Sort: 23},
		{ID: 14, PID: 2, Name: "欧美剧", Sort: 24},
		{ID: 15, PID: 4, Name: "国产动漫", Sort: 41},
		{ID: 16, PID: 4, Name: "日韩动漫", Sort: 42},
		{ID: 17, PID: 4, Name: "欧美动漫", Sort: 43},
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	stmt, err := tx.PrepareContext(ctx, "INSERT INTO categories (id, pid, name, sort) VALUES ($1, $2, $3, $4) ON CONFLICT (id) DO NOTHING")
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, c := range defaults {
		if _, err := stmt.ExecContext(ctx, c.ID, c.PID, c.Name, c.Sort); err != nil {
			return err
		}
	}

	return tx.Commit()
}

// 用户增删改查
func (s *PostgresStore) GetUserByUsername(ctx context.Context, username string) (*User, error) {
	u := &User{}
	row := s.db.QueryRowContext(ctx, `
		SELECT id, username, password_hash, nickname, avatar, role, status, created_at, updated_at
		FROM users WHERE username = $1
	`, username)
	err := row.Scan(&u.ID, &u.Username, &u.PasswordHash, &u.Nickname, &u.Avatar, &u.Role, &u.Status, &u.CreatedAt, &u.UpdatedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return u, nil
}

func (s *PostgresStore) GetUserByID(ctx context.Context, id int) (*User, error) {
	u := &User{}
	row := s.db.QueryRowContext(ctx, `
		SELECT id, username, password_hash, nickname, avatar, role, status, created_at, updated_at
		FROM users WHERE id = $1
	`, id)
	err := row.Scan(&u.ID, &u.Username, &u.PasswordHash, &u.Nickname, &u.Avatar, &u.Role, &u.Status, &u.CreatedAt, &u.UpdatedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return u, nil
}

func (s *PostgresStore) ListUsers(ctx context.Context) ([]User, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, username, nickname, avatar, role, status, created_at, updated_at
		FROM users ORDER BY id ASC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []User
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Username, &u.Nickname, &u.Avatar, &u.Role, &u.Status, &u.CreatedAt, &u.UpdatedAt); err != nil {
			return nil, err
		}
		list = append(list, u)
	}
	return list, nil
}

func (s *PostgresStore) CreateUser(ctx context.Context, user *User) error {
	return s.db.QueryRowContext(ctx, `
		INSERT INTO users (username, password_hash, nickname, avatar, role, status, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())
		RETURNING id, created_at, updated_at
	`, user.Username, user.PasswordHash, user.Nickname, user.Avatar, user.Role, user.Status).
		Scan(&user.ID, &user.CreatedAt, &user.UpdatedAt)
}

func (s *PostgresStore) UpdateUser(ctx context.Context, user *User) error {
	if user.PasswordHash != "" {
		_, err := s.db.ExecContext(ctx, `
			UPDATE users SET nickname=$1, avatar=$2, role=$3, status=$4, password_hash=$5, updated_at=NOW()
			WHERE id=$6
		`, user.Nickname, user.Avatar, user.Role, user.Status, user.PasswordHash, user.ID)
		return err
	}
	_, err := s.db.ExecContext(ctx, `
		UPDATE users SET nickname=$1, avatar=$2, role=$3, status=$4, updated_at=NOW()
		WHERE id=$5
	`, user.Nickname, user.Avatar, user.Role, user.Status, user.ID)
	return err
}

func (s *PostgresStore) DeleteUser(ctx context.Context, id int) error {
	_, err := s.db.ExecContext(ctx, "DELETE FROM users WHERE id = $1", id)
	return err
}

// 系统设置
func (s *PostgresStore) GetSetting(ctx context.Context, key, defaultVal string) (string, error) {
	var val string
	err := s.db.QueryRowContext(ctx, "SELECT val FROM settings WHERE key = $1", key).Scan(&val)
	if err == sql.ErrNoRows {
		return defaultVal, nil
	}
	if err != nil {
		return defaultVal, err
	}
	return val, nil
}

func (s *PostgresStore) SetSetting(ctx context.Context, key, val string) error {
	query := `
		INSERT INTO settings (key, val, updated_at) VALUES ($1, $2, NOW())
		ON CONFLICT (key) DO UPDATE SET val = EXCLUDED.val, updated_at = NOW()
	`
	_, err := s.db.ExecContext(ctx, query, key, val)
	return err
}

func (s *PostgresStore) GetAllSettings(ctx context.Context) (map[string]string, error) {
	rows, err := s.db.QueryContext(ctx, "SELECT key, val FROM settings")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	res := make(map[string]string)
	for rows.Next() {
		var k, v string
		if err := rows.Scan(&k, &v); err == nil {
			res[k] = v
		}
	}
	return res, nil
}

func (s *PostgresStore) SetSettings(ctx context.Context, settings map[string]string) error {
	for k, v := range settings {
		if err := s.SetSetting(ctx, k, v); err != nil {
			return err
		}
	}
	return nil
}

// 采集源管理
func (s *PostgresStore) GetSources(ctx context.Context) ([]config.SourceConfig, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, name, api, type, enabled, collect_hours, page_limit, timeout_sec,
		       retry_count, interval_ms, concurrency, category_mappings, filter_rules
		FROM sources ORDER BY created_at DESC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []config.SourceConfig
	for rows.Next() {
		var src config.SourceConfig
		var enabledInt int
		var mappingsJSON, filterJSON string

		err := rows.Scan(
			&src.ID, &src.Name, &src.API, &src.Type, &enabledInt, &src.CollectHours,
			&src.PageLimit, &src.TimeoutSec, &src.RetryCount, &src.IntervalMs,
			&src.Concurrency, &mappingsJSON, &filterJSON,
		)
		if err != nil {
			return nil, err
		}
		src.Enabled = enabledInt == 1
		_ = json.Unmarshal([]byte(mappingsJSON), &src.CategoryMappings)
		_ = json.Unmarshal([]byte(filterJSON), &src.Filter)
		if src.Headers == nil && src.Filter.Headers != nil {
			src.Headers = src.Filter.Headers
		}
		if src.CustomParams == nil && src.Filter.CustomParams != nil {
			src.CustomParams = src.Filter.CustomParams
		}
		if src.CustomMapping.ListPath == "" && src.Filter.CustomMapping != nil {
			src.CustomMapping = *src.Filter.CustomMapping
		}
		list = append(list, src)
	}
	return list, nil
}

func (s *PostgresStore) GetSourceByID(ctx context.Context, id string) (*config.SourceConfig, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT id, name, api, type, enabled, collect_hours, page_limit, timeout_sec,
		       retry_count, interval_ms, concurrency, category_mappings, filter_rules
		FROM sources WHERE id = $1
	`, id)

	var src config.SourceConfig
	var enabledInt int
	var mappingsJSON, filterJSON string

	err := row.Scan(
		&src.ID, &src.Name, &src.API, &src.Type, &enabledInt, &src.CollectHours,
		&src.PageLimit, &src.TimeoutSec, &src.RetryCount, &src.IntervalMs,
		&src.Concurrency, &mappingsJSON, &filterJSON,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	src.Enabled = enabledInt == 1
	_ = json.Unmarshal([]byte(mappingsJSON), &src.CategoryMappings)
	_ = json.Unmarshal([]byte(filterJSON), &src.Filter)
	if src.Headers == nil && src.Filter.Headers != nil {
		src.Headers = src.Filter.Headers
	}
	if src.CustomParams == nil && src.Filter.CustomParams != nil {
		src.CustomParams = src.Filter.CustomParams
	}
	if src.CustomMapping.ListPath == "" && src.Filter.CustomMapping != nil {
		src.CustomMapping = *src.Filter.CustomMapping
	}
	return &src, nil
}

func (s *PostgresStore) SaveSource(ctx context.Context, src config.SourceConfig) error {
	if src.Headers != nil {
		src.Filter.Headers = src.Headers
	}
	if src.CustomParams != nil {
		src.Filter.CustomParams = src.CustomParams
	}
	src.Filter.CustomMapping = &src.CustomMapping

	mappingsBytes, _ := json.Marshal(src.CategoryMappings)
	filterBytes, _ := json.Marshal(src.Filter)
	enabledInt := 0
	if src.Enabled {
		enabledInt = 1
	}

	query := `
		INSERT INTO sources (
			id, name, api, type, enabled, collect_hours, page_limit, timeout_sec,
			retry_count, interval_ms, concurrency, category_mappings, filter_rules, updated_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, NOW())
		ON CONFLICT (id) DO UPDATE SET
			name = EXCLUDED.name,
			api = EXCLUDED.api,
			type = EXCLUDED.type,
			enabled = EXCLUDED.enabled,
			collect_hours = EXCLUDED.collect_hours,
			page_limit = EXCLUDED.page_limit,
			timeout_sec = EXCLUDED.timeout_sec,
			retry_count = EXCLUDED.retry_count,
			interval_ms = EXCLUDED.interval_ms,
			concurrency = EXCLUDED.concurrency,
			category_mappings = EXCLUDED.category_mappings,
			filter_rules = EXCLUDED.filter_rules,
			updated_at = NOW()
	`
	_, err := s.db.ExecContext(ctx, query,
		src.ID, src.Name, src.API, src.Type, enabledInt, src.CollectHours,
		src.PageLimit, src.TimeoutSec, src.RetryCount, src.IntervalMs,
		src.Concurrency, string(mappingsBytes), string(filterBytes),
	)
	if err != nil {
		return err
	}

	// 级联同步更新该采集节点下已入库所有历史视频的线路名称与展示来源
	if src.Name != "" && src.ID != "" {
		updateVideosSQL := `
			UPDATE videos
			SET play_groups = (
				SELECT COALESCE(jsonb_agg(
					CASE
						WHEN elem->>'source_id' = $1 THEN
							jsonb_set(
								jsonb_set(
									jsonb_set(elem, '{source_name}', to_jsonb($2::text)),
									'{server}', to_jsonb($2::text)
								),
								'{from}', to_jsonb($2 || ' (' || COALESCE(elem->>'player_code', '') || ')')
							)
						ELSE elem
					END
				), '[]'::jsonb)
				FROM jsonb_array_elements(play_groups) AS elem
			),
			updated_at = NOW()
			WHERE play_groups::text LIKE '%' || $1 || '%';
		`
		_, _ = s.db.ExecContext(ctx, updateVideosSQL, src.ID, src.Name)
	}
	return nil
}

func (s *PostgresStore) DeleteSource(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx, "DELETE FROM sources WHERE id = $1", id)
	return err
}

// 分类管理与智能推导
func (s *PostgresStore) GetCategories(ctx context.Context) ([]Category, error) {
	s.catMu.RLock()
	if len(s.catCache) > 0 && time.Since(s.lastCatAt) < 1*time.Minute {
		defer s.catMu.RUnlock()
		return s.catCache, nil
	}
	s.catMu.RUnlock()

	rows, err := s.db.QueryContext(ctx, "SELECT id, pid, name, sort FROM categories ORDER BY sort ASC, id ASC")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []Category
	for rows.Next() {
		var c Category
		if err := rows.Scan(&c.ID, &c.PID, &c.Name, &c.Sort); err != nil {
			return nil, err
		}
		list = append(list, c)
	}

	s.catMu.Lock()
	s.catCache = list
	s.lastCatAt = time.Now()
	s.catMu.Unlock()

	return list, nil
}

// GetCategoryFamilyIDs 获取指定分类及其所有子孙分类ID (用于树形级联查询)
func (s *PostgresStore) GetCategoryFamilyIDs(ctx context.Context, catID int) ([]int, error) {
	allCats, err := s.GetCategories(ctx)
	if err != nil {
		return []int{catID}, err
	}

	idMap := make(map[int]bool)
	idMap[catID] = true

	// 广度优先寻找子分类
	changed := true
	for changed {
		changed = false
		for _, c := range allCats {
			if idMap[c.PID] && !idMap[c.ID] {
				idMap[c.ID] = true
				changed = true
			}
		}
	}

	res := make([]int, 0, len(idMap))
	for id := range idMap {
		res = append(res, id)
	}
	return res, nil
}

// matchCategorySmart 智能匹配分类名称
func (s *PostgresStore) matchCategorySmart(ctx context.Context, srcName string) (int, string) {
	if strings.TrimSpace(srcName) == "" {
		return 0, ""
	}
	cats, err := s.GetCategories(ctx)
	if err != nil {
		return 0, srcName
	}

	// 1. 完全精确匹配
	for _, c := range cats {
		if c.Name == srcName {
			return c.ID, c.Name
		}
	}

	// 2. 包含匹配 (如 "欧美动作片" -> "动作片")
	for _, c := range cats {
		if strings.Contains(srcName, c.Name) || strings.Contains(c.Name, srcName) {
			return c.ID, c.Name
		}
	}

	// 3. 常见大词兜底
	if strings.Contains(srcName, "影") {
		return 1, "电影"
	}
	if strings.Contains(srcName, "剧") {
		return 2, "连续剧"
	}
	if strings.Contains(srcName, "漫") {
		return 4, "动漫"
	}
	if strings.Contains(srcName, "综") {
		return 3, "综艺"
	}

	return 0, srcName
}

// UpsertVideo 写入或更新视频数据（深度支持 PostgreSQL 原生 JSONB 与多采集节点独立聚合存储）
func (s *PostgresStore) UpsertVideo(ctx context.Context, sourceID string, vod *maccms.CleanedVod) (int, error) {
	// 并发采集写锁保护，防止多采集点同时采集同一视频时产生竞态同名记录
	s.upsertMu.Lock()
	defer s.upsertMu.Unlock()

	// 智能分类归纳修复：若未分配分类ID，自动从本地标准分类库智能匹配
	if vod.TargetTypeID <= 0 {
		matchedID, matchedName := s.matchCategorySmart(ctx, vod.SourceTypeName)
		if matchedID > 0 {
			vod.TargetTypeID = matchedID
			vod.TargetTypeName = matchedName
		}
	}

	recordTime := parseVodTime(vod.UpdateTime)

	// 确保每个 PlayGroup 都带有节点 ID 与名称
	for i := range vod.PlayGroups {
		if vod.PlayGroups[i].SourceID == "" {
			vod.PlayGroups[i].SourceID = sourceID
		}
		if vod.PlayGroups[i].SourceName == "" {
			vod.PlayGroups[i].SourceName = vod.SourceName
			if vod.PlayGroups[i].SourceName == "" {
				vod.PlayGroups[i].SourceName = sourceID
			}
		}
		if vod.PlayGroups[i].From == "" {
			vod.PlayGroups[i].From = fmt.Sprintf("%s (%s)", vod.PlayGroups[i].SourceName, vod.PlayGroups[i].PlayerCode)
		}
		if vod.PlayGroups[i].Server == "" || vod.PlayGroups[i].Server == "no" {
			vod.PlayGroups[i].Server = vod.PlayGroups[i].SourceName
		}
	}

	// 查询是否存在同名视频
	var videoID int
	var existingSourceID string
	var existingPlayGroupsJSON []byte
	queryExisting := `SELECT id, source_id, play_groups FROM videos WHERE name = $1 LIMIT 1`
	err := s.db.QueryRowContext(ctx, queryExisting, vod.Name).Scan(&videoID, &existingSourceID, &existingPlayGroupsJSON)

	if err == sql.ErrNoRows {
		// 插入全新视频
		newGroupsJSON, _ := json.Marshal(vod.PlayGroups)
		insertSQL := `
			INSERT INTO videos (
				name, sub_name, type_id, type_name, picture, actor, director,
				area, language, year, remarks, content, source_id, created_at, updated_at, play_groups
			) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16::jsonb)
			RETURNING id
		`
		err := s.db.QueryRowContext(ctx, insertSQL,
			vod.Name, vod.SubName, vod.TargetTypeID, vod.TargetTypeName, vod.Picture,
			vod.Actor, vod.Director, vod.Area, vod.Language, vod.Year,
			vod.Remarks, vod.Content, sourceID, recordTime, recordTime, string(newGroupsJSON),
		).Scan(&videoID)
		return videoID, err
	} else if err != nil {
		return 0, err
	}

	// 已存在：多节点线路聚合（保留来自不同采集节点的所有播放线路）
	var mergedGroups []maccms.PlayGroup
	_ = json.Unmarshal(existingPlayGroupsJSON, &mergedGroups)

	for _, incoming := range vod.PlayGroups {
		sID := strings.ToLower(strings.TrimSpace(incoming.SourceID))
		sName := strings.TrimSpace(incoming.SourceName)
		pCode := strings.ToLower(strings.TrimSpace(incoming.PlayerCode))

		matchedIdx := -1

		// 1. 优先精确匹配：同 source_id 且同 player_code
		for i, g := range mergedGroups {
			existingSID := strings.ToLower(strings.TrimSpace(g.SourceID))
			existingPCode := strings.ToLower(strings.TrimSpace(g.PlayerCode))
			if existingSID != "" && existingSID == sID && existingPCode == pCode {
				matchedIdx = i
				break
			}
		}

		// 2. 来源名称匹配：source_name 或 server 一致且 player_code 相同
		if matchedIdx == -1 && sName != "" {
			for i, g := range mergedGroups {
				existingName := strings.TrimSpace(g.SourceName)
				existingServer := strings.TrimSpace(g.Server)
				existingPCode := strings.ToLower(strings.TrimSpace(g.PlayerCode))
				if existingPCode == pCode && (existingName == sName || (existingServer != "" && existingServer != "no" && existingServer == sName)) {
					matchedIdx = i
					break
				}
			}
		}

		// 3. 历史兼容匹配：旧数据 source_id 为空，但同 player_code（认领升级历史无 source_id 线路）
		if matchedIdx == -1 {
			for i, g := range mergedGroups {
				existingSID := strings.ToLower(strings.TrimSpace(g.SourceID))
				existingPCode := strings.ToLower(strings.TrimSpace(g.PlayerCode))
				if existingSID == "" && existingPCode == pCode {
					matchedIdx = i
					break
				}
			}
		}

		if matchedIdx >= 0 {
			// 同节点线路：更新剧集、线路名称及最新状态
			mergedGroups[matchedIdx] = incoming
		} else {
			// 来自全新采集节点或新线路：独立追加，完整保留多节点数据
			mergedGroups = append(mergedGroups, incoming)
		}
	}

	// 保底去重：同一节点（source_id:player_code 或相同展示来源）若存在多条，保留剧集最完整的一条
	dedupMap := make(map[string]maccms.PlayGroup)
	var dedupOrder []string
	for _, g := range mergedGroups {
		k := strings.ToLower(strings.TrimSpace(g.SourceID)) + ":" + strings.ToLower(strings.TrimSpace(g.PlayerCode))
		if strings.TrimSpace(g.SourceID) == "" {
			k = "default:" + strings.ToLower(strings.TrimSpace(g.PlayerCode))
		}
		if existing, exists := dedupMap[k]; exists {
			if len(g.Episodes) >= len(existing.Episodes) {
				dedupMap[k] = g
			}
		} else {
			dedupMap[k] = g
			dedupOrder = append(dedupOrder, k)
		}
	}
	finalGroups := make([]maccms.PlayGroup, 0, len(dedupOrder))
	for _, k := range dedupOrder {
		finalGroups = append(finalGroups, dedupMap[k])
	}
	mergedGroups = finalGroups

	mergedBytes, _ := json.Marshal(mergedGroups)

	// 合并记录所有提供该视频的采集节点 ID
	newSourceID := existingSourceID
	if sourceID != "" {
		existingParts := strings.Split(existingSourceID, ",")
		hasSource := false
		for _, part := range existingParts {
			if strings.TrimSpace(part) == sourceID {
				hasSource = true
				break
			}
		}
		if !hasSource {
			if strings.TrimSpace(existingSourceID) == "" {
				newSourceID = sourceID
			} else {
				newSourceID = existingSourceID + "," + sourceID
			}
		}
	}

	updateSQL := `
		UPDATE videos SET
			sub_name = CASE WHEN $1 != '' THEN $1 ELSE sub_name END,
			picture = CASE WHEN $2 != '' THEN $2 ELSE picture END,
			remarks = CASE WHEN $3 != '' THEN $3 ELSE remarks END,
			content = CASE WHEN $4 != '' THEN $4 ELSE content END,
			type_id = CASE WHEN $5 > 0 THEN $5 ELSE type_id END,
			type_name = CASE WHEN $6 != '' THEN $6 ELSE type_name END,
			source_id = $7,
			play_groups = $8::jsonb,
			updated_at = $9
		WHERE id = $10
	`
	_, err = s.db.ExecContext(ctx, updateSQL,
		vod.SubName, vod.Picture, vod.Remarks, vod.Content,
		vod.TargetTypeID, vod.TargetTypeName, newSourceID,
		string(mergedBytes), recordTime, videoID,
	)
	return videoID, err
}

// QueryVideos 视频多维检索 (支持树形级联分类展开)
func (s *PostgresStore) QueryVideos(ctx context.Context, q VideoQuery) ([]VideoRecord, int, error) {
	var whereClauses []string
	var args []any
	argIndex := 1

	// 分类树级联展开：若用户筛选分类，自动展开为该分类及其所有子分类集合
	if q.TypeID > 0 {
		familyIDs, _ := s.GetCategoryFamilyIDs(ctx, q.TypeID)
		if len(familyIDs) == 1 {
			whereClauses = append(whereClauses, fmt.Sprintf("v.type_id = $%d", argIndex))
			args = append(args, familyIDs[0])
			argIndex++
		} else if len(familyIDs) > 1 {
			placeholders := make([]string, len(familyIDs))
			for i, fid := range familyIDs {
				placeholders[i] = fmt.Sprintf("$%d", argIndex)
				args = append(args, fid)
				argIndex++
			}
			whereClauses = append(whereClauses, fmt.Sprintf("v.type_id IN (%s)", strings.Join(placeholders, ",")))
		}
	}

	if q.Hours > 0 {
		whereClauses = append(whereClauses, fmt.Sprintf("v.updated_at >= NOW() - INTERVAL '%d hours'", q.Hours))
	}

	if q.Area != "" {
		if q.Area == "大陆" {
			whereClauses = append(whereClauses, fmt.Sprintf("(v.area ILIKE $%d OR v.area ILIKE $%d OR v.type_name ILIKE $%d)", argIndex, argIndex+1, argIndex+2))
			args = append(args, "%大陆%", "%中国%", "%国产%")
			argIndex += 3
		} else if q.Area == "日本" {
			whereClauses = append(whereClauses, fmt.Sprintf("(v.area ILIKE $%d OR v.type_name ILIKE $%d)", argIndex, argIndex+1))
			args = append(args, "%日本%", "%日韩%")
			argIndex += 2
		} else if q.Area == "欧美" {
			whereClauses = append(whereClauses, fmt.Sprintf("(v.area ILIKE $%d OR v.type_name ILIKE $%d)", argIndex, argIndex+1))
			args = append(args, "%欧美%", "%欧美%")
			argIndex += 2
		} else {
			whereClauses = append(whereClauses, fmt.Sprintf("v.area ILIKE $%d", argIndex))
			args = append(args, "%"+q.Area+"%")
			argIndex++
		}
	}

	if q.Year != "" {
		if q.Year == "更早" {
			whereClauses = append(whereClauses, "NULLIF(regexp_replace(v.year, '\\D', '', 'g'), '')::int < 2020")
		} else {
			whereClauses = append(whereClauses, fmt.Sprintf("v.year LIKE $%d", argIndex))
			args = append(args, "%"+q.Year+"%")
			argIndex++
		}
	}

	if q.NameKeyword != "" {
		whereClauses = append(whereClauses, fmt.Sprintf("(v.name ILIKE $%d OR v.sub_name ILIKE $%d)", argIndex, argIndex+1))
		args = append(args, "%"+q.NameKeyword+"%", "%"+q.NameKeyword+"%")
		argIndex += 2
	}

	if q.Keyword != "" {
		whereClauses = append(whereClauses, fmt.Sprintf("(v.name ILIKE $%d OR v.sub_name ILIKE $%d OR v.actor ILIKE $%d OR v.content ILIKE $%d OR v.remarks ILIKE $%d)", argIndex, argIndex, argIndex, argIndex, argIndex))
		args = append(args, "%"+q.Keyword+"%")
		argIndex++
	}

	if len(q.IDs) > 0 {
		placeholders := make([]string, len(q.IDs))
		for i, id := range q.IDs {
			placeholders[i] = fmt.Sprintf("$%d", argIndex)
			args = append(args, id)
			argIndex++
		}
		whereClauses = append(whereClauses, fmt.Sprintf("v.id IN (%s)", strings.Join(placeholders, ",")))
	}

	if len(q.ExcludeIDs) > 0 {
		placeholders := make([]string, len(q.ExcludeIDs))
		for i, id := range q.ExcludeIDs {
			placeholders[i] = fmt.Sprintf("$%d", argIndex)
			args = append(args, id)
			argIndex++
		}
		whereClauses = append(whereClauses, fmt.Sprintf("v.id NOT IN (%s)", strings.Join(placeholders, ",")))
	}

	whereSQL := ""
	if len(whereClauses) > 0 {
		whereSQL = " WHERE " + strings.Join(whereClauses, " AND ")
	}

	// 统计总数
	countSQL := "SELECT COUNT(*) FROM videos v" + whereSQL
	var total int
	err := s.db.QueryRowContext(ctx, countSQL, args...).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	limit := q.PageSize
	if limit <= 0 {
		limit = 20
	}
	offset := (q.Page - 1) * limit
	if offset < 0 {
		offset = 0
	}

	orderField := "v.updated_at"
	orderDir := "DESC"
	if q.OrderBy == "hits" || q.OrderBy == "score" {
		orderField = "COALESCE(v.hits, 0)"
	} else if q.OrderBy == "id" {
		orderField = "v.id"
	}
	if !q.OrderDesc && q.OrderBy != "" {
		orderDir = "ASC"
	}

	querySQL := fmt.Sprintf(`
		SELECT v.id, v.name, v.sub_name, v.type_id, v.type_name, v.picture,
		       v.actor, v.director, v.area, v.language, v.year, v.remarks,
		       v.content, v.source_id, COALESCE(v.hits, 0), v.created_at, v.updated_at, v.play_groups
		FROM videos v
		%s
		ORDER BY %s %s, v.updated_at DESC
		LIMIT %d OFFSET %d
	`, whereSQL, orderField, orderDir, limit, offset)

	rows, err := s.db.QueryContext(ctx, querySQL, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var records []VideoRecord
	for rows.Next() {
		var rec VideoRecord
		var playJSON []byte
		err := rows.Scan(
			&rec.ID, &rec.Name, &rec.SubName, &rec.TypeID, &rec.TypeName, &rec.Picture,
			&rec.Actor, &rec.Director, &rec.Area, &rec.Language, &rec.Year, &rec.Remarks,
			&rec.Content, &rec.SourceID, &rec.Hits, &rec.CreatedAt, &rec.UpdatedAt, &playJSON,
		)
		if err != nil {
			return nil, 0, err
		}
		_ = json.Unmarshal(playJSON, &rec.PlayGroups)
		rec.FillCompatFields()
		records = append(records, rec)
	}

	return records, total, nil
}

func (s *PostgresStore) GetVideoByID(ctx context.Context, id int) (*VideoRecord, error) {
	query, _, err := s.QueryVideos(ctx, VideoQuery{IDs: []int{id}, Page: 1, PageSize: 1})
	if err != nil {
		return nil, err
	}
	if len(query) == 0 {
		return nil, nil
	}
	return &query[0], nil
}

func (s *PostgresStore) SaveVideoManual(ctx context.Context, v *VideoRecord) (int, error) {
	now := time.Now()
	if v.CreatedAt.IsZero() {
		v.CreatedAt = now
	}
	v.UpdatedAt = now

	if v.TypeID > 0 && v.TypeName == "" {
		cats, _ := s.GetCategories(ctx)
		for _, c := range cats {
			if c.ID == v.TypeID {
				v.TypeName = c.Name
				break
			}
		}
	}

	playGroupsJSON, _ := json.Marshal(v.PlayGroups)

	if v.ID > 0 {
		updateSQL := `
			UPDATE videos SET
				name = $1, sub_name = $2, type_id = $3, type_name = $4, picture = $5,
				actor = $6, director = $7, area = $8, language = $9, year = $10,
				remarks = $11, content = $12, play_groups = $13::jsonb, updated_at = $14
			WHERE id = $15
		`
		_, err := s.db.ExecContext(ctx, updateSQL,
			v.Name, v.SubName, v.TypeID, v.TypeName, v.Picture,
			v.Actor, v.Director, v.Area, v.Language, v.Year,
			v.Remarks, v.Content, string(playGroupsJSON), v.UpdatedAt, v.ID,
		)
		if err != nil {
			return 0, err
		}
		return v.ID, nil
	} else {
		insertSQL := `
			INSERT INTO videos (
				name, sub_name, type_id, type_name, picture, actor, director,
				area, language, year, remarks, content, source_id, hits, play_groups, created_at, updated_at
			) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, 0, $14::jsonb, $15, $16)
			RETURNING id
		`
		var newID int
		err := s.db.QueryRowContext(ctx, insertSQL,
			v.Name, v.SubName, v.TypeID, v.TypeName, v.Picture, v.Actor, v.Director,
			v.Area, v.Language, v.Year, v.Remarks, v.Content, v.SourceID,
			string(playGroupsJSON), v.CreatedAt, v.UpdatedAt,
		).Scan(&newID)
		if err != nil {
			return 0, err
		}
		v.ID = newID
		return newID, nil
	}
}

func (s *PostgresStore) DeleteVideo(ctx context.Context, id int) error {
	return s.SQLContentStore.deleteVideosWithComments(ctx, []int{id})
}
func (s *PostgresStore) BatchDeleteVideos(ctx context.Context, ids []int) error {
	return s.SQLContentStore.deleteVideosWithComments(ctx, ids)
}

func (s *PostgresStore) IncrementVideoHits(ctx context.Context, id int) error {
	_, err := s.db.ExecContext(ctx, "UPDATE videos SET hits = COALESCE(hits, 0) + 1 WHERE id = $1", id)
	return err
}

func (s *PostgresStore) GetHotVideos(ctx context.Context, typeID int, limit int) ([]VideoRecord, error) {
	if limit <= 0 {
		limit = 10
	}
	recs, _, err := s.QueryVideos(ctx, VideoQuery{
		TypeID:    typeID,
		Page:      1,
		PageSize:  limit,
		OrderBy:   "hits",
		OrderDesc: true,
	})
	return recs, err
}

// 用户留言与求片报错反馈
func (s *PostgresStore) CreateFeedback(ctx context.Context, fb *Feedback) error {
	fb.CreatedAt = time.Now()
	fb.UpdatedAt = time.Now()
	if fb.Status == "" {
		fb.Status = "pending"
	}
	query := `
		INSERT INTO feedbacks (type, title, content, contact, status, reply, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING id
	`
	return s.db.QueryRowContext(ctx, query, fb.Type, fb.Title, fb.Content, fb.Contact, fb.Status, fb.Reply, fb.CreatedAt, fb.UpdatedAt).Scan(&fb.ID)
}

func (s *PostgresStore) ListFeedbacks(ctx context.Context, page, pageSize int, status, fbType string) ([]Feedback, int, error) {
	if page <= 0 {
		page = 1
	}
	if pageSize <= 0 {
		pageSize = 20
	}
	var whereClauses []string
	var args []any
	argIdx := 1
	if status != "" {
		whereClauses = append(whereClauses, fmt.Sprintf("status = $%d", argIdx))
		args = append(args, status)
		argIdx++
	}
	if fbType != "" {
		whereClauses = append(whereClauses, fmt.Sprintf("type = $%d", argIdx))
		args = append(args, fbType)
		argIdx++
	}
	whereSQL := ""
	if len(whereClauses) > 0 {
		whereSQL = " WHERE " + strings.Join(whereClauses, " AND ")
	}

	countSQL := "SELECT COUNT(*) FROM feedbacks" + whereSQL
	var total int
	if err := s.db.QueryRowContext(ctx, countSQL, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * pageSize
	querySQL := fmt.Sprintf(`
		SELECT id, type, title, content, contact, status, reply, created_at, updated_at
		FROM feedbacks
		%s
		ORDER BY created_at DESC
		LIMIT %d OFFSET %d
	`, whereSQL, pageSize, offset)

	rows, err := s.db.QueryContext(ctx, querySQL, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var list []Feedback
	for rows.Next() {
		var f Feedback
		if err := rows.Scan(&f.ID, &f.Type, &f.Title, &f.Content, &f.Contact, &f.Status, &f.Reply, &f.CreatedAt, &f.UpdatedAt); err == nil {
			list = append(list, f)
		}
	}
	return list, total, nil
}

func (s *PostgresStore) UpdateFeedback(ctx context.Context, id int, status, reply string) error {
	query := `UPDATE feedbacks SET status = $1, reply = $2, updated_at = NOW() WHERE id = $3`
	_, err := s.db.ExecContext(ctx, query, status, reply, id)
	return err
}

func (s *PostgresStore) DeleteFeedback(ctx context.Context, id int) error {
	_, err := s.db.ExecContext(ctx, "DELETE FROM feedbacks WHERE id = $1", id)
	return err
}

func (s *PostgresStore) GetStats(ctx context.Context) (*StatsInfo, error) {
	stats := &StatsInfo{}

	_ = s.db.QueryRowContext(ctx, "SELECT COUNT(*), COALESCE(SUM(enabled), 0) FROM sources").
		Scan(&stats.TotalSources, &stats.ActiveSources)

	_ = s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM videos").Scan(&stats.TotalVideos)

	_ = s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM videos WHERE updated_at >= NOW() - INTERVAL '24 hours'").
		Scan(&stats.TodayUpdated)

	// 计算总播放组数量
	_ = s.db.QueryRowContext(ctx, "SELECT COALESCE(SUM(jsonb_array_length(play_groups)), 0) FROM videos").
		Scan(&stats.TotalPlayCount)

	_ = s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM users").Scan(&stats.TotalUsers)

	_ = s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM feedbacks").Scan(&stats.TotalFeedbacks)

	return stats, nil
}

// SaveUserHistory 保存/更新用户播放历史与进度 (UPSERT)
func (s *PostgresStore) SaveUserHistory(ctx context.Context, item *UserHistoryItem) error {
	query := `
	INSERT INTO user_history (
		user_id, video_id, video_name, picture, episode_name,
		route_index, episode_index, play_time, duration, progress, updated_at
	) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW())
	ON CONFLICT(user_id, video_id) DO UPDATE SET
		video_name = EXCLUDED.video_name,
		picture = EXCLUDED.picture,
		episode_name = EXCLUDED.episode_name,
		route_index = EXCLUDED.route_index,
		episode_index = EXCLUDED.episode_index,
		play_time = EXCLUDED.play_time,
		duration = EXCLUDED.duration,
		progress = EXCLUDED.progress,
		updated_at = NOW();
	`
	_, err := s.db.ExecContext(ctx, query,
		item.UserID, item.VideoID, item.VideoName, item.Picture, item.EpisodeName,
		item.RouteIndex, item.EpisodeIndex, item.CurrentTime, item.Duration, item.Progress,
	)
	return err
}

// GetUserHistory 获取用户的云端播放历史
func (s *PostgresStore) GetUserHistory(ctx context.Context, userID int, limit int) ([]UserHistoryItem, error) {
	if limit <= 0 {
		limit = 50
	}
	query := `
	SELECT id, user_id, video_id, video_name, picture, episode_name,
	       route_index, episode_index, play_time, duration, progress, updated_at
	FROM user_history
	WHERE user_id = $1
	ORDER BY updated_at DESC
	LIMIT $2
	`
	rows, err := s.db.QueryContext(ctx, query, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []UserHistoryItem
	for rows.Next() {
		var it UserHistoryItem
		if err := rows.Scan(
			&it.ID, &it.UserID, &it.VideoID, &it.VideoName, &it.Picture, &it.EpisodeName,
			&it.RouteIndex, &it.EpisodeIndex, &it.CurrentTime, &it.Duration, &it.Progress, &it.UpdatedAt,
		); err != nil {
			return nil, err
		}
		list = append(list, it)
	}
	return list, nil
}

// DeleteUserHistory 删除单条播放历史
func (s *PostgresStore) DeleteUserHistory(ctx context.Context, userID int, videoID int) error {
	_, err := s.db.ExecContext(ctx, "DELETE FROM user_history WHERE user_id = $1 AND video_id = $2", userID, videoID)
	return err
}

// ClearUserHistory 清空用户全部播放历史
func (s *PostgresStore) ClearUserHistory(ctx context.Context, userID int) error {
	_, err := s.db.ExecContext(ctx, "DELETE FROM user_history WHERE user_id = $1", userID)
	return err
}

// SaveUserFavorite 保存追剧收藏
func (s *PostgresStore) SaveUserFavorite(ctx context.Context, item *UserFavoriteItem) error {
	query := `
	INSERT INTO user_favorites (user_id, video_id, video_name, picture, remarks, created_at)
	VALUES ($1, $2, $3, $4, $5, NOW())
	ON CONFLICT(user_id, video_id) DO UPDATE SET
		video_name = EXCLUDED.video_name,
		picture = EXCLUDED.picture,
		remarks = EXCLUDED.remarks,
		created_at = NOW();
	`
	_, err := s.db.ExecContext(ctx, query, item.UserID, item.VideoID, item.VideoName, item.Picture, item.Remarks)
	return err
}

// GetUserFavorites 获取用户追剧收藏列表
func (s *PostgresStore) GetUserFavorites(ctx context.Context, userID int, limit int) ([]UserFavoriteItem, error) {
	if limit <= 0 {
		limit = 100
	}
	query := `
	SELECT id, user_id, video_id, video_name, picture, remarks, created_at
	FROM user_favorites
	WHERE user_id = $1
	ORDER BY created_at DESC
	LIMIT $2
	`
	rows, err := s.db.QueryContext(ctx, query, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []UserFavoriteItem
	for rows.Next() {
		var it UserFavoriteItem
		if err := rows.Scan(&it.ID, &it.UserID, &it.VideoID, &it.VideoName, &it.Picture, &it.Remarks, &it.CreatedAt); err != nil {
			return nil, err
		}
		list = append(list, it)
	}
	return list, nil
}

// DeleteUserFavorite 取消追剧收藏
func (s *PostgresStore) DeleteUserFavorite(ctx context.Context, userID int, videoID int) error {
	_, err := s.db.ExecContext(ctx, "DELETE FROM user_favorites WHERE user_id = $1 AND video_id = $2", userID, videoID)
	return err
}
