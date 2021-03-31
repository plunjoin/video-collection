package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/bcrypt"
	_ "modernc.org/sqlite"
	"video-collection-api/config"
	"video-collection-api/pkg/maccms"
)

type SQLiteStore struct {
	db        *sql.DB
	upsertMu  sync.Mutex
	catMu     sync.RWMutex
	catCache  []Category
	lastCatAt time.Time
}

// NewSQLiteStore 初始化 SQLite 存储
func NewSQLiteStore(dbPath string) (*SQLiteStore, error) {
	dir := filepath.Dir(dbPath)
	if dir != "" && dir != "." {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return nil, fmt.Errorf("create db dir failed: %w", err)
		}
	}

	db, err := sql.Open("sqlite", dbPath+"?_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)")
	if err != nil {
		return nil, fmt.Errorf("open sqlite failed: %w", err)
	}

	db.SetMaxOpenConns(1)

	s := &SQLiteStore{db: db}
	if err := s.initSchema(); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("init schema failed: %w", err)
	}

	ctx := context.Background()
	_ = s.InitDefaultCategories(ctx)
	_ = s.InitDefaultAdmin(ctx)

	return s, nil
}

func (s *SQLiteStore) initSchema() error {
	schema := `
	CREATE TABLE IF NOT EXISTS users (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		username TEXT UNIQUE NOT NULL,
		password_hash TEXT NOT NULL,
		nickname TEXT DEFAULT '',
		avatar TEXT DEFAULT '',
		role TEXT NOT NULL DEFAULT 'user',
		status INTEGER NOT NULL DEFAULT 1,
		created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS settings (
		key TEXT PRIMARY KEY,
		val TEXT NOT NULL,
		updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS sources (
		id TEXT PRIMARY KEY,
		name TEXT NOT NULL,
		api TEXT NOT NULL,
		type TEXT NOT NULL DEFAULT 'json',
		enabled INTEGER NOT NULL DEFAULT 1,
		collect_hours INTEGER NOT NULL DEFAULT 24,
		page_limit INTEGER NOT NULL DEFAULT 0,
		timeout_sec INTEGER NOT NULL DEFAULT 15,
		retry_count INTEGER NOT NULL DEFAULT 3,
		interval_ms INTEGER NOT NULL DEFAULT 300,
		concurrency INTEGER NOT NULL DEFAULT 2,
		category_mappings TEXT NOT NULL DEFAULT '[]',
		filter_rules TEXT NOT NULL DEFAULT '{}',
		created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS categories (
		id INTEGER PRIMARY KEY,
		pid INTEGER NOT NULL DEFAULT 0,
		name TEXT NOT NULL,
		sort INTEGER NOT NULL DEFAULT 0
	);

	CREATE TABLE IF NOT EXISTS videos (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT NOT NULL,
		sub_name TEXT DEFAULT '',
		type_id INTEGER NOT NULL DEFAULT 0,
		type_name TEXT NOT NULL DEFAULT '',
		picture TEXT DEFAULT '',
		actor TEXT DEFAULT '',
		director TEXT DEFAULT '',
		area TEXT DEFAULT '',
		language TEXT DEFAULT '',
		year TEXT DEFAULT '',
		remarks TEXT DEFAULT '',
		content TEXT DEFAULT '',
		source_id TEXT DEFAULT '',
		hits INTEGER DEFAULT 0,
		created_at DATETIME NOT NULL,
		updated_at DATETIME NOT NULL
	);

	CREATE INDEX IF NOT EXISTS idx_videos_name ON videos(name);
	CREATE INDEX IF NOT EXISTS idx_videos_type_id ON videos(type_id);
	CREATE INDEX IF NOT EXISTS idx_videos_updated_at ON videos(updated_at);

	CREATE TABLE IF NOT EXISTS play_sources (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		video_id INTEGER NOT NULL,
		player_code TEXT NOT NULL,
		server TEXT DEFAULT 'no',
		note TEXT DEFAULT '',
		episodes TEXT NOT NULL DEFAULT '[]',
		updated_at DATETIME NOT NULL,
		UNIQUE(video_id, player_code)
	);
	CREATE INDEX IF NOT EXISTS idx_play_sources_vid ON play_sources(video_id);

	CREATE TABLE IF NOT EXISTS feedbacks (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		type TEXT NOT NULL DEFAULT 'request',
		title TEXT NOT NULL,
		content TEXT NOT NULL,
		contact TEXT DEFAULT '',
		status TEXT NOT NULL DEFAULT 'pending',
		reply TEXT DEFAULT '',
		created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
	);
	CREATE INDEX IF NOT EXISTS idx_feedbacks_status ON feedbacks(status);

	CREATE TABLE IF NOT EXISTS user_history (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		user_id INTEGER NOT NULL,
		video_id INTEGER NOT NULL,
		video_name TEXT NOT NULL,
		picture TEXT DEFAULT '',
		episode_name TEXT DEFAULT '',
		route_index INTEGER DEFAULT 0,
		episode_index INTEGER DEFAULT 0,
		play_time INTEGER DEFAULT 0,
		duration INTEGER DEFAULT 0,
		progress REAL DEFAULT 0,
		updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		UNIQUE(user_id, video_id)
	);
	CREATE INDEX IF NOT EXISTS idx_user_history_uid ON user_history(user_id, updated_at DESC);

	CREATE TABLE IF NOT EXISTS user_favorites (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		user_id INTEGER NOT NULL,
		video_id INTEGER NOT NULL,
		video_name TEXT NOT NULL,
		picture TEXT DEFAULT '',
		remarks TEXT DEFAULT '',
		created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		UNIQUE(user_id, video_id)
	);
	CREATE INDEX IF NOT EXISTS idx_user_fav_uid ON user_favorites(user_id, created_at DESC);
	`
	if _, err := s.db.Exec(schema); err != nil {
		return err
	}
	// 兼容迁移：如果旧数据库 videos 没有 hits 字段则尝试添加
	_, _ = s.db.Exec("ALTER TABLE videos ADD COLUMN hits INTEGER DEFAULT 0;")
	// hits 索引必须在补列之后创建，否则旧库升级时会报 no such column: hits
	_, _ = s.db.Exec("CREATE INDEX IF NOT EXISTS idx_videos_hits ON videos(hits);")
	_, _ = s.db.Exec("ALTER TABLE user_history ADD COLUMN play_time INTEGER DEFAULT 0;")
	_, _ = s.db.Exec("ALTER TABLE play_sources ADD COLUMN source_id TEXT DEFAULT '';")
	_, _ = s.db.Exec("ALTER TABLE play_sources ADD COLUMN source_name TEXT DEFAULT '';")
	_, _ = s.db.Exec("CREATE INDEX IF NOT EXISTS idx_play_sources_v_s_p ON play_sources(video_id, source_id, player_code);")
	return nil
}

func (s *SQLiteStore) InitDefaultAdmin(ctx context.Context) error {
	var count int
	_ = s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM users").Scan(&count)
	if count > 0 {
		return nil
	}

	hash, err := bcrypt.GenerateFromPassword([]byte("admin123"), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	_, err = s.db.ExecContext(ctx, `
		INSERT INTO users (username, password_hash, nickname, role, status)
		VALUES (?, ?, ?, ?, ?)
	`, "admin", string(hash), "超级管理员", "admin", 1)
	return err
}

func (s *SQLiteStore) InitDefaultCategories(ctx context.Context) error {
	var count int
	err := s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM categories").Scan(&count)
	if err != nil || count > 0 {
		return err
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

	stmt, err := tx.PrepareContext(ctx, "INSERT OR IGNORE INTO categories (id, pid, name, sort) VALUES (?, ?, ?, ?)")
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
func (s *SQLiteStore) GetUserByUsername(ctx context.Context, username string) (*User, error) {
	u := &User{}
	row := s.db.QueryRowContext(ctx, `
		SELECT id, username, password_hash, nickname, avatar, role, status, created_at, updated_at
		FROM users WHERE username = ?
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

func (s *SQLiteStore) GetUserByID(ctx context.Context, id int) (*User, error) {
	u := &User{}
	row := s.db.QueryRowContext(ctx, `
		SELECT id, username, password_hash, nickname, avatar, role, status, created_at, updated_at
		FROM users WHERE id = ?
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

func (s *SQLiteStore) ListUsers(ctx context.Context) ([]User, error) {
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

func (s *SQLiteStore) CreateUser(ctx context.Context, user *User) error {
	now := time.Now()
	res, err := s.db.ExecContext(ctx, `
		INSERT INTO users (username, password_hash, nickname, avatar, role, status, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	`, user.Username, user.PasswordHash, user.Nickname, user.Avatar, user.Role, user.Status, now, now)
	if err != nil {
		return err
	}
	id, err := res.LastInsertId()
	if err != nil {
		return err
	}
	user.ID = int(id)
	user.CreatedAt = now
	user.UpdatedAt = now
	return nil
}

func (s *SQLiteStore) UpdateUser(ctx context.Context, user *User) error {
	now := time.Now()
	if user.PasswordHash != "" {
		_, err := s.db.ExecContext(ctx, `
			UPDATE users SET nickname=?, avatar=?, role=?, status=?, password_hash=?, updated_at=?
			WHERE id=?
		`, user.Nickname, user.Avatar, user.Role, user.Status, user.PasswordHash, now, user.ID)
		return err
	}
	_, err := s.db.ExecContext(ctx, `
		UPDATE users SET nickname=?, avatar=?, role=?, status=?, updated_at=?
		WHERE id=?
	`, user.Nickname, user.Avatar, user.Role, user.Status, now, user.ID)
	return err
}

func (s *SQLiteStore) DeleteUser(ctx context.Context, id int) error {
	_, err := s.db.ExecContext(ctx, "DELETE FROM users WHERE id = ?", id)
	return err
}

// 系统设置
func (s *SQLiteStore) GetSetting(ctx context.Context, key, defaultVal string) (string, error) {
	var val string
	err := s.db.QueryRowContext(ctx, "SELECT val FROM settings WHERE key = ?", key).Scan(&val)
	if err == sql.ErrNoRows {
		return defaultVal, nil
	}
	if err != nil {
		return defaultVal, err
	}
	return val, nil
}

func (s *SQLiteStore) SetSetting(ctx context.Context, key, val string) error {
	query := `
		INSERT INTO settings (key, val, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP)
		ON CONFLICT(key) DO UPDATE SET val = excluded.val, updated_at = CURRENT_TIMESTAMP
	`
	_, err := s.db.ExecContext(ctx, query, key, val)
	return err
}

func (s *SQLiteStore) GetAllSettings(ctx context.Context) (map[string]string, error) {
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

func (s *SQLiteStore) SetSettings(ctx context.Context, settings map[string]string) error {
	for k, v := range settings {
		if err := s.SetSetting(ctx, k, v); err != nil {
			return err
		}
	}
	return nil
}

func (s *SQLiteStore) GetSources(ctx context.Context) ([]config.SourceConfig, error) {
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

func (s *SQLiteStore) GetSourceByID(ctx context.Context, id string) (*config.SourceConfig, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT id, name, api, type, enabled, collect_hours, page_limit, timeout_sec,
		       retry_count, interval_ms, concurrency, category_mappings, filter_rules
		FROM sources WHERE id = ?
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

func (s *SQLiteStore) SaveSource(ctx context.Context, src config.SourceConfig) error {
	if src.Headers != nil {
		src.Filter.Headers = src.Headers
	}
	if src.CustomParams != nil {
		src.Filter.CustomParams = src.CustomParams
	}
	if src.CustomMapping.ListPath != "" || src.CustomMapping.NamePath != "" {
		src.Filter.CustomMapping = &src.CustomMapping
	}

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
	) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
	ON CONFLICT(id) DO UPDATE SET
		name=excluded.name,
		api=excluded.api,
		type=excluded.type,
		enabled=excluded.enabled,
		collect_hours=excluded.collect_hours,
		page_limit=excluded.page_limit,
		timeout_sec=excluded.timeout_sec,
		retry_count=excluded.retry_count,
		interval_ms=excluded.interval_ms,
		concurrency=excluded.concurrency,
		category_mappings=excluded.category_mappings,
		filter_rules=excluded.filter_rules,
		updated_at=CURRENT_TIMESTAMP
	`
	_, err := s.db.ExecContext(ctx, query,
		src.ID, src.Name, src.API, src.Type, enabledInt, src.CollectHours,
		src.PageLimit, src.TimeoutSec, src.RetryCount, src.IntervalMs,
		src.Concurrency, string(mappingsBytes), string(filterBytes),
	)
	if err != nil {
		return err
	}

	// 级联同步更新该采集节点下已入库所有历史视频的线路名称
	if src.Name != "" && src.ID != "" {
		_, _ = s.db.ExecContext(ctx, "UPDATE play_sources SET source_name = ?, server = ? WHERE source_id = ?", src.Name, src.Name, src.ID)
	}
	return nil
}

func (s *SQLiteStore) DeleteSource(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx, "DELETE FROM sources WHERE id = ?", id)
	return err
}

func (s *SQLiteStore) GetCategories(ctx context.Context) ([]Category, error) {
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

func (s *SQLiteStore) GetCategoryFamilyIDs(ctx context.Context, catID int) ([]int, error) {
	allCats, err := s.GetCategories(ctx)
	if err != nil {
		return []int{catID}, err
	}

	idMap := make(map[int]bool)
	idMap[catID] = true

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

func (s *SQLiteStore) matchCategorySmart(ctx context.Context, srcName string) (int, string) {
	if strings.TrimSpace(srcName) == "" {
		return 0, ""
	}
	cats, err := s.GetCategories(ctx)
	if err != nil {
		return 0, srcName
	}
	for _, c := range cats {
		if c.Name == srcName {
			return c.ID, c.Name
		}
	}
	for _, c := range cats {
		if strings.Contains(srcName, c.Name) || strings.Contains(c.Name, srcName) {
			return c.ID, c.Name
		}
	}
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


// UpsertVideo 写入或更新视频数据（深度支持 SQLite 智能多采集节点独立聚合存储）
func (s *SQLiteStore) UpsertVideo(ctx context.Context, sourceID string, vod *maccms.CleanedVod) (int, error) {
	s.upsertMu.Lock()
	defer s.upsertMu.Unlock()

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

	var videoID int
	var existingSourceID string
	queryExisting := `SELECT id, source_id FROM videos WHERE name = ? LIMIT 1`
	err := s.db.QueryRowContext(ctx, queryExisting, vod.Name).Scan(&videoID, &existingSourceID)

	if err == sql.ErrNoRows {
		insertSQL := `
			INSERT INTO videos (
				name, sub_name, type_id, type_name, picture, actor, director,
				area, language, year, remarks, content, source_id, created_at, updated_at
			) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		`
		res, err := s.db.ExecContext(ctx, insertSQL,
			vod.Name, vod.SubName, vod.TargetTypeID, vod.TargetTypeName, vod.Picture,
			vod.Actor, vod.Director, vod.Area, vod.Language, vod.Year,
			vod.Remarks, vod.Content, sourceID, recordTime, recordTime,
		)
		if err != nil {
			return 0, err
		}
		lid, err := res.LastInsertId()
		if err != nil {
			return 0, err
		}
		videoID = int(lid)
	} else if err != nil {
		return 0, err
	} else {
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
				sub_name = CASE WHEN ? != '' THEN ? ELSE sub_name END,
				picture = CASE WHEN ? != '' THEN ? ELSE picture END,
				remarks = CASE WHEN ? != '' THEN ? ELSE remarks END,
				content = CASE WHEN ? != '' THEN ? ELSE content END,
				type_id = CASE WHEN ? > 0 THEN ? ELSE type_id END,
				type_name = CASE WHEN ? != '' THEN ? ELSE type_name END,
				source_id = ?,
				updated_at = ?
			WHERE id = ?
		`
		_, err := s.db.ExecContext(ctx, updateSQL,
			vod.SubName, vod.SubName,
			vod.Picture, vod.Picture,
			vod.Remarks, vod.Remarks,
			vod.Content, vod.Content,
			vod.TargetTypeID, vod.TargetTypeID,
			vod.TargetTypeName, vod.TargetTypeName,
			newSourceID,
			recordTime, videoID,
		)
		if err != nil {
			return 0, err
		}
	}

	for _, pg := range vod.PlayGroups {
		if len(pg.Episodes) == 0 {
			continue
		}
		epBytes, _ := json.Marshal(pg.Episodes)

		var existingPlayID int
		checkSQL := `SELECT id FROM play_sources WHERE video_id = ? AND source_id = ? AND player_code = ? LIMIT 1`
		err := s.db.QueryRowContext(ctx, checkSQL, videoID, pg.SourceID, pg.PlayerCode).Scan(&existingPlayID)
		if err == sql.ErrNoRows {
			checkOldSQL := `SELECT id FROM play_sources WHERE video_id = ? AND (source_id = '' OR source_id IS NULL) AND player_code = ? LIMIT 1`
			_ = s.db.QueryRowContext(ctx, checkOldSQL, videoID, pg.PlayerCode).Scan(&existingPlayID)
		}

		if existingPlayID > 0 {
			updatePlaySQL := `UPDATE play_sources SET source_id = ?, source_name = ?, server = ?, note = ?, episodes = ?, updated_at = ? WHERE id = ?`
			_, err = s.db.ExecContext(ctx, updatePlaySQL, pg.SourceID, pg.SourceName, pg.Server, pg.Note, string(epBytes), recordTime, existingPlayID)
		} else {
			insertPlaySQL := `INSERT INTO play_sources (video_id, source_id, source_name, player_code, server, note, episodes, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
			_, err = s.db.ExecContext(ctx, insertPlaySQL, videoID, pg.SourceID, pg.SourceName, pg.PlayerCode, pg.Server, pg.Note, string(epBytes), recordTime)
		}
		if err != nil {
			return 0, err
		}
	}

	return videoID, nil
}

func (s *SQLiteStore) QueryVideos(ctx context.Context, q VideoQuery) ([]VideoRecord, int, error) {
	var whereClauses []string
	var args []any

	if q.TypeID > 0 {
		familyIDs, _ := s.GetCategoryFamilyIDs(ctx, q.TypeID)
		if len(familyIDs) == 1 {
			whereClauses = append(whereClauses, "v.type_id = ?")
			args = append(args, familyIDs[0])
		} else if len(familyIDs) > 1 {
			placeholders := make([]string, len(familyIDs))
			for i, fid := range familyIDs {
				placeholders[i] = "?"
				args = append(args, fid)
			}
			whereClauses = append(whereClauses, fmt.Sprintf("v.type_id IN (%s)", strings.Join(placeholders, ",")))
		}
	}

	if q.Hours > 0 {
		timeThreshold := time.Now().Add(-time.Duration(q.Hours) * time.Hour)
		whereClauses = append(whereClauses, "v.updated_at >= ?")
		args = append(args, timeThreshold)
	}

	if q.Area != "" {
		if q.Area == "大陆" {
			whereClauses = append(whereClauses, "(v.area LIKE ? OR v.area LIKE ? OR v.type_name LIKE ?)")
			args = append(args, "%大陆%", "%中国%", "%国产%")
		} else if q.Area == "日本" {
			whereClauses = append(whereClauses, "(v.area LIKE ? OR v.type_name LIKE ?)")
			args = append(args, "%日本%", "%日韩%")
		} else if q.Area == "欧美" {
			whereClauses = append(whereClauses, "(v.area LIKE ? OR v.type_name LIKE ?)")
			args = append(args, "%欧美%", "%欧美%")
		} else {
			whereClauses = append(whereClauses, "v.area LIKE ?")
			args = append(args, "%"+q.Area+"%")
		}
	}

	if q.Year != "" {
		if q.Year == "更早" {
			whereClauses = append(whereClauses, "CAST(v.year AS INTEGER) < 2020")
		} else {
			whereClauses = append(whereClauses, "v.year LIKE ?")
			args = append(args, "%"+q.Year+"%")
		}
	}

	if q.NameKeyword != "" {
		whereClauses = append(whereClauses, "(v.name LIKE ? OR v.sub_name LIKE ?)")
		args = append(args, "%"+q.NameKeyword+"%", "%"+q.NameKeyword+"%")
	}

	if q.Keyword != "" {
		whereClauses = append(whereClauses, "(v.name LIKE ? OR v.sub_name LIKE ? OR v.actor LIKE ? OR v.content LIKE ? OR v.remarks LIKE ?)")
		args = append(args, "%"+q.Keyword+"%", "%"+q.Keyword+"%", "%"+q.Keyword+"%", "%"+q.Keyword+"%", "%"+q.Keyword+"%")
	}

	if len(q.IDs) > 0 {
		var placeholders []string
		for _, id := range q.IDs {
			placeholders = append(placeholders, "?")
			args = append(args, id)
		}
		whereClauses = append(whereClauses, fmt.Sprintf("v.id IN (%s)", strings.Join(placeholders, ",")))
	}

	if len(q.ExcludeIDs) > 0 {
		var placeholders []string
		for _, id := range q.ExcludeIDs {
			placeholders = append(placeholders, "?")
			args = append(args, id)
		}
		whereClauses = append(whereClauses, fmt.Sprintf("v.id NOT IN (%s)", strings.Join(placeholders, ",")))
	}

	whereSQL := ""
	if len(whereClauses) > 0 {
		whereSQL = " WHERE " + strings.Join(whereClauses, " AND ")
	}

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
		       v.content, v.source_id, COALESCE(v.hits, 0), v.created_at, v.updated_at
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
	var videoIDs []any
	idToIdx := make(map[int]int)

	for rows.Next() {
		var rec VideoRecord
		err := rows.Scan(
			&rec.ID, &rec.Name, &rec.SubName, &rec.TypeID, &rec.TypeName, &rec.Picture,
			&rec.Actor, &rec.Director, &rec.Area, &rec.Language, &rec.Year, &rec.Remarks,
			&rec.Content, &rec.SourceID, &rec.Hits, &rec.CreatedAt, &rec.UpdatedAt,
		)
		if err != nil {
			return nil, 0, err
		}
		idToIdx[rec.ID] = len(records)
		records = append(records, rec)
		videoIDs = append(videoIDs, rec.ID)
	}

	if len(videoIDs) > 0 {
		placeholders := make([]string, len(videoIDs))
		for i := range placeholders {
			placeholders[i] = "?"
		}
		playSQL := fmt.Sprintf(`
			SELECT video_id, COALESCE(source_id, ''), COALESCE(source_name, ''), player_code, server, note, episodes
			FROM play_sources
			WHERE video_id IN (%s)
		`, strings.Join(placeholders, ","))

		pRows, err := s.db.QueryContext(ctx, playSQL, videoIDs...)
		if err == nil {
			defer pRows.Close()
			for pRows.Next() {
				var vid int
				var pg maccms.PlayGroup
				var epJSON string
				if err := pRows.Scan(&vid, &pg.SourceID, &pg.SourceName, &pg.PlayerCode, &pg.Server, &pg.Note, &epJSON); err == nil {
					_ = json.Unmarshal([]byte(epJSON), &pg.Episodes)
					if pg.From == "" {
						if pg.SourceName != "" {
							pg.From = pg.SourceName + " (" + pg.PlayerCode + ")"
						} else {
							pg.From = pg.PlayerCode
						}
					}
					if pg.Server == "" || pg.Server == "no" {
						if pg.SourceName != "" {
							pg.Server = pg.SourceName
						}
					}
					if idx, ok := idToIdx[vid]; ok {
						records[idx].PlayGroups = append(records[idx].PlayGroups, pg)
					}
				}
			}
		}
	}

	for i := range records {
		records[i].FillCompatFields()
	}

	return records, total, nil
}

func (s *SQLiteStore) GetVideoByID(ctx context.Context, id int) (*VideoRecord, error) {
	query, _, err := s.QueryVideos(ctx, VideoQuery{IDs: []int{id}, Page: 1, PageSize: 1})
	if err != nil {
		return nil, err
	}
	if len(query) == 0 {
		return nil, nil
	}
	return &query[0], nil
}

func (s *SQLiteStore) SaveVideoManual(ctx context.Context, v *VideoRecord) (int, error) {
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

	if v.ID > 0 {
		updateSQL := `
			UPDATE videos SET
				name = ?, sub_name = ?, type_id = ?, type_name = ?, picture = ?,
				actor = ?, director = ?, area = ?, language = ?, year = ?,
				remarks = ?, content = ?, updated_at = ?
			WHERE id = ?
		`
		_, err := s.db.ExecContext(ctx, updateSQL,
			v.Name, v.SubName, v.TypeID, v.TypeName, v.Picture,
			v.Actor, v.Director, v.Area, v.Language, v.Year,
			v.Remarks, v.Content, v.UpdatedAt, v.ID,
		)
		if err != nil {
			return 0, err
		}
		_, _ = s.db.ExecContext(ctx, "DELETE FROM play_sources WHERE video_id = ?", v.ID)
		for _, pg := range v.PlayGroups {
			epJSON, _ := json.Marshal(pg.Episodes)
			_, _ = s.db.ExecContext(ctx, `
				INSERT INTO play_sources (video_id, player_code, server, note, episodes, updated_at)
				VALUES (?, ?, ?, ?, ?, ?)
			`, v.ID, pg.PlayerCode, pg.Server, pg.Note, string(epJSON), now)
		}
		return v.ID, nil
	} else {
		insertSQL := `
			INSERT INTO videos (
				name, sub_name, type_id, type_name, picture, actor, director,
				area, language, year, remarks, content, source_id, hits, created_at, updated_at
			) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
		`
		res, err := s.db.ExecContext(ctx, insertSQL,
			v.Name, v.SubName, v.TypeID, v.TypeName, v.Picture, v.Actor, v.Director,
			v.Area, v.Language, v.Year, v.Remarks, v.Content, v.SourceID, v.CreatedAt, v.UpdatedAt,
		)
		if err != nil {
			return 0, err
		}
		lid, err := res.LastInsertId()
		if err != nil {
			return 0, err
		}
		v.ID = int(lid)
		for _, pg := range v.PlayGroups {
			epJSON, _ := json.Marshal(pg.Episodes)
			_, _ = s.db.ExecContext(ctx, `
				INSERT INTO play_sources (video_id, player_code, server, note, episodes, updated_at)
				VALUES (?, ?, ?, ?, ?, ?)
			`, v.ID, pg.PlayerCode, pg.Server, pg.Note, string(epJSON), now)
		}
		return v.ID, nil
	}
}

func (s *SQLiteStore) DeleteVideo(ctx context.Context, id int) error {
	_, _ = s.db.ExecContext(ctx, "DELETE FROM play_sources WHERE video_id = ?", id)
	_, err := s.db.ExecContext(ctx, "DELETE FROM videos WHERE id = ?", id)
	return err
}

func (s *SQLiteStore) BatchDeleteVideos(ctx context.Context, ids []int) error {
	for _, id := range ids {
		_ = s.DeleteVideo(ctx, id)
	}
	return nil
}

func (s *SQLiteStore) IncrementVideoHits(ctx context.Context, id int) error {
	_, err := s.db.ExecContext(ctx, "UPDATE videos SET hits = COALESCE(hits, 0) + 1 WHERE id = ?", id)
	return err
}

func (s *SQLiteStore) GetHotVideos(ctx context.Context, typeID int, limit int) ([]VideoRecord, error) {
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
func (s *SQLiteStore) CreateFeedback(ctx context.Context, fb *Feedback) error {
	fb.CreatedAt = time.Now()
	fb.UpdatedAt = time.Now()
	if fb.Status == "" {
		fb.Status = "pending"
	}
	query := `
		INSERT INTO feedbacks (type, title, content, contact, status, reply, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	`
	res, err := s.db.ExecContext(ctx, query, fb.Type, fb.Title, fb.Content, fb.Contact, fb.Status, fb.Reply, fb.CreatedAt, fb.UpdatedAt)
	if err != nil {
		return err
	}
	lid, err := res.LastInsertId()
	if err == nil {
		fb.ID = int(lid)
	}
	return nil
}

func (s *SQLiteStore) ListFeedbacks(ctx context.Context, page, pageSize int, status, fbType string) ([]Feedback, int, error) {
	if page <= 0 {
		page = 1
	}
	if pageSize <= 0 {
		pageSize = 20
	}
	var whereClauses []string
	var args []any
	if status != "" {
		whereClauses = append(whereClauses, "status = ?")
		args = append(args, status)
	}
	if fbType != "" {
		whereClauses = append(whereClauses, "type = ?")
		args = append(args, fbType)
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

func (s *SQLiteStore) UpdateFeedback(ctx context.Context, id int, status, reply string) error {
	query := `UPDATE feedbacks SET status = ?, reply = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?`
	_, err := s.db.ExecContext(ctx, query, status, reply, id)
	return err
}

func (s *SQLiteStore) DeleteFeedback(ctx context.Context, id int) error {
	_, err := s.db.ExecContext(ctx, "DELETE FROM feedbacks WHERE id = ?", id)
	return err
}

func (s *SQLiteStore) GetStats(ctx context.Context) (*StatsInfo, error) {
	stats := &StatsInfo{}

	_ = s.db.QueryRowContext(ctx, "SELECT COUNT(*), COALESCE(SUM(enabled), 0) FROM sources").
		Scan(&stats.TotalSources, &stats.ActiveSources)

	_ = s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM videos").Scan(&stats.TotalVideos)

	todayStart := time.Now().Truncate(24 * time.Hour)
	_ = s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM videos WHERE updated_at >= ?", todayStart).
		Scan(&stats.TodayUpdated)

	_ = s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM play_sources").Scan(&stats.TotalPlayCount)

	_ = s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM users").Scan(&stats.TotalUsers)

	_ = s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM feedbacks").Scan(&stats.TotalFeedbacks)

	return stats, nil
}

// SaveUserHistory 保存/更新用户播放历史与进度 (UPSERT)
func (s *SQLiteStore) SaveUserHistory(ctx context.Context, item *UserHistoryItem) error {
	query := `
	INSERT INTO user_history (
		user_id, video_id, video_name, picture, episode_name,
		route_index, episode_index, play_time, duration, progress, updated_at
	) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
	ON CONFLICT(user_id, video_id) DO UPDATE SET
		video_name = excluded.video_name,
		picture = excluded.picture,
		episode_name = excluded.episode_name,
		route_index = excluded.route_index,
		episode_index = excluded.episode_index,
		play_time = excluded.play_time,
		duration = excluded.duration,
		progress = excluded.progress,
		updated_at = CURRENT_TIMESTAMP;
	`
	_, err := s.db.ExecContext(ctx, query,
		item.UserID, item.VideoID, item.VideoName, item.Picture, item.EpisodeName,
		item.RouteIndex, item.EpisodeIndex, item.CurrentTime, item.Duration, item.Progress,
	)
	return err
}

// GetUserHistory 获取用户的云端播放历史
func (s *SQLiteStore) GetUserHistory(ctx context.Context, userID int, limit int) ([]UserHistoryItem, error) {
	if limit <= 0 {
		limit = 50
	}
	query := `
	SELECT id, user_id, video_id, video_name, picture, episode_name,
	       route_index, episode_index, play_time, duration, progress, updated_at
	FROM user_history
	WHERE user_id = ?
	ORDER BY updated_at DESC
	LIMIT ?
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
func (s *SQLiteStore) DeleteUserHistory(ctx context.Context, userID int, videoID int) error {
	_, err := s.db.ExecContext(ctx, "DELETE FROM user_history WHERE user_id = ? AND video_id = ?", userID, videoID)
	return err
}

// ClearUserHistory 清空用户全部播放历史
func (s *SQLiteStore) ClearUserHistory(ctx context.Context, userID int) error {
	_, err := s.db.ExecContext(ctx, "DELETE FROM user_history WHERE user_id = ?", userID)
	return err
}

// SaveUserFavorite 保存追剧收藏
func (s *SQLiteStore) SaveUserFavorite(ctx context.Context, item *UserFavoriteItem) error {
	query := `
	INSERT INTO user_favorites (user_id, video_id, video_name, picture, remarks, created_at)
	VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
	ON CONFLICT(user_id, video_id) DO UPDATE SET
		video_name = excluded.video_name,
		picture = excluded.picture,
		remarks = excluded.remarks,
		created_at = CURRENT_TIMESTAMP;
	`
	_, err := s.db.ExecContext(ctx, query, item.UserID, item.VideoID, item.VideoName, item.Picture, item.Remarks)
	return err
}

// GetUserFavorites 获取用户追剧收藏列表
func (s *SQLiteStore) GetUserFavorites(ctx context.Context, userID int, limit int) ([]UserFavoriteItem, error) {
	if limit <= 0 {
		limit = 100
	}
	query := `
	SELECT id, user_id, video_id, video_name, picture, remarks, created_at
	FROM user_favorites
	WHERE user_id = ?
	ORDER BY created_at DESC
	LIMIT ?
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
func (s *SQLiteStore) DeleteUserFavorite(ctx context.Context, userID int, videoID int) error {
	_, err := s.db.ExecContext(ctx, "DELETE FROM user_favorites WHERE user_id = ? AND video_id = ?", userID, videoID)
	return err
}
