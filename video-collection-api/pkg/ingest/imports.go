package ingest

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/csv"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"unicode/utf8"

	_ "github.com/go-sql-driver/mysql"
	_ "github.com/lib/pq"
	_ "github.com/microsoft/go-mssqldb"
	"github.com/xuri/excelize/v2"
	_ "modernc.org/sqlite"
	"video-collection-api/config"
)

var fileToken = regexp.MustCompile(`^[a-f0-9]{32}\.(xlsx|csv)$`)
var forbiddenSQL = regexp.MustCompile(`(?i)\b(insert|update|delete|drop|alter|create|attach|detach|pragma|exec|execute|call|into|load_file|outfile|sleep|benchmark|pg_sleep|dblink)\b|;|--|/\*`)

func validateQuery(query string) error {
	q := strings.TrimSpace(query)
	if !strings.HasPrefix(strings.ToUpper(q), "SELECT ") || forbiddenSQL.MatchString(q) {
		return fmt.Errorf("仅支持单条 SELECT 查询，不允许注释、分号、写操作或 SELECT INTO")
	}
	return nil
}

func databaseRows(ctx context.Context, p *config.PipelineRule, limit int, emit func(Sample) error) error {
	dsn := os.Getenv(p.Database.DSNEnv)
	if dsn == "" {
		return fmt.Errorf("服务端未设置连接串环境变量 %s", p.Database.DSNEnv)
	}
	db, err := sql.Open(p.Database.Driver, dsn)
	if err != nil {
		return fmt.Errorf("数据库连接配置无效")
	}
	defer db.Close()
	db.SetMaxOpenConns(1)
	conn, err := db.Conn(ctx)
	if err != nil {
		return fmt.Errorf("数据库连接失败，请检查服务端连接串与只读账号")
	}
	defer conn.Close()
	if p.Database.Driver == "sqlite" {
		if _, err := conn.ExecContext(ctx, "PRAGMA query_only = ON"); err != nil {
			return fmt.Errorf("无法启用 SQLite 只读模式")
		}
	}
	options := &sql.TxOptions{ReadOnly: p.Database.Driver == "postgres" || p.Database.Driver == "mysql"}
	tx, err := conn.BeginTx(ctx, options)
	if err != nil {
		return fmt.Errorf("无法启动数据库读取事务")
	}
	defer tx.Rollback()
	query := fmt.Sprintf("SELECT * FROM (%s) AS import_source LIMIT %d", p.Database.Query, limit)
	if p.Database.Driver == "sqlserver" {
		query = fmt.Sprintf("SELECT TOP (%d) * FROM (%s) AS import_source", limit, p.Database.Query)
	}
	rows, err := tx.QueryContext(ctx, query)
	if err != nil {
		return fmt.Errorf("SELECT 查询失败，请检查列名、查询语法及只读权限")
	}
	defer rows.Close()
	columns, err := rows.Columns()
	if err != nil {
		return err
	}
	for rows.Next() {
		values := make([]any, len(columns))
		refs := make([]any, len(columns))
		for i := range values {
			refs[i] = &values[i]
		}
		if err := rows.Scan(refs...); err != nil {
			return fmt.Errorf("数据库记录读取失败")
		}
		obj := map[string]string{}
		for i, c := range columns {
			if b, ok := values[i].([]byte); ok {
				obj[c] = string(b)
			} else if values[i] != nil {
				obj[c] = fmt.Sprint(values[i])
			}
		}
		if err := emit(mapColumns(p, obj)); err != nil {
			return err
		}
	}
	if rows.Err() != nil {
		return fmt.Errorf("数据库读取中断")
	}
	return nil
}

func uploadDir() string {
	if dir := os.Getenv("COLLECTION_UPLOAD_DIR"); dir != "" {
		return dir
	}
	return filepath.Join("data", "collection-imports")
}

// SaveUpload accepts data only; clients cannot choose or traverse server paths.
func SaveUpload(name string, reader io.Reader) (string, error) {
	ext := strings.ToLower(filepath.Ext(name))
	if ext != ".xlsx" && ext != ".csv" {
		return "", fmt.Errorf("支持 .xlsx 和 UTF-8 .csv；旧 .xls 请另存为 .xlsx")
	}
	if err := os.MkdirAll(uploadDir(), 0700); err != nil {
		return "", err
	}
	var id [16]byte
	if _, err := rand.Read(id[:]); err != nil {
		return "", err
	}
	token := hex.EncodeToString(id[:]) + ext
	path := filepath.Join(uploadDir(), token)
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return "", err
	}
	n, err := io.Copy(f, io.LimitReader(reader, 20*1024*1024+1))
	closeErr := f.Close()
	if err != nil || closeErr != nil || n > 20*1024*1024 {
		_ = os.Remove(path)
		return "", fmt.Errorf("上传失败或文件超过 20 MB")
	}
	return token, nil
}

func mapColumns(p *config.PipelineRule, obj map[string]string) Sample {
	raw := map[string]string{}
	for _, f := range p.Fields {
		raw[f.Target] = obj[f.Selector]
	}
	return MapRecord(p, raw)
}

func fileRows(ctx context.Context, p *config.PipelineRule, limit int, emit func(Sample) error) error {
	path := filepath.Join(uploadDir(), p.File.Token)
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("导入文件不存在，请重新上传")
	}
	defer f.Close()
	var next func() ([]string, error)
	if strings.HasSuffix(p.File.Token, ".csv") {
		r := csv.NewReader(f)
		r.FieldsPerRecord = -1
		next = r.Read
	} else {
		book, err := excelize.OpenReader(f, excelize.Options{UnzipSizeLimit: 100 * 1024 * 1024, UnzipXMLSizeLimit: 10 * 1024 * 1024})
		if err != nil {
			return fmt.Errorf("无法读取 Excel 文件")
		}
		defer book.Close()
		sheet := p.File.Sheet
		if sheet == "" {
			list := book.GetSheetList()
			if len(list) == 0 {
				return fmt.Errorf("Excel 没有工作表")
			}
			sheet = list[0]
		}
		rows, err := book.Rows(sheet)
		if err != nil {
			return fmt.Errorf("工作表 %q 不存在", sheet)
		}
		defer rows.Close()
		next = func() ([]string, error) {
			if !rows.Next() {
				if err := rows.Error(); err != nil {
					return nil, err
				}
				return nil, io.EOF
			}
			return rows.Columns()
		}
	}
	var headers []string
	for i := 0; i < p.File.HeaderRow; i++ {
		headers, err = next()
		if err != nil {
			return fmt.Errorf("无法读取表头行")
		}
	}
	seen := map[string]bool{}
	for i, h := range headers {
		h = strings.TrimSpace(strings.TrimPrefix(h, "\ufeff"))
		if !utf8.ValidString(h) || h == "" || seen[h] {
			return fmt.Errorf("表头必须是非空、唯一的 UTF-8 列名")
		}
		headers[i] = h
		seen[h] = true
	}
	for _, field := range p.Fields {
		if field.Selector != "" && !seen[field.Selector] {
			return fmt.Errorf("文件中不存在列 %q", field.Selector)
		}
	}
	for i := 0; i < limit; {
		if err := ctx.Err(); err != nil {
			return err
		}
		row, err := next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("读取文件行失败: %w", err)
		}
		if strings.TrimSpace(strings.Join(row, "")) == "" {
			continue
		}
		obj := map[string]string{}
		for j, h := range headers {
			if j < len(row) {
				if !utf8.ValidString(row[j]) {
					return fmt.Errorf("CSV 请使用 UTF-8 编码")
				}
				obj[h] = row[j]
			}
		}
		if err := emit(mapColumns(p, obj)); err != nil {
			return err
		}
		i++
	}
	return nil
}
