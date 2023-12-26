package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// DBAdmin 数据库管理能力（PostgreSQL 优先，SQLite 兼容降级）。
// 用于管理后台的「数据库管理」模块：引擎信息、表统计、数据浏览、备份恢复、清理维护与执行管理 SQL。
type DBAdmin interface {
	Engine() string
	GetDBInfo(ctx context.Context) (*DBInfo, error)
	ListDBTables(ctx context.Context) ([]DBTableInfo, error)
	BrowseTable(ctx context.Context, q TableBrowseQuery) (*TableBrowseResult, error)
	BackupDatabase(ctx context.Context, opts BackupOptions) (*BackupResult, error)
	ListBackups(ctx context.Context) ([]BackupMeta, error)
	DeleteBackup(ctx context.Context, filename string) error
	PreviewRestore(ctx context.Context, filename, mode string) (*RestorePreview, error)
	RestoreDatabase(ctx context.Context, filename, mode string) (*RestoreResult, error)
	RunCleanup(ctx context.Context, actions []string) ([]CleanupResult, error)
	ExecSQL(ctx context.Context, statement string) (*SQLExecResult, error)
}

// DBInfo 数据库整体信息
type DBInfo struct {
	Engine     string `json:"engine"`              // "postgres" | "sqlite"
	Driver     string `json:"driver"`              // 底层驱动名
	Version    string `json:"version"`             // 数据库版本字符串
	Host       string `json:"host,omitempty"`      // PostgreSQL 主机
	Database   string `json:"database,omitempty"`  // PostgreSQL 库名
	FilePath   string `json:"file_path,omitempty"` // SQLite 数据文件路径
	SizeBytes  int64  `json:"size_bytes"`          // 数据库整体占用字节数
	TableCount int    `json:"table_count"`         // 业务表数量
	BackupsDir string `json:"backups_dir"`         // 备份文件存储目录
	ServerTime string `json:"server_time"`         // 服务器当前时间
}

// DBTableInfo 单张数据表的统计信息
type DBTableInfo struct {
	Name        string `json:"name"`
	Rows        int64  `json:"rows"`        // PG 为估算值(reltuples)，SQLite 为精确 COUNT(*)
	Approximate bool   `json:"approximate"` // Rows 是否为估算值
	SizeBytes   int64  `json:"size_bytes"`  // 表占用字节数（SQLite 下为 0，库整体占用见 DBInfo）
	ColumnCount int    `json:"column_count"`
	IndexCount  int    `json:"index_count"`
	Comment     string `json:"comment,omitempty"`
}

// TableColumn 表字段信息
type TableColumn struct {
	Name     string `json:"name"`
	DataType string `json:"data_type"`
}

// TableBrowseQuery 表数据浏览查询
type TableBrowseQuery struct {
	Table     string
	Page      int
	PageSize  int
	OrderBy   string
	OrderDesc bool
	Keyword   string // 全列模糊搜索
}

// TableBrowseResult 表数据浏览结果
type TableBrowseResult struct {
	Columns  []TableColumn    `json:"columns"`
	Rows     []map[string]any `json:"rows"`
	Total    int64            `json:"total"`
	Page     int              `json:"page"`
	PageSize int              `json:"page_size"`
}

// BackupOptions 备份选项
type BackupOptions struct {
	Tables []string `json:"tables"` // 空表示备份全部业务表
}

// BackupResult 备份结果
type BackupResult struct {
	Filename  string `json:"filename"`
	FilePath  string `json:"file_path"`
	SizeBytes int64  `json:"size_bytes"`
	Tables    int    `json:"tables"`
	Rows      int64  `json:"rows"`
	CreatedAt string `json:"created_at"`
}

// BackupMeta 备份文件元信息（列表用，仅读取文件头）
type BackupMeta struct {
	Filename  string `json:"filename"`
	SizeBytes int64  `json:"size_bytes"`
	CreatedAt string `json:"created_at"`
	Engine    string `json:"engine"`
	Tables    int    `json:"tables"`
	Rows      int64  `json:"rows"`
}

// RestoreResult 恢复结果
type RestoreResult struct {
	File     string `json:"file"`
	Mode     string `json:"mode"` // "merge" 合并导入 / "replace" 清空后导入
	Tables   int    `json:"tables"`
	Inserted int64  `json:"inserted"`
	Skipped  int64  `json:"skipped"`
	Elapsed  string `json:"elapsed"`
}

// RestorePreview 恢复预览（dry-run），展示备份中每张表的行数与目标表是否存在
type RestorePreview struct {
	File      string                `json:"file"`
	Mode      string                `json:"mode"`
	Engine    string                `json:"engine"`
	CreatedAt string                `json:"created_at"`
	Tables    []RestorePreviewTable `json:"tables"`
}

// RestorePreviewTable 恢复预览中的单表信息
type RestorePreviewTable struct {
	Name   string `json:"name"`
	Rows   int    `json:"rows"`
	Exists bool   `json:"exists"`
}

// CleanupResult 单个清理动作的结果
type CleanupResult struct {
	Action   string `json:"action"`
	Affected int64  `json:"affected"`
	Error    string `json:"error,omitempty"`
}

// SQLExecResult 管理 SQL 执行结果
type SQLExecResult struct {
	Type      string           `json:"type"` // "select" | "write" | "ddl"
	Columns   []string         `json:"columns,omitempty"`
	Rows      []map[string]any `json:"rows,omitempty"`
	RowCount  int              `json:"row_count,omitempty"`
	Truncated bool             `json:"truncated,omitempty"` // 查询结果超过 1000 行被截断
	Affected  int64            `json:"affected,omitempty"`
	Message   string           `json:"message,omitempty"`
}

const backupFormat = "video-collection-backup"

type backupFile struct {
	Format    string        `json:"format"`
	Version   int           `json:"version"`
	Engine    string        `json:"engine"`
	CreatedAt string        `json:"created_at"`
	Tables    []backupTable `json:"tables"`
}

type backupTable struct {
	Name    string   `json:"name"`
	Columns []string `json:"columns"`
	Rows    [][]any  `json:"rows"`
}

// dbAdminHelper 为 SQLite / PostgreSQL 提供共用的数据库管理实现
type dbAdminHelper struct {
	db         *sql.DB
	engine     string // "postgres" | "sqlite"
	host       string // PostgreSQL 主机:端口
	dbName     string // PostgreSQL 库名
	filePath   string // SQLite 数据文件路径
	backupsDir string // 备份文件目录
}

func (h *dbAdminHelper) Engine() string { return h.engine }

// listTables 返回业务表名列表
func (h *dbAdminHelper) listTables(ctx context.Context) ([]string, error) {
	var names []string
	if h.engine == "postgres" {
		rows, err := h.db.QueryContext(ctx, `
			SELECT t.relname FROM pg_class t
			JOIN pg_namespace n ON n.oid = t.relnamespace
			WHERE t.relkind = 'r' AND n.nspname = 'public'
			ORDER BY t.relname`)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		for rows.Next() {
			var name string
			if err := rows.Scan(&name); err != nil {
				return nil, err
			}
			names = append(names, name)
		}
		return names, rows.Err()
	}
	rows, err := h.db.QueryContext(ctx, `
		SELECT name FROM sqlite_master
		WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
		ORDER BY name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, err
		}
		names = append(names, name)
	}
	return names, rows.Err()
}

// tableColumns 返回表字段信息
func (h *dbAdminHelper) tableColumns(ctx context.Context, table string) ([]TableColumn, error) {
	var cols []TableColumn
	if h.engine == "postgres" {
		rows, err := h.db.QueryContext(ctx, `
			SELECT column_name, data_type FROM information_schema.columns
			WHERE table_schema = 'public' AND table_name = $1
			ORDER BY ordinal_position`, table)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		for rows.Next() {
			var c TableColumn
			if err := rows.Scan(&c.Name, &c.DataType); err != nil {
				return nil, err
			}
			cols = append(cols, c)
		}
		return cols, rows.Err()
	}
	rows, err := h.db.QueryContext(ctx, "PRAGMA table_info("+quoteIdent(table)+")")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var cid, notnull, pk int
		var name, ctype string
		var dflt sql.NullString
		if err := rows.Scan(&cid, &name, &ctype, &notnull, &dflt, &pk); err != nil {
			return nil, err
		}
		cols = append(cols, TableColumn{Name: name, DataType: ctype})
	}
	return cols, rows.Err()
}

// tableColumnNames 返回字段名列表
func (h *dbAdminHelper) tableColumnNames(ctx context.Context, table string) ([]string, error) {
	cols, err := h.tableColumns(ctx, table)
	if err != nil {
		return nil, err
	}
	names := make([]string, len(cols))
	for i, c := range cols {
		names[i] = c.Name
	}
	return names, nil
}

// tableExists 判断表是否存在
func (h *dbAdminHelper) tableExists(ctx context.Context, table string) (bool, error) {
	names, err := h.listTables(ctx)
	if err != nil {
		return false, err
	}
	for _, n := range names {
		if n == table {
			return true, nil
		}
	}
	return false, nil
}

// GetDBInfo 数据库整体信息
func (h *dbAdminHelper) GetDBInfo(ctx context.Context) (*DBInfo, error) {
	info := &DBInfo{
		Engine:     h.engine,
		Driver:     h.engine,
		Host:       h.host,
		Database:   h.dbName,
		FilePath:   h.filePath,
		BackupsDir: h.backupsDir,
		ServerTime: time.Now().Format(time.RFC3339),
	}
	if h.engine == "postgres" {
		_ = h.db.QueryRowContext(ctx, "SELECT version()").Scan(&info.Version)
		_ = h.db.QueryRowContext(ctx, "SELECT pg_database_size(current_database())").Scan(&info.SizeBytes)
	} else {
		_ = h.db.QueryRowContext(ctx, "SELECT sqlite_version()").Scan(&info.Version)
		if h.filePath != "" {
			if st, err := os.Stat(h.filePath); err == nil {
				info.SizeBytes = st.Size()
			}
		}
	}
	names, err := h.listTables(ctx)
	if err != nil {
		return info, err
	}
	info.TableCount = len(names)
	return info, nil
}

// ListDBTables 数据表列表与统计
func (h *dbAdminHelper) ListDBTables(ctx context.Context) ([]DBTableInfo, error) {
	names, err := h.listTables(ctx)
	if err != nil {
		return nil, err
	}
	var list []DBTableInfo
	for _, name := range names {
		t := DBTableInfo{Name: name}
		if h.engine == "postgres" {
			var estimated int64
			_ = h.db.QueryRowContext(ctx, `
				SELECT COALESCE(t.reltuples::bigint, -1),
				       pg_total_relation_size(c.oid),
				       (SELECT COUNT(*) FROM information_schema.columns col
				         WHERE col.table_schema='public' AND col.table_name=t.relname),
				       (SELECT COUNT(*) FROM pg_indexes ix WHERE ix.schemaname='public' AND ix.tablename=t.relname),
				       COALESCE(obj_description(c.oid), '')
				FROM pg_class t
				JOIN pg_namespace n ON n.oid = t.relnamespace
				JOIN pg_class c ON c.oid = t.oid
				WHERE t.relkind='r' AND n.nspname='public' AND t.relname=$1`, name).
				Scan(&estimated, &t.SizeBytes, &t.ColumnCount, &t.IndexCount, &t.Comment)
			if estimated >= 0 {
				t.Rows = estimated
				t.Approximate = true
			} else {
				// PG 15+ 未 ANALYZE 的表 reltuples 为 -1，回退精确计数
				_ = h.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM "+quoteIdent(name)).Scan(&t.Rows)
				t.Approximate = false
			}
		} else {
			_ = h.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM "+name).Scan(&t.Rows)
			t.Approximate = false
			cols, _ := h.tableColumns(ctx, name)
			t.ColumnCount = len(cols)
			if rows, err := h.db.QueryContext(ctx, "PRAGMA index_list("+name+")"); err == nil {
				for rows.Next() {
					t.IndexCount++
				}
				rows.Close()
			}
		}
		list = append(list, t)
	}
	return list, nil
}

// BrowseTable 分页浏览表数据
func (h *dbAdminHelper) BrowseTable(ctx context.Context, q TableBrowseQuery) (*TableBrowseResult, error) {
	q.Table = strings.TrimSpace(q.Table)
	if q.Table == "" {
		return nil, fmt.Errorf("缺少表名")
	}
	exists, err := h.tableExists(ctx, q.Table)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, fmt.Errorf("表不存在: %s", q.Table)
	}
	if q.Page <= 0 {
		q.Page = 1
	}
	if q.PageSize <= 0 || q.PageSize > 500 {
		q.PageSize = 100
	}

	cols, err := h.tableColumns(ctx, q.Table)
	if err != nil {
		return nil, err
	}
	if len(cols) == 0 {
		return &TableBrowseResult{Columns: []TableColumn{}, Rows: []map[string]any{}, Page: q.Page, PageSize: q.PageSize}, nil
	}

	quoted := quoteIdent(q.Table)
	var where string
	var args []any
	if k := strings.TrimSpace(q.Keyword); k != "" {
		var parts []string
		for _, c := range cols {
			if h.engine == "postgres" {
				// lib/pq 仅支持 $N 位置占位符
				parts = append(parts, fmt.Sprintf("CAST(%s AS TEXT) LIKE $%d ESCAPE '\\'", quoteIdent(c.Name), len(args)+1))
			} else {
				parts = append(parts, fmt.Sprintf("CAST(%s AS TEXT) LIKE ? ESCAPE '\\'", quoteIdent(c.Name)))
			}
			args = append(args, "%"+escapeLike(k)+"%")
		}
		where = " WHERE " + strings.Join(parts, " OR ")
	}

	var total int64
	countSQL := "SELECT COUNT(*) FROM " + quoted + where
	if err := h.db.QueryRowContext(ctx, countSQL, args...).Scan(&total); err != nil {
		return nil, err
	}

	orderCol := cols[0].Name
	if q.OrderBy != "" {
		found := false
		for _, c := range cols {
			if c.Name == q.OrderBy {
				orderCol = q.OrderBy
				found = true
				break
			}
		}
		if !found {
			return nil, fmt.Errorf("排序字段不存在: %s", q.OrderBy)
		}
	}
	dir := "ASC"
	if q.OrderDesc {
		dir = "DESC"
	}

	limit := q.PageSize
	offset := (q.Page - 1) * limit
	if offset < 0 {
		offset = 0
	}
	querySQL := fmt.Sprintf("SELECT * FROM %s%s ORDER BY %s %s LIMIT %d OFFSET %d",
		quoted, where, quoteIdent(orderCol), dir, limit, offset)

	rows, err := h.db.QueryContext(ctx, querySQL, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	colNames := make([]string, len(cols))
	for i, c := range cols {
		colNames[i] = c.Name
	}
	result := &TableBrowseResult{
		Columns:  cols,
		Rows:     []map[string]any{},
		Total:    total,
		Page:     q.Page,
		PageSize: q.PageSize,
	}
	for rows.Next() {
		vals := make([]any, len(colNames))
		ptrs := make([]any, len(colNames))
		for i := range vals {
			ptrs[i] = &vals[i]
		}
		if err := rows.Scan(ptrs...); err != nil {
			return nil, err
		}
		rowMap := make(map[string]any, len(colNames))
		for i, name := range colNames {
			rowMap[name] = normalizeDBValue(vals[i])
			if name == "password_hash" {
				rowMap[name] = "[已隐藏]"
			}
		}
		result.Rows = append(result.Rows, rowMap)
	}
	return result, rows.Err()
}

// BackupDatabase 导出全部（或指定）业务表为 JSON 备份文件
func (h *dbAdminHelper) BackupDatabase(ctx context.Context, opts BackupOptions) (*BackupResult, error) {
	if err := os.MkdirAll(h.backupsDir, 0o755); err != nil {
		return nil, fmt.Errorf("创建备份目录失败: %w", err)
	}

	names, err := h.listTables(ctx)
	if err != nil {
		return nil, err
	}
	if len(opts.Tables) > 0 {
		allowed := make(map[string]bool, len(names))
		for _, n := range names {
			allowed[n] = true
		}
		var filtered []string
		for _, t := range opts.Tables {
			if allowed[t] {
				filtered = append(filtered, t)
			}
		}
		names = filtered
	}
	if len(names) == 0 {
		return nil, fmt.Errorf("没有可备份的数据表")
	}
	sort.Strings(names)

	backup := backupFile{
		Format:    backupFormat,
		Version:   1,
		Engine:    h.engine,
		CreatedAt: time.Now().Format(time.RFC3339),
	}
	var totalRows int64
	for _, name := range names {
		colNames, err := h.tableColumnNames(ctx, name)
		if err != nil {
			return nil, err
		}
		bt := backupTable{Name: name, Columns: colNames}
		querySQL := "SELECT * FROM " + quoteIdent(name)
		rows, err := h.db.QueryContext(ctx, querySQL)
		if err != nil {
			return nil, fmt.Errorf("导出表 %s 失败: %w", name, err)
		}
		for rows.Next() {
			vals := make([]any, len(colNames))
			ptrs := make([]any, len(colNames))
			for i := range vals {
				ptrs[i] = &vals[i]
			}
			if err := rows.Scan(ptrs...); err != nil {
				rows.Close()
				return nil, err
			}
			row := make([]any, len(vals))
			for i, v := range vals {
				row[i] = normalizeDBValue(v)
			}
			bt.Rows = append(bt.Rows, row)
			totalRows++
		}
		if err := rows.Err(); err != nil {
			rows.Close()
			return nil, err
		}
		rows.Close()
		backup.Tables = append(backup.Tables, bt)
	}

	// 同秒内可能连续创建多次备份，追加毫秒后缀避免文件名冲突覆盖
	stamp := time.Now()
	filename := fmt.Sprintf("backup_%s_%03d.json", stamp.Format("20060102_150405"), stamp.Nanosecond()/1e6)
	filePath := filepath.Join(h.backupsDir, filename)
	data, err := json.Marshal(backup)
	if err != nil {
		return nil, err
	}
	if err := os.WriteFile(filePath, data, 0o644); err != nil {
		return nil, err
	}
	return &BackupResult{
		Filename:  filename,
		FilePath:  filePath,
		SizeBytes: int64(len(data)),
		Tables:    len(backup.Tables),
		Rows:      totalRows,
		CreatedAt: backup.CreatedAt,
	}, nil
}

// ListBackups 读取备份目录中的备份文件列表
func (h *dbAdminHelper) ListBackups(ctx context.Context) ([]BackupMeta, error) {
	entries, err := os.ReadDir(h.backupsDir)
	if err != nil {
		if os.IsNotExist(err) {
			return []BackupMeta{}, nil
		}
		return nil, err
	}
	var list []BackupMeta
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".json") {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		meta := BackupMeta{
			Filename:  e.Name(),
			SizeBytes: info.Size(),
			CreatedAt: info.ModTime().Format(time.RFC3339),
		}
		if bf, err := readBackupHeader(filepath.Join(h.backupsDir, e.Name())); err == nil {
			meta.Engine = bf.Engine
			meta.Tables = len(bf.Tables)
			meta.CreatedAt = bf.CreatedAt
			for _, t := range bf.Tables {
				meta.Rows += int64(len(t.Rows))
			}
		}
		list = append(list, meta)
	}
	sort.Slice(list, func(i, j int) bool { return list[i].Filename > list[j].Filename })
	return list, nil
}

// DeleteBackup 删除备份文件
func (h *dbAdminHelper) DeleteBackup(ctx context.Context, filename string) error {
	filename = filepath.Base(filename)
	if !strings.HasSuffix(filename, ".json") {
		return fmt.Errorf("非法备份文件名")
	}
	filePath := filepath.Join(h.backupsDir, filename)
	if err := os.Remove(filePath); err != nil {
		if os.IsNotExist(err) {
			return fmt.Errorf("备份文件不存在: %s", filename)
		}
		return err
	}
	return nil
}

// PreviewRestore 恢复预览（dry-run）：读取备份文件头信息并校验引擎一致性，不写入任何数据
func (h *dbAdminHelper) PreviewRestore(ctx context.Context, filename, mode string) (*RestorePreview, error) {
	if mode != "merge" && mode != "replace" {
		return nil, fmt.Errorf("mode 仅支持 merge / replace")
	}
	filename = filepath.Base(strings.TrimSpace(filename))
	bf, err := readBackupHeader(filepath.Join(h.backupsDir, filename))
	if err != nil {
		return nil, err
	}
	if bf.Engine != h.engine {
		return nil, fmt.Errorf("备份引擎 %s 与当前数据库 %s 不一致", bf.Engine, h.engine)
	}
	preview := &RestorePreview{
		File:      filename,
		Mode:      mode,
		Engine:    bf.Engine,
		CreatedAt: bf.CreatedAt,
		Tables:    []RestorePreviewTable{},
	}
	for _, bt := range bf.Tables {
		exists, err := h.tableExists(ctx, bt.Name)
		if err != nil {
			return nil, err
		}
		preview.Tables = append(preview.Tables, RestorePreviewTable{Name: bt.Name, Rows: len(bt.Rows), Exists: exists})
	}
	return preview, nil
}

// RestoreDatabase 从备份文件恢复
// mode=merge 合并导入（主键冲突跳过）；mode=replace 清空目标表后导入（危险，需调用方确认）
func (h *dbAdminHelper) RestoreDatabase(ctx context.Context, filename, mode string) (*RestoreResult, error) {
	if mode != "merge" && mode != "replace" {
		return nil, fmt.Errorf("mode 仅支持 merge / replace")
	}
	filename = filepath.Base(filename)
	filePath := filepath.Join(h.backupsDir, filename)
	bf, err := readBackupHeader(filePath)
	if err != nil {
		return nil, err
	}
	if bf.Engine != h.engine {
		return nil, fmt.Errorf("备份引擎 %s 与当前数据库 %s 不一致", bf.Engine, h.engine)
	}

	result := &RestoreResult{File: filename, Mode: mode, Tables: len(bf.Tables)}

	// 事务开始前预取现存表名：SQLite 连接池为单连接，事务内再开新查询会死锁
	existingTables, err := h.listTables(ctx)
	if err != nil {
		return nil, err
	}
	existsSet := make(map[string]bool, len(existingTables))
	for _, name := range existingTables {
		existsSet[name] = true
	}

	// 事务开始前预取各表列类型：PG 的 jsonb 列无法接受 text 参数，需要显式 CAST
	colTypes := make(map[string]map[string]string)
	// 事务开始前预取各表 id 序列名：pg_get_serial_sequence 对不存在的列会直接报错，
	// 必须在事务外探测，否则会把恢复事务置为 aborted 状态
	serialSeqs := make(map[string]string)
	for _, bt := range bf.Tables {
		if !existsSet[bt.Name] {
			continue
		}
		cols, err := h.tableColumns(ctx, bt.Name)
		if err != nil {
			return nil, err
		}
		m := make(map[string]string, len(cols))
		hasID := false
		for _, c := range cols {
			m[c.Name] = strings.ToLower(c.DataType)
			if c.Name == "id" {
				hasID = true
			}
		}
		colTypes[bt.Name] = m
		if h.engine == "postgres" && hasID {
			var seqName sql.NullString
			if err := h.db.QueryRowContext(ctx, "SELECT pg_get_serial_sequence($1,'id')", bt.Name).Scan(&seqName); err == nil && seqName.Valid {
				serialSeqs[bt.Name] = seqName.String
			}
		}
	}

	start := time.Now()
	tx, err := h.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	// PG 的 replace 模式：外键约束下逐表 TRUNCATE 会失败，
	// 对本次恢复涉及的全部已存在表一次性 TRUNCATE ... CASCADE
	if mode == "replace" && h.engine == "postgres" {
		var targets []string
		for _, bt := range bf.Tables {
			if existsSet[bt.Name] {
				targets = append(targets, quoteIdent(bt.Name))
			}
		}
		if len(targets) > 0 {
			if _, err := tx.ExecContext(ctx, "TRUNCATE TABLE "+strings.Join(targets, ", ")+" CASCADE"); err != nil {
				return nil, err
			}
		}
	}

	for _, bt := range bf.Tables {
		if !existsSet[bt.Name] {
			continue
		}
		if mode == "replace" && h.engine != "postgres" {
			if _, err := tx.ExecContext(ctx, "DELETE FROM "+quoteIdent(bt.Name)); err != nil {
				return nil, err
			}
		}
		// PG 中任何语句错误都会使事务进入 aborted 状态，行级失败必须用 SAVEPOINT 隔离
		useSavepoints := h.engine == "postgres"
		for _, row := range bt.Rows {
			if len(row) != len(bt.Columns) {
				continue
			}
			args := make([]any, len(row))
			for i, v := range row {
				args[i] = restoreValue(v)
			}
			sqlStmt := buildInsertSQL(h.engine, bt.Name, bt.Columns, colTypes[bt.Name])
			if useSavepoints {
				_, _ = tx.ExecContext(ctx, "SAVEPOINT restore_row")
			}
			res, err := tx.ExecContext(ctx, sqlStmt, args...)
			if err != nil {
				if useSavepoints {
					_, _ = tx.ExecContext(ctx, "ROLLBACK TO SAVEPOINT restore_row")
				}
				result.Skipped++
				continue
			}
			if useSavepoints {
				_, _ = tx.ExecContext(ctx, "RELEASE SAVEPOINT restore_row")
			}
			// INSERT OR IGNORE / ON CONFLICT DO NOTHING 冲突时静默跳过，Exec 不报错
			if affected, err := res.RowsAffected(); err != nil || affected == 0 {
				result.Skipped++
			} else {
				result.Inserted++
			}
		}
	}
	// PG：恢复写入显式主键后校正 SERIAL 序列，避免后续业务插入主键冲突。
	// 序列名已在事务外探测完毕，无序列的表在此直接跳过。
	if h.engine == "postgres" {
		for name, seq := range serialSeqs {
			_, _ = tx.ExecContext(ctx, fmt.Sprintf(
				`SELECT setval('%s', COALESCE((SELECT MAX(id) FROM %s),1), COALESCE((SELECT MAX(id) FROM %s),0) > 0)`,
				seq, quoteIdent(name), quoteIdent(name)))
		}
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}
	result.Elapsed = time.Since(start).Round(time.Millisecond).String()
	return result, nil
}

// RunCleanup 执行数据清理维护动作
func (h *dbAdminHelper) RunCleanup(ctx context.Context, actions []string) ([]CleanupResult, error) {
	var results []CleanupResult
	for _, action := range actions {
		res := CleanupResult{Action: action}
		action = strings.TrimSpace(strings.ToLower(action))
		switch action {
		case "vacuum":
			if h.engine == "postgres" {
				_, err := h.db.ExecContext(ctx, "VACUUM (ANALYZE)")
				if err != nil {
					res.Error = err.Error()
				}
			} else {
				_, err := h.db.ExecContext(ctx, "VACUUM")
				if err != nil {
					res.Error = err.Error()
				}
			}
		case "orphan_play_sources":
			ok, _ := h.tableExists(ctx, "play_sources")
			if !ok {
				res.Error = "当前引擎无 play_sources 表（PostgreSQL 使用 videos.play_groups）"
			} else if n, err := h.deleteWhere(ctx, `
				DELETE FROM play_sources WHERE NOT EXISTS (SELECT 1 FROM videos v WHERE v.id = play_sources.video_id)`); err != nil {
				res.Error = err.Error()
			} else {
				res.Affected = n
			}
		case "dup_play_sources":
			ok, _ := h.tableExists(ctx, "play_sources")
			if !ok {
				res.Error = "当前引擎无 play_sources 表"
			} else if n, err := h.deleteWhere(ctx, `
				DELETE FROM play_sources WHERE id NOT IN (
					SELECT MAX(id) FROM play_sources
					GROUP BY video_id, player_code, COALESCE(source_id, ''))`); err != nil {
				res.Error = err.Error()
			} else {
				res.Affected = n
			}
		case "orphan_comments":
			ok, _ := h.tableExists(ctx, "comments")
			if !ok {
				res.Error = "comments 表不存在"
			} else if n, err := h.deleteWhere(ctx, `
				DELETE FROM comments WHERE target_type = 'video'
					AND NOT EXISTS (SELECT 1 FROM videos v WHERE v.id = comments.target_id)`); err != nil {
				res.Error = err.Error()
			} else {
				res.Affected = n
			}
		case "orphan_user_history":
			ok, _ := h.tableExists(ctx, "user_history")
			if !ok {
				res.Error = "user_history 表不存在"
			} else if n, err := h.deleteWhere(ctx, `
				DELETE FROM user_history WHERE NOT EXISTS (SELECT 1 FROM videos v WHERE v.id = user_history.video_id)`); err != nil {
				res.Error = err.Error()
			} else {
				res.Affected = n
			}
		case "orphan_user_favorites":
			ok, _ := h.tableExists(ctx, "user_favorites")
			if !ok {
				res.Error = "user_favorites 表不存在"
			} else if err := func() error {
				n, err := h.deleteWhere(ctx, `
					DELETE FROM user_favorites WHERE NOT EXISTS (SELECT 1 FROM videos v WHERE v.id = user_favorites.video_id)`)
				if err == nil {
					res.Affected = n
				}
				return err
			}(); err != nil {
				res.Error = err.Error()
			}
		case "clear_user_history":
			ok, _ := h.tableExists(ctx, "user_history")
			if !ok {
				res.Error = "user_history 表不存在"
			} else if n, err := h.deleteWhere(ctx, "DELETE FROM user_history"); err != nil {
				res.Error = err.Error()
			} else {
				res.Affected = n
			}
		case "clear_feedbacks":
			ok, _ := h.tableExists(ctx, "feedbacks")
			if !ok {
				res.Error = "feedbacks 表不存在"
			} else if n, err := h.deleteWhere(ctx, "DELETE FROM feedbacks"); err != nil {
				res.Error = err.Error()
			} else {
				res.Affected = n
			}
		default:
			res.Error = "未知清理动作: " + action
		}
		results = append(results, res)
	}
	return results, nil
}

// deleteWhere 执行删除类 SQL 并返回影响行数
func (h *dbAdminHelper) deleteWhere(ctx context.Context, sql string) (int64, error) {
	r, err := h.db.ExecContext(ctx, sql)
	if err != nil {
		return 0, err
	}
	return r.RowsAffected()
}

// ExecSQL 执行单条管理 SQL。写语句与 DDL 需要调用方在 API 层确认后调用。
func (h *dbAdminHelper) ExecSQL(ctx context.Context, statement string) (*SQLExecResult, error) {
	statement = strings.TrimSpace(statement)
	if statement == "" {
		return nil, fmt.Errorf("SQL 不能为空")
	}
	if !singleStatement(statement) {
		return nil, fmt.Errorf("仅支持单条 SQL 语句，不允许分号分隔多条")
	}

	result := &SQLExecResult{}
	switch classifySQL(statement) {
	case "select":
		result.Type = "select"
		ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
		defer cancel()
		rows, err := h.db.QueryContext(ctx, statement)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		colNames, err := rows.Columns()
		if err != nil {
			return nil, err
		}
		result.Columns = colNames
		result.Rows = []map[string]any{}
		for rows.Next() {
			vals := make([]any, len(colNames))
			ptrs := make([]any, len(colNames))
			for i := range vals {
				ptrs[i] = &vals[i]
			}
			if err := rows.Scan(ptrs...); err != nil {
				return nil, err
			}
			rowMap := make(map[string]any, len(colNames))
			for i, name := range colNames {
				rowMap[name] = normalizeDBValue(vals[i])
			}
			result.Rows = append(result.Rows, rowMap)
		}
		result.Truncated = len(result.Rows) > 1000
		if len(result.Rows) > 1000 {
			result.Rows = result.Rows[:1000]
		}
		result.RowCount = len(result.Rows)
	default:
		if classifySQL(statement) == "write" {
			result.Type = "write"
		} else {
			result.Type = "ddl"
		}
		ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
		defer cancel()
		r, err := h.db.ExecContext(ctx, statement)
		if err != nil {
			return nil, err
		}
		affected, err := r.RowsAffected()
		if err == nil {
			result.Affected = affected
		}
		result.Message = "语句执行成功"
	}
	return result, nil
}

// --- 内部工具 ---

func quoteIdent(name string) string {
	return `"` + strings.ReplaceAll(name, `"`, `""`) + `"`
}

// normalizeDBValue 将数据库扫描值归一化为 JSON 友好类型
func normalizeDBValue(v any) any {
	switch t := v.(type) {
	case nil:
		return nil
	case []byte:
		return string(t)
	case time.Time:
		return t.Format(time.RFC3339)
	case bool, int64, float64, string:
		return t
	default:
		return fmt.Sprintf("%v", t)
	}
}

// restoreValue 恢复时把 JSON 数值还原为适合 SQL 驱动的类型
func restoreValue(v any) any {
	if f, ok := v.(float64); ok && f == math.Trunc(f) && math.Abs(f) < 1e15 {
		return int64(f)
	}
	return v
}

// escapeLike 转义 LIKE 通配符（% 与 _ 按字面匹配）
func escapeLike(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `%`, `\%`)
	s = strings.ReplaceAll(s, `_`, `\_`)
	return s
}

func buildInsertSQL(engine, table string, columns []string, colTypes map[string]string) string {
	quotedCols := make([]string, len(columns))
	placeholders := make([]string, len(columns))
	for i, c := range columns {
		quotedCols[i] = quoteIdent(c)
		if engine == "postgres" {
			placeholder := fmt.Sprintf("$%d", i+1)
			// json/jsonb 列不接受 text 参数，必须显式转换（lib/pq 传参均为 text）
			if t := colTypes[c]; t == "jsonb" || t == "json" {
				placeholder += "::jsonb"
			}
			placeholders[i] = placeholder
		} else {
			placeholders[i] = "?"
		}
	}
	insert := fmt.Sprintf("INSERT INTO %s (%s) VALUES (%s)",
		quoteIdent(table), strings.Join(quotedCols, ", "), strings.Join(placeholders, ", "))
	if engine == "postgres" {
		insert += " ON CONFLICT DO NOTHING"
	} else {
		insert = strings.Replace(insert, "INSERT INTO", "INSERT OR IGNORE INTO", 1)
	}
	return insert
}

// readBackupHeader 读取备份文件整体（文件较小，直接解析）
func readBackupHeader(filePath string) (*backupFile, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, err
	}
	var bf backupFile
	if err := json.Unmarshal(data, &bf); err != nil {
		return nil, fmt.Errorf("备份文件格式无效: %w", err)
	}
	if bf.Format != backupFormat {
		return nil, fmt.Errorf("不是有效的备份文件")
	}
	return &bf, nil
}

// singleStatement 检查是否为单条语句（引号内的分号不计）
// IsSingleStatement 检查是否为单条 SQL 语句（引号内的分号不计），供 API 层在确认前预校验
func IsSingleStatement(s string) bool { return singleStatement(s) }

func singleStatement(s string) bool {
	s = strings.TrimRight(s, " \t\r\n;")
	inSingle, inDouble := false, false
	for i := 0; i < len(s); i++ {
		ch := s[i]
		switch {
		case ch == '\'' && !inDouble:
			if inSingle && i+1 < len(s) && s[i+1] == '\'' {
				i++ // 转义引号 ''
				continue
			}
			inSingle = !inSingle
		case ch == '"' && !inSingle:
			if inDouble && i+1 < len(s) && s[i+1] == '"' {
				i++
				continue
			}
			inDouble = !inDouble
		case ch == ';' && !inSingle && !inDouble:
			return false
		}
	}
	return true
}

// classifySQL 简单分类 SQL 语句类型
func classifySQL(s string) string {
	s = strings.ToUpper(strings.TrimSpace(s))
	switch {
	case strings.HasPrefix(s, "SELECT"), strings.HasPrefix(s, "WITH"),
		strings.HasPrefix(s, "EXPLAIN"), strings.HasPrefix(s, "SHOW"),
		strings.HasPrefix(s, "PRAGMA"), strings.HasPrefix(s, "VALUES"),
		strings.HasPrefix(s, "DESCRIBE"):
		return "select"
	case strings.HasPrefix(s, "INSERT"), strings.HasPrefix(s, "UPDATE"),
		strings.HasPrefix(s, "DELETE"), strings.HasPrefix(s, "REPLACE"):
		return "write"
	default:
		return "ddl"
	}
}

// ClassifySQL 对 SQL 语句做只读/写/DDL 三态分类，供 API 层决定是否需要二次确认
func ClassifySQL(s string) string { return classifySQL(s) }
