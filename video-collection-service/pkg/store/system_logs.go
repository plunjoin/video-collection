package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

const systemLogRetainLimit = 5000

// SystemLog 后台系统审计日志（与采集日志 collection_logs 分离）
type SystemLog struct {
	ID         int            `json:"id"`
	Level      string         `json:"level"`    // info / warn / error
	Category   string         `json:"category"` // auth / admin / collect / content / system
	Message    string         `json:"message"`
	ActorID    int            `json:"actor_id"`
	ActorName  string         `json:"actor_name"`
	Meta       map[string]any `json:"meta,omitempty"`
	CreatedAt  time.Time      `json:"created_at"`
}

// SystemLogQuery 系统日志分页与过滤
type SystemLogQuery struct {
	Level    string
	Category string
	Q        string
	Page     int
	PageSize int
}

// SystemLogStore 系统审计日志持久化
type SystemLogStore interface {
	AppendSystemLog(ctx context.Context, log SystemLog) error
	ListSystemLogs(ctx context.Context, q SystemLogQuery) ([]SystemLog, int, error)
}

func migrateSystemLogs(tx *sql.Tx, id, timestamp string) error {
	schema := fmt.Sprintf(`
	CREATE TABLE IF NOT EXISTS system_logs (
		id %s,
		level TEXT NOT NULL DEFAULT 'info',
		category TEXT NOT NULL DEFAULT 'system',
		message TEXT NOT NULL,
		actor_id INTEGER NOT NULL DEFAULT 0,
		actor_name TEXT NOT NULL DEFAULT '',
		meta TEXT NOT NULL DEFAULT '',
		created_at %s NOT NULL
	);
	CREATE INDEX IF NOT EXISTS idx_system_logs_created ON system_logs(created_at DESC, id DESC);
	CREATE INDEX IF NOT EXISTS idx_system_logs_level ON system_logs(level);
	CREATE INDEX IF NOT EXISTS idx_system_logs_category ON system_logs(category);
	`, id, timestamp)
	if _, err := tx.Exec(schema); err != nil {
		return err
	}
	_, err := tx.Exec("INSERT INTO content_migrations(name) VALUES('system_logs_v1') ON CONFLICT(name) DO NOTHING")
	return err
}

func normalizeSystemLogLevel(level string) string {
	switch strings.ToLower(strings.TrimSpace(level)) {
	case "warn", "warning":
		return "warn"
	case "error", "err":
		return "error"
	default:
		return "info"
	}
}

func normalizeSystemLogCategory(category string) string {
	switch strings.ToLower(strings.TrimSpace(category)) {
	case "auth", "admin", "collect", "content", "system":
		return strings.ToLower(strings.TrimSpace(category))
	default:
		return "system"
	}
}

func (s *SQLContentStore) AppendSystemLog(ctx context.Context, log SystemLog) error {
	msg := strings.TrimSpace(log.Message)
	if msg == "" {
		return fmt.Errorf("系统日志内容不能为空")
	}
	level := normalizeSystemLogLevel(log.Level)
	category := normalizeSystemLogCategory(log.Category)
	metaJSON := ""
	if log.Meta != nil && len(log.Meta) > 0 {
		b, err := json.Marshal(log.Meta)
		if err != nil {
			return err
		}
		metaJSON = string(b)
	}
	now := time.Now().UTC()
	if !log.CreatedAt.IsZero() {
		now = log.CreatedAt.UTC()
	}
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO system_logs (level, category, message, actor_id, actor_name, meta, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, level, category, msg, log.ActorID, strings.TrimSpace(log.ActorName), metaJSON, now)
	if err != nil {
		return err
	}
	return s.pruneSystemLogs(ctx)
}

func (s *SQLContentStore) pruneSystemLogs(ctx context.Context) error {
	var count int
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM system_logs`).Scan(&count); err != nil {
		return err
	}
	if count <= systemLogRetainLimit {
		return nil
	}
	excess := count - systemLogRetainLimit
	_, err := s.db.ExecContext(ctx, `
		DELETE FROM system_logs
		WHERE id IN (
			SELECT id FROM system_logs ORDER BY id ASC LIMIT $1
		)
	`, excess)
	return err
}

func (s *SQLContentStore) ListSystemLogs(ctx context.Context, q SystemLogQuery) ([]SystemLog, int, error) {
	page := q.Page
	if page <= 0 {
		page = 1
	}
	pageSize := q.PageSize
	if pageSize <= 0 {
		pageSize = 20
	}
	if pageSize > 100 {
		pageSize = 100
	}
	offset := (page - 1) * pageSize

	var conditions []string
	var args []any
	argIdx := 1

	if level := strings.TrimSpace(q.Level); level != "" {
		conditions = append(conditions, fmt.Sprintf("level = $%d", argIdx))
		args = append(args, normalizeSystemLogLevel(level))
		argIdx++
	}
	if category := strings.TrimSpace(q.Category); category != "" {
		conditions = append(conditions, fmt.Sprintf("category = $%d", argIdx))
		args = append(args, normalizeSystemLogCategory(category))
		argIdx++
	}
	if keyword := strings.TrimSpace(q.Q); keyword != "" {
		conditions = append(conditions, fmt.Sprintf("(message LIKE $%d OR actor_name LIKE $%d)", argIdx, argIdx+1))
		like := "%" + keyword + "%"
		args = append(args, like, like)
		argIdx += 2
	}

	whereClause := ""
	if len(conditions) > 0 {
		whereClause = "WHERE " + strings.Join(conditions, " AND ")
	}

	var total int
	if err := s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM system_logs "+whereClause, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	selectQuery := fmt.Sprintf(`
		SELECT id, level, category, message, actor_id, actor_name, meta, created_at
		FROM system_logs
		%s
		ORDER BY id DESC
		LIMIT $%d OFFSET $%d
	`, whereClause, argIdx, argIdx+1)
	args = append(args, pageSize, offset)

	rows, err := s.db.QueryContext(ctx, selectQuery, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	logs := make([]SystemLog, 0)
	for rows.Next() {
		var item SystemLog
		var metaRaw string
		if err := rows.Scan(&item.ID, &item.Level, &item.Category, &item.Message, &item.ActorID, &item.ActorName, &metaRaw, &item.CreatedAt); err != nil {
			return nil, 0, err
		}
		if strings.TrimSpace(metaRaw) != "" {
			_ = json.Unmarshal([]byte(metaRaw), &item.Meta)
		}
		logs = append(logs, item)
	}
	return logs, total, rows.Err()
}
