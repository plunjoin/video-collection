package store

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"
)

// CollectionTask 采集任务执行批次记录模型
type CollectionTask struct {
	ID           int        `json:"id"`
	SourceID     string     `json:"source_id"`
	SourceName   string     `json:"source_name"`
	TriggerType  string     `json:"trigger_type"` // "manual" 手动触发, "cron" 定时调度
	CollectHours int        `json:"collect_hours"` // 0 全量, >0 增量小时
	Status       string     `json:"status"`        // "running" 进行中, "success" 成功, "failed" 失败, "stopped" 中止
	TotalFetched int        `json:"total_fetched"` // 抓取总条数
	TotalSaved   int        `json:"total_saved"`   // 实际有效入库/新增数
	TotalSkipped int        `json:"total_skipped"` // 过滤/跳过数
	ErrorMessage string     `json:"error_message"` // 异常错误摘要
	StartedAt    time.Time  `json:"started_at"`    // 任务启动时间
	EndedAt      *time.Time `json:"ended_at"`      // 任务结束时间
	DurationMs   int64      `json:"duration_ms"`   // 运行时长(毫秒)
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
}

// CollectionTaskQuery 任务分页检索条件
type CollectionTaskQuery struct {
	SourceID    string
	Status      string
	TriggerType string
	Page        int
	PageSize    int
}

// CollectionLog 采集运行结构化日志条目
type CollectionLog struct {
	ID         int       `json:"id"`
	TaskID     int       `json:"task_id"`
	SourceID   string    `json:"source_id"`
	SourceName string    `json:"source_name"`
	Level      string    `json:"level"` // INFO, WARN, SUCCESS, ERROR
	Message    string    `json:"message"`
	CreatedAt  time.Time `json:"created_at"`
}

// CollectionLogQuery 日志分页与过滤条件
type CollectionLogQuery struct {
	TaskID    int
	SourceID  string
	Level     string
	Keyword   string
	Page      int
	PageSize  int
}

// TaskStore 采集任务进度与日志持久化接口
type TaskStore interface {
	CreateCollectionTask(ctx context.Context, task *CollectionTask) (int, error)
	UpdateCollectionTaskProgress(ctx context.Context, id int, fetched, saved, skipped int) error
	FinishCollectionTask(ctx context.Context, id int, status string, errMsg string, fetched, saved, skipped int) error
	GetCollectionTask(ctx context.Context, id int) (*CollectionTask, error)
	ListCollectionTasks(ctx context.Context, q CollectionTaskQuery) ([]CollectionTask, int, error)

	AddCollectionLog(ctx context.Context, log CollectionLog) error
	BatchAddCollectionLogs(ctx context.Context, logs []CollectionLog) error
	ListCollectionLogs(ctx context.Context, q CollectionLogQuery) ([]CollectionLog, int, error)
	ClearCollectionLogs(ctx context.Context, olderThanDays int) (int64, error)
}

func migrateCollectionTasks(tx *sql.Tx, id, timestamp string) error {
	schema := fmt.Sprintf(`
	CREATE TABLE IF NOT EXISTS collection_tasks (
		id %s,
		source_id TEXT NOT NULL,
		source_name TEXT NOT NULL,
		trigger_type TEXT NOT NULL DEFAULT 'manual',
		collect_hours INTEGER NOT NULL DEFAULT 24,
		status TEXT NOT NULL DEFAULT 'running',
		total_fetched INTEGER NOT NULL DEFAULT 0,
		total_saved INTEGER NOT NULL DEFAULT 0,
		total_skipped INTEGER NOT NULL DEFAULT 0,
		error_message TEXT NOT NULL DEFAULT '',
		started_at %s NOT NULL,
		ended_at %s,
		duration_ms INTEGER NOT NULL DEFAULT 0,
		created_at %s NOT NULL,
		updated_at %s NOT NULL
	);
	CREATE INDEX IF NOT EXISTS idx_collection_tasks_source ON collection_tasks(source_id, started_at);
	CREATE INDEX IF NOT EXISTS idx_collection_tasks_status ON collection_tasks(status);

	CREATE TABLE IF NOT EXISTS collection_logs (
		id %s,
		task_id INTEGER NOT NULL DEFAULT 0,
		source_id TEXT NOT NULL DEFAULT '',
		source_name TEXT NOT NULL DEFAULT '',
		level TEXT NOT NULL DEFAULT 'INFO',
		message TEXT NOT NULL,
		created_at %s NOT NULL
	);
	CREATE INDEX IF NOT EXISTS idx_collection_logs_task ON collection_logs(task_id, id);
	CREATE INDEX IF NOT EXISTS idx_collection_logs_source ON collection_logs(source_id, created_at);
	CREATE INDEX IF NOT EXISTS idx_collection_logs_level ON collection_logs(level);
	`, id, timestamp, timestamp, timestamp, timestamp, id, timestamp)

	if err := execScript(tx, schema); err != nil {
		return err
	}

	_, err := tx.Exec("INSERT INTO content_migrations(name) VALUES('collection_tasks_v1') ON CONFLICT(name) DO NOTHING")
	return err
}

func (s *SQLContentStore) CreateCollectionTask(ctx context.Context, task *CollectionTask) (int, error) {
	now := time.Now().UTC()
	task.StartedAt = now
	task.CreatedAt = now
	task.UpdatedAt = now
	if task.Status == "" {
		task.Status = "running"
	}
	if task.TriggerType == "" {
		task.TriggerType = "manual"
	}

	var id int
	err := s.db.QueryRowContext(ctx, `
		INSERT INTO collection_tasks (
			source_id, source_name, trigger_type, collect_hours, status,
			total_fetched, total_saved, total_skipped, error_message,
			started_at, duration_ms, created_at, updated_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
		RETURNING id
	`, task.SourceID, task.SourceName, task.TriggerType, task.CollectHours, task.Status,
		task.TotalFetched, task.TotalSaved, task.TotalSkipped, task.ErrorMessage,
		now, task.DurationMs, now, now).Scan(&id)
	if err != nil {
		return 0, err
	}
	task.ID = id
	return id, nil
}

func (s *SQLContentStore) UpdateCollectionTaskProgress(ctx context.Context, id int, fetched, saved, skipped int) error {
	now := time.Now().UTC()
	var startedAt time.Time
	_ = s.db.QueryRowContext(ctx, `SELECT started_at FROM collection_tasks WHERE id=$1`, id).Scan(&startedAt)
	var durationMs int64
	if !startedAt.IsZero() {
		durationMs = now.Sub(startedAt).Milliseconds()
	}

	_, err := s.db.ExecContext(ctx, `
		UPDATE collection_tasks
		SET total_fetched=$1, total_saved=$2, total_skipped=$3, duration_ms=$4, updated_at=$5
		WHERE id=$6
	`, fetched, saved, skipped, durationMs, now, id)
	return err
}

func (s *SQLContentStore) FinishCollectionTask(ctx context.Context, id int, status string, errMsg string, fetched, saved, skipped int) error {
	now := time.Now().UTC()
	var startedAt time.Time
	_ = s.db.QueryRowContext(ctx, `SELECT started_at FROM collection_tasks WHERE id=$1`, id).Scan(&startedAt)
	var durationMs int64
	if !startedAt.IsZero() {
		durationMs = now.Sub(startedAt).Milliseconds()
	}

	_, err := s.db.ExecContext(ctx, `
		UPDATE collection_tasks
		SET status=$1, error_message=$2, total_fetched=$3, total_saved=$4, total_skipped=$5, ended_at=$6, duration_ms=$7, updated_at=$8
		WHERE id=$9
	`, status, errMsg, fetched, saved, skipped, now, durationMs, now, id)
	return err
}

func (s *SQLContentStore) GetCollectionTask(ctx context.Context, id int) (*CollectionTask, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT id, source_id, source_name, trigger_type, collect_hours, status,
		       total_fetched, total_saved, total_skipped, error_message,
		       started_at, ended_at, duration_ms, created_at, updated_at
		FROM collection_tasks
		WHERE id=$1
	`, id)

	var t CollectionTask
	var endedAt sql.NullTime
	err := row.Scan(
		&t.ID, &t.SourceID, &t.SourceName, &t.TriggerType, &t.CollectHours, &t.Status,
		&t.TotalFetched, &t.TotalSaved, &t.TotalSkipped, &t.ErrorMessage,
		&t.StartedAt, &endedAt, &t.DurationMs, &t.CreatedAt, &t.UpdatedAt,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	if endedAt.Valid {
		t.EndedAt = &endedAt.Time
	}
	return &t, nil
}

func (s *SQLContentStore) ListCollectionTasks(ctx context.Context, q CollectionTaskQuery) ([]CollectionTask, int, error) {
	page := q.Page
	if page <= 0 {
		page = 1
	}
	pageSize := q.PageSize
	if pageSize <= 0 || pageSize > 100 {
		pageSize = 20
	}
	offset := (page - 1) * pageSize

	var conditions []string
	var args []any
	argIdx := 1

	if q.SourceID != "" {
		conditions = append(conditions, fmt.Sprintf("source_id = $%d", argIdx))
		args = append(args, q.SourceID)
		argIdx++
	}
	if q.Status != "" {
		conditions = append(conditions, fmt.Sprintf("status = $%d", argIdx))
		args = append(args, q.Status)
		argIdx++
	}
	if q.TriggerType != "" {
		conditions = append(conditions, fmt.Sprintf("trigger_type = $%d", argIdx))
		args = append(args, q.TriggerType)
		argIdx++
	}

	whereClause := ""
	if len(conditions) > 0 {
		whereClause = "WHERE " + strings.Join(conditions, " AND ")
	}

	countQuery := fmt.Sprintf("SELECT COUNT(*) FROM collection_tasks %s", whereClause)
	var total int
	if err := s.db.QueryRowContext(ctx, countQuery, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	selectQuery := fmt.Sprintf(`
		SELECT id, source_id, source_name, trigger_type, collect_hours, status,
		       total_fetched, total_saved, total_skipped, error_message,
		       started_at, ended_at, duration_ms, created_at, updated_at
		FROM collection_tasks
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

	var tasks []CollectionTask
	for rows.Next() {
		var t CollectionTask
		var endedAt sql.NullTime
		if err := rows.Scan(
			&t.ID, &t.SourceID, &t.SourceName, &t.TriggerType, &t.CollectHours, &t.Status,
			&t.TotalFetched, &t.TotalSaved, &t.TotalSkipped, &t.ErrorMessage,
			&t.StartedAt, &endedAt, &t.DurationMs, &t.CreatedAt, &t.UpdatedAt,
		); err != nil {
			return nil, 0, err
		}
		if endedAt.Valid {
			t.EndedAt = &endedAt.Time
		}
		tasks = append(tasks, t)
	}

	return tasks, total, rows.Err()
}

func (s *SQLContentStore) AddCollectionLog(ctx context.Context, log CollectionLog) error {
	now := time.Now().UTC()
	if log.CreatedAt.IsZero() {
		log.CreatedAt = now
	}
	if log.Level == "" {
		log.Level = "INFO"
	}
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO collection_logs (task_id, source_id, source_name, level, message, created_at)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, log.TaskID, log.SourceID, log.SourceName, log.Level, log.Message, log.CreatedAt)
	return err
}

func (s *SQLContentStore) BatchAddCollectionLogs(ctx context.Context, logs []CollectionLog) error {
	if len(logs) == 0 {
		return nil
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	stmt, err := tx.PrepareContext(ctx, `
		INSERT INTO collection_logs (task_id, source_id, source_name, level, message, created_at)
		VALUES ($1, $2, $3, $4, $5, $6)
	`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	now := time.Now().UTC()
	for _, l := range logs {
		t := l.CreatedAt
		if t.IsZero() {
			t = now
		}
		lvl := l.Level
		if lvl == "" {
			lvl = "INFO"
		}
		if _, err := stmt.ExecContext(ctx, l.TaskID, l.SourceID, l.SourceName, lvl, l.Message, t); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *SQLContentStore) ListCollectionLogs(ctx context.Context, q CollectionLogQuery) ([]CollectionLog, int, error) {
	page := q.Page
	if page <= 0 {
		page = 1
	}
	pageSize := q.PageSize
	if pageSize <= 0 || pageSize > 500 {
		pageSize = 50
	}
	offset := (page - 1) * pageSize

	var conditions []string
	var args []any
	argIdx := 1

	if q.TaskID > 0 {
		conditions = append(conditions, fmt.Sprintf("task_id = $%d", argIdx))
		args = append(args, q.TaskID)
		argIdx++
	}
	if q.SourceID != "" {
		conditions = append(conditions, fmt.Sprintf("source_id = $%d", argIdx))
		args = append(args, q.SourceID)
		argIdx++
	}
	if q.Level != "" {
		conditions = append(conditions, fmt.Sprintf("level = $%d", argIdx))
		args = append(args, strings.ToUpper(q.Level))
		argIdx++
	}
	if q.Keyword != "" {
		conditions = append(conditions, fmt.Sprintf("message LIKE $%d", argIdx))
		args = append(args, "%"+q.Keyword+"%")
		argIdx++
	}

	whereClause := ""
	if len(conditions) > 0 {
		whereClause = "WHERE " + strings.Join(conditions, " AND ")
	}

	countQuery := fmt.Sprintf("SELECT COUNT(*) FROM collection_logs %s", whereClause)
	var total int
	if err := s.db.QueryRowContext(ctx, countQuery, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	// 单任务日志按时间升序展示更符合执行顺序；全局日志按倒序展示最新
	orderClause := "ORDER BY id DESC"
	if q.TaskID > 0 {
		orderClause = "ORDER BY id ASC"
	}

	selectQuery := fmt.Sprintf(`
		SELECT id, task_id, source_id, source_name, level, message, created_at
		FROM collection_logs
		%s
		%s
		LIMIT $%d OFFSET $%d
	`, whereClause, orderClause, argIdx, argIdx+1)

	args = append(args, pageSize, offset)

	rows, err := s.db.QueryContext(ctx, selectQuery, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var logs []CollectionLog
	for rows.Next() {
		var l CollectionLog
		if err := rows.Scan(&l.ID, &l.TaskID, &l.SourceID, &l.SourceName, &l.Level, &l.Message, &l.CreatedAt); err != nil {
			return nil, 0, err
		}
		logs = append(logs, l)
	}
	return logs, total, rows.Err()
}

func (s *SQLContentStore) ClearCollectionLogs(ctx context.Context, olderThanDays int) (int64, error) {
	if olderThanDays <= 0 {
		olderThanDays = 15
	}
	cutoff := time.Now().UTC().AddDate(0, 0, -olderThanDays)
	res, err := s.db.ExecContext(ctx, `DELETE FROM collection_logs WHERE created_at < $1`, cutoff)
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}
