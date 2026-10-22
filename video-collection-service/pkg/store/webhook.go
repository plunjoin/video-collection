package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// Webhook 外部系统回调采集端点（密钥以加密信封存储，明文仅在创建/轮换时返回一次）。
type Webhook struct {
	ID           string    `json:"id"`
	Name         string    `json:"name"`
	SecretHint   string    `json:"secret_hint"`   // 密钥掩码，仅用于界面展示
	Target       string    `json:"target"`        // "video" 入库视频库, "record" 落入通用采集记录
	Duplicate    string    `json:"duplicate"`     // "update" 覆盖更新, "skip" 已存在则跳过
	Events       []string  `json:"events"`        // 允许的事件类型白名单，空数组表示不限制
	SourceID     string    `json:"source_id"`     // 入视频库时归属的来源标识（默认 webhook:<id>）
	ToleranceSec int       `json:"tolerance_sec"` // 签名时间戳容忍窗口（秒），<=0 表示不校验时间戳
	Enabled      bool      `json:"enabled"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// WebhookStats 单个 webhook 的投递统计概览。
type WebhookStats struct {
	Total        int        `json:"total"`
	Accepted     int        `json:"accepted"`
	Rejected     int        `json:"rejected"`
	Duplicate    int        `json:"duplicate"`
	Error        int        `json:"error"`
	Imported     int        `json:"imported_total"`
	LastStatus   string     `json:"last_status"`
	LastDelivery *time.Time `json:"last_delivery_at"`
}

// WebhookDelivery 一次 webhook 投递的完整留痕（含原始报文，便于审计与重放）。
type WebhookDelivery struct {
	ID           int       `json:"id"`
	WebhookID    string    `json:"webhook_id"`
	WebhookName  string    `json:"webhook_name"`
	Event        string    `json:"event"`
	Status       string    `json:"status"` // accepted / rejected / duplicate / error
	Imported     int       `json:"imported"`
	ErrorMessage string    `json:"error_message"`
	RemoteIP     string    `json:"remote_ip"`
	RawBody      string    `json:"raw_body"`
	CreatedAt    time.Time `json:"created_at"`
}

// WebhookDeliveryQuery 投递日志检索条件。
type WebhookDeliveryQuery struct {
	WebhookID string
	Status    string
	Keyword   string
	Page      int
	PageSize  int
}

// WebhookStore 回调采集端点与投递日志持久化接口（SQLite / PostgreSQL 双驱动共用实现）。
type WebhookStore interface {
	CreateWebhook(ctx context.Context, wh *Webhook, secretCipher string) error
	UpdateWebhook(ctx context.Context, wh *Webhook) error
	DeleteWebhook(ctx context.Context, id string) error
	GetWebhook(ctx context.Context, id string) (*Webhook, error)
	ListWebhooks(ctx context.Context) ([]Webhook, error)
	GetWebhookSecret(ctx context.Context, id string) (string, error)
	RotateWebhookSecret(ctx context.Context, id, secretCipher, hint string) error
	RecordWebhookDelivery(ctx context.Context, d *WebhookDelivery) error
	ListWebhookDeliveries(ctx context.Context, q WebhookDeliveryQuery) ([]WebhookDelivery, int, error)
	GetWebhookStats(ctx context.Context, id string) (*WebhookStats, error)
	ClearWebhookDeliveries(ctx context.Context, webhookID string, olderThanDays int) (int64, error)
}

func migrateWebhooks(tx *sql.Tx, postgres bool, id, timestamp string) error {
	schema := fmt.Sprintf(`
CREATE TABLE IF NOT EXISTS webhooks (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL DEFAULT '',
  secret_cipher TEXT NOT NULL,
  secret_hint TEXT NOT NULL DEFAULT '',
  target TEXT NOT NULL DEFAULT 'video',
  duplicate TEXT NOT NULL DEFAULT 'update',
  events TEXT NOT NULL DEFAULT '[]',
  source_id TEXT NOT NULL DEFAULT '',
  tolerance_sec INTEGER NOT NULL DEFAULT 300,
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at %s NOT NULL, updated_at %s NOT NULL
);
CREATE TABLE IF NOT EXISTS webhook_deliveries (
  id %s,
  webhook_id TEXT NOT NULL,
  event TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'accepted',
  imported INTEGER NOT NULL DEFAULT 0,
  error_message TEXT NOT NULL DEFAULT '',
  remote_ip TEXT NOT NULL DEFAULT '',
  raw_body TEXT NOT NULL DEFAULT '',
  created_at %s NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_list ON webhook_deliveries(webhook_id, created_at DESC, id DESC);
`, timestamp, timestamp, id, timestamp)
	if err := execScript(tx, schema); err != nil {
		return err
	}
	// PostgreSQL errors abort the transaction, so duplicate columns must be
	// avoided and other errors returned. SQLite duplicate-column errors are safe
	// to ignore and older versions do not support ADD COLUMN IF NOT EXISTS.
	alter := "ALTER TABLE webhooks ADD COLUMN "
	if postgres {
		alter += "IF NOT EXISTS "
	}
	for _, column := range []string{
		"tolerance_sec INTEGER NOT NULL DEFAULT 300",
		"events TEXT NOT NULL DEFAULT '[]'",
		"secret_hint TEXT NOT NULL DEFAULT ''",
	} {
		if _, err := tx.Exec(alter + column); err != nil && postgres {
			return err
		}
	}
	return nil
}

func validWebhookTarget(t string) bool { return t == "video" || t == "record" }
func validWebhookDuplicate(d string) bool {
	return d == "update" || d == "skip"
}

// CreateWebhook 创建回调端点，secretCipher 为加密后的密钥信封（AES-256-GCM）。
func (s *SQLContentStore) CreateWebhook(ctx context.Context, wh *Webhook, secretCipher string) error {
	if wh.ID == "" || secretCipher == "" {
		return fmt.Errorf("webhook 缺少 ID 或密钥")
	}
	if !validWebhookTarget(wh.Target) {
		wh.Target = "video"
	}
	if !validWebhookDuplicate(wh.Duplicate) {
		wh.Duplicate = "update"
	}
	wh.Events = normalizeWebhookEvents(wh.Events)
	now := time.Now().UTC()
	wh.CreatedAt, wh.UpdatedAt = now, now
	events, err := json.Marshal(wh.Events)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `
INSERT INTO webhooks (id,name,secret_cipher,secret_hint,target,duplicate,events,source_id,tolerance_sec,enabled,created_at,updated_at)
VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
		wh.ID, wh.Name, secretCipher, wh.SecretHint, wh.Target, wh.Duplicate, string(events),
		wh.SourceID, wh.ToleranceSec, boolToInt(wh.Enabled), now, now)
	return err
}

func normalizeWebhookEvents(events []string) []string {
	if len(events) == 0 {
		return []string{}
	}
	seen := map[string]bool{}
	out := make([]string, 0, len(events))
	for _, e := range events {
		e = strings.TrimSpace(e)
		if e == "" || seen[e] {
			continue
		}
		seen[e] = true
		out = append(out, e)
	}
	return out
}

func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}

// UpdateWebhook 更新回调端点配置（不含密钥）。
func (s *SQLContentStore) UpdateWebhook(ctx context.Context, wh *Webhook) error {
	if wh.ID == "" {
		return fmt.Errorf("缺少 webhook ID")
	}
	if !validWebhookTarget(wh.Target) {
		return fmt.Errorf("不支持的采集目标: %s", wh.Target)
	}
	if !validWebhookDuplicate(wh.Duplicate) {
		return fmt.Errorf("不支持的重复策略: %s", wh.Duplicate)
	}
	wh.Events = normalizeWebhookEvents(wh.Events)
	if wh.ToleranceSec < 0 || wh.ToleranceSec > 86400 {
		return fmt.Errorf("时间戳容忍窗口须为 0–86400 秒（0 表示不校验）")
	}
	events, err := json.Marshal(wh.Events)
	if err != nil {
		return err
	}
	res, err := s.db.ExecContext(ctx, `
UPDATE webhooks SET name=$1,target=$2,duplicate=$3,events=$4,source_id=$5,tolerance_sec=$6,enabled=$7,updated_at=$8 WHERE id=$9`,
		wh.Name, wh.Target, wh.Duplicate, string(events), wh.SourceID, wh.ToleranceSec, boolToInt(wh.Enabled),
		time.Now().UTC(), wh.ID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return fmt.Errorf("webhook 不存在: %s", wh.ID)
	}
	return nil
}

func (s *SQLContentStore) DeleteWebhook(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx, "DELETE FROM webhooks WHERE id=$1", id)
	return err
}

func (s *SQLContentStore) GetWebhook(ctx context.Context, id string) (*Webhook, error) {
	wh := &Webhook{}
	var events, sourceID string
	var enabled, tolerance int
	err := s.db.QueryRowContext(ctx, `
SELECT id,name,secret_hint,target,duplicate,events,source_id,tolerance_sec,enabled,created_at,updated_at FROM webhooks WHERE id=$1`, id).
		Scan(&wh.ID, &wh.Name, &wh.SecretHint, &wh.Target, &wh.Duplicate, &events, &sourceID, &tolerance, &enabled, &wh.CreatedAt, &wh.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	_ = json.Unmarshal([]byte(events), &wh.Events)
	if wh.Events == nil {
		wh.Events = []string{}
	}
	wh.SourceID = sourceID
	wh.ToleranceSec = tolerance
	wh.Enabled = enabled != 0
	return wh, nil
}

func (s *SQLContentStore) ListWebhooks(ctx context.Context) ([]Webhook, error) {
	rows, err := s.db.QueryContext(ctx, `
SELECT id,name,secret_hint,target,duplicate,events,source_id,tolerance_sec,enabled,created_at,updated_at FROM webhooks ORDER BY created_at DESC, id DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var list []Webhook
	for rows.Next() {
		var wh Webhook
		var events, sourceID string
		var enabled, tolerance int
		if err := rows.Scan(&wh.ID, &wh.Name, &wh.SecretHint, &wh.Target, &wh.Duplicate, &events, &sourceID, &tolerance, &enabled, &wh.CreatedAt, &wh.UpdatedAt); err != nil {
			return nil, err
		}
		_ = json.Unmarshal([]byte(events), &wh.Events)
		if wh.Events == nil {
			wh.Events = []string{}
		}
		wh.SourceID, wh.ToleranceSec, wh.Enabled = sourceID, tolerance, enabled != 0
		list = append(list, wh)
	}
	return list, rows.Err()
}

// GetWebhookSecret 返回加密信封存储的密钥（由调用方解密后参与验签，绝不外泄）。
func (s *SQLContentStore) GetWebhookSecret(ctx context.Context, id string) (string, error) {
	var cipher string
	err := s.db.QueryRowContext(ctx, "SELECT secret_cipher FROM webhooks WHERE id=$1", id).Scan(&cipher)
	if err == sql.ErrNoRows {
		return "", nil
	}
	return cipher, err
}

// RotateWebhookSecret 轮换密钥（旧密钥立即失效），secretCipher 为新密钥的加密信封。
func (s *SQLContentStore) RotateWebhookSecret(ctx context.Context, id, secretCipher, hint string) error {
	if secretCipher == "" {
		return fmt.Errorf("密钥不能为空")
	}
	res, err := s.db.ExecContext(ctx, "UPDATE webhooks SET secret_cipher=$1, secret_hint=$2, updated_at=$3 WHERE id=$4", secretCipher, hint, time.Now().UTC(), id)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return fmt.Errorf("webhook 不存在: %s", id)
	}
	return nil
}

// HasVideoByName 判断视频库中是否已存在同名影片（供 webhook skip 去重策略使用）。
func (s *SQLContentStore) HasVideoByName(ctx context.Context, name string) (bool, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return false, nil
	}
	var n int
	err := s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM videos WHERE name = $1", name).Scan(&n)
	return n > 0, err
}

// RecordWebhookDelivery 记录一次投递留痕（含原始报文与入库条数）。
func (s *SQLContentStore) RecordWebhookDelivery(ctx context.Context, d *WebhookDelivery) error {
	if d.WebhookID == "" {
		return fmt.Errorf("缺少 webhook ID")
	}
	if d.Status == "" {
		d.Status = "accepted"
	}
	_, err := s.db.ExecContext(ctx, `
INSERT INTO webhook_deliveries (webhook_id,event,status,imported,error_message,remote_ip,raw_body,created_at)
VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
		d.WebhookID, d.Event, d.Status, d.Imported, d.ErrorMessage, d.RemoteIP, d.RawBody, time.Now().UTC())
	return err
}

func (s *SQLContentStore) ListWebhookDeliveries(ctx context.Context, q WebhookDeliveryQuery) ([]WebhookDelivery, int, error) {
	size, offset := contentPage(q.Page, q.PageSize)
	where := " WHERE 1=1"
	args := []any{}
	add := func(clause string, value any) {
		args = append(args, value)
		where += fmt.Sprintf(clause, len(args))
	}
	if q.WebhookID != "" {
		add(" AND d.webhook_id=$%d", q.WebhookID)
	}
	if q.Status != "" {
		add(" AND d.status=$%d", q.Status)
	}
	if q.Keyword != "" {
		kw := strings.NewReplacer("!", "!!", "%", "!%", "_", "!_").Replace(strings.ToLower(q.Keyword))
		args = append(args, "%"+kw+"%")
		where += fmt.Sprintf(" AND (LOWER(d.event) LIKE $%d ESCAPE '!' OR LOWER(d.error_message) LIKE $%d ESCAPE '!' OR LOWER(d.raw_body) LIKE $%d ESCAPE '!')", len(args), len(args), len(args))
	}
	var total int
	if err := s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM webhook_deliveries d"+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	args = append(args, size, offset)
	rows, err := s.db.QueryContext(ctx, `
SELECT d.id,d.webhook_id,COALESCE(w.name,''),d.event,d.status,d.imported,d.error_message,d.remote_ip,d.raw_body,d.created_at
FROM webhook_deliveries d LEFT JOIN webhooks w ON w.id=d.webhook_id`+where+
		fmt.Sprintf(" ORDER BY d.created_at DESC, d.id DESC LIMIT $%d OFFSET $%d", len(args)-1, len(args)), args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	var list []WebhookDelivery
	for rows.Next() {
		var d WebhookDelivery
		if err := rows.Scan(&d.ID, &d.WebhookID, &d.WebhookName, &d.Event, &d.Status, &d.Imported, &d.ErrorMessage, &d.RemoteIP, &d.RawBody, &d.CreatedAt); err != nil {
			return nil, 0, err
		}
		list = append(list, d)
	}
	return list, total, rows.Err()
}

// GetWebhookStats 汇总单个 webhook 的投递结果分布与最近状态。
func (s *SQLContentStore) GetWebhookStats(ctx context.Context, id string) (*WebhookStats, error) {
	st := &WebhookStats{}
	rows, err := s.db.QueryContext(ctx, `
SELECT status, COUNT(*), COALESCE(SUM(imported),0), MAX(created_at) FROM webhook_deliveries WHERE webhook_id=$1 GROUP BY status`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var status, last string
		var count, imported int
		if err := rows.Scan(&status, &count, &imported, &last); err != nil {
			return nil, err
		}
		st.Total += count
		st.Imported += imported
		switch status {
		case "accepted":
			st.Accepted = count
		case "rejected":
			st.Rejected = count
		case "duplicate":
			st.Duplicate = count
		case "error":
			st.Error = count
		}
		// 聚合结果无列类型声明，SQLite 驱动按字符串返回，需自行解析
		if t, ok := parseAggregateTime(last); ok && (st.LastDelivery == nil || t.After(*st.LastDelivery)) {
			st.LastDelivery = &t
			st.LastStatus = status
		}
	}
	return st, rows.Err()
}

// parseAggregateTime 解析聚合时间列（兼容 RFC3339Nano / DATETIME 字符串）。
func parseAggregateTime(raw string) (time.Time, bool) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return time.Time{}, false
	}
	for _, layout := range []string{time.RFC3339Nano, "2006-01-02 15:04:05.999999999-07:00", "2006-01-02 15:04:05", "2006-01-02T15:04:05"} {
		if t, err := time.Parse(layout, raw); err == nil {
			return t, true
		}
	}
	return time.Time{}, false
}

// ClearWebhookDeliveries 清理投递日志；webhookID 为空表示清理全部端点。
// olderThanDays > 0 表示保留天数（清理更早的记录）；0 表示清理全部；< 0 视为 30 天。
func (s *SQLContentStore) ClearWebhookDeliveries(ctx context.Context, webhookID string, olderThanDays int) (int64, error) {
	if olderThanDays < 0 {
		olderThanDays = 30
	}
	cutoff := time.Now().UTC().Add(time.Second)
	if olderThanDays > 0 {
		cutoff = time.Now().UTC().AddDate(0, 0, -olderThanDays)
	}
	var res sql.Result
	var err error
	if webhookID == "" {
		res, err = s.db.ExecContext(ctx, "DELETE FROM webhook_deliveries WHERE created_at < $1", cutoff)
	} else {
		res, err = s.db.ExecContext(ctx, "DELETE FROM webhook_deliveries WHERE webhook_id=$1 AND created_at < $2", webhookID, cutoff)
	}
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}
