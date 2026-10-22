package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"math"
	"regexp"
	"strconv"
	"strings"
	"time"

	"video-collection-service/config"
)

// BusinessType routes a public slug to a controlled writer. TableName is never
// accepted from clients; custom tables are always derived from the validated slug.
type BusinessType struct {
	Slug        string              `json:"slug"`
	Name        string              `json:"name"`
	Description string              `json:"description"`
	IsSystem    bool                `json:"is_system"`
	TableName   string              `json:"table_name"`
	Writer      string              `json:"writer"`
	KeyField    string              `json:"key_field"`
	CreatedAt   string              `json:"created_at"`
	UpdatedAt   string              `json:"updated_at"`
	Fields      []BusinessTypeField `json:"fields"`
}

type BusinessTypeField struct {
	Name      string `json:"name"`
	Label     string `json:"label"`
	DataType  string `json:"data_type"`
	Required  bool   `json:"required"`
	IsSystem  bool   `json:"is_system"`
	SortOrder int    `json:"sort_order"`
}

type BusinessTypeStore interface {
	ListBusinessTypes(context.Context) ([]BusinessType, error)
	GetBusinessType(context.Context, string) (*BusinessType, error)
	CreateBusinessType(context.Context, BusinessType) error
	UpdateBusinessType(context.Context, string, string, string) error
	DeleteBusinessType(context.Context, string) error
	AddBusinessTypeField(context.Context, string, BusinessTypeField) error
	UpdateBusinessTypeField(context.Context, string, string, BusinessTypeField) error
	DeleteBusinessTypeField(context.Context, string, string) error
}

var businessName = regexp.MustCompile(`^[a-z][a-z0-9_]{1,47}$`)
var businessColumn = regexp.MustCompile(`^[a-z][a-z0-9_]{0,47}$`)
var businessSQLTypes = map[string]string{"text": "TEXT", "integer": "BIGINT", "real": "DOUBLE PRECISION", "boolean": "BOOLEAN", "json": "TEXT"}
var businessReservedColumns = map[string]bool{"id": true, "record_key": true, "source_id": true, "payload": true, "created_at": true, "updated_at": true}

func migrateBusinessTypes(tx *sql.Tx) error {
	_, err := tx.Exec(`CREATE TABLE IF NOT EXISTS business_types (
 slug TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
 is_system BOOLEAN NOT NULL DEFAULT FALSE, table_name TEXT NOT NULL DEFAULT '',
 writer TEXT NOT NULL, key_field TEXT NOT NULL DEFAULT 'id', created_at TEXT NOT NULL, updated_at TEXT NOT NULL
 );
 CREATE TABLE IF NOT EXISTS business_type_fields (
 type_slug TEXT NOT NULL REFERENCES business_types(slug) ON DELETE CASCADE,
 name TEXT NOT NULL, label TEXT NOT NULL, data_type TEXT NOT NULL,
 required BOOLEAN NOT NULL DEFAULT FALSE, is_system BOOLEAN NOT NULL DEFAULT FALSE,
 sort_order INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(type_slug,name)
 );`)
	if err != nil {
		return err
	}
	seeds := []BusinessType{
		{Slug: "record", Name: "通用数据", Description: "保留映射字段，保存到采集结果，供后续业务处理。", Writer: "record", KeyField: "id"},
		{Slug: "article", Name: "文章", Description: "映射 title、content，写入既有资讯草稿并保留采集记录。", Writer: "article", KeyField: "title"},
		{Slug: "video", Name: "视频", Description: "映射 title、播放链接和影视信息，写入现有视频仓库。", Writer: "video", KeyField: "title"},
	}
	now := time.Now().UTC().Format(time.RFC3339Nano)
	for _, b := range seeds {
		if _, err = tx.Exec(`INSERT INTO business_types(slug,name,description,is_system,writer,key_field,created_at,updated_at) VALUES($1,$2,$3,TRUE,$4,$5,$6,$6) ON CONFLICT(slug) DO NOTHING`, b.Slug, b.Name, b.Description, b.Writer, b.KeyField, now); err != nil {
			return err
		}
		names := []string{"title", "content"}
		if b.Slug == "article" {
			names = append(names, "summary", "cover", "category", "url", "source_name", "published_at", "status")
		}
		if b.Slug == "video" {
			names = append(names, "play_url", "play_from", "play_server", "play_note", "cover", "category", "year", "actor", "director", "area", "remarks", "sub_name")
		}
		for i, n := range names {
			required := (n == "title" && b.Slug != "record") || (n == "content" && b.Slug == "article")
			if _, err = tx.Exec(`INSERT INTO business_type_fields(type_slug,name,label,data_type,required,is_system,sort_order) VALUES($1,$2,$2,'text',$3,TRUE,$4) ON CONFLICT(type_slug,name) DO NOTHING`, b.Slug, n, required, i); err != nil {
				return err
			}
		}
	}
	return nil
}

type businessQuerier interface {
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

func getBusinessType(ctx context.Context, q businessQuerier, slug string) (*BusinessType, error) {
	b := &BusinessType{Fields: []BusinessTypeField{}}
	err := q.QueryRowContext(ctx, `SELECT slug,name,description,is_system,table_name,writer,key_field,created_at,updated_at FROM business_types WHERE slug=$1`, slug).Scan(&b.Slug, &b.Name, &b.Description, &b.IsSystem, &b.TableName, &b.Writer, &b.KeyField, &b.CreatedAt, &b.UpdatedAt)
	if err != nil {
		return nil, err
	}
	rows, err := q.QueryContext(ctx, `SELECT name,label,data_type,required,is_system,sort_order FROM business_type_fields WHERE type_slug=$1 ORDER BY sort_order,name`, slug)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var f BusinessTypeField
		if err = rows.Scan(&f.Name, &f.Label, &f.DataType, &f.Required, &f.IsSystem, &f.SortOrder); err != nil {
			return nil, err
		}
		b.Fields = append(b.Fields, f)
	}
	return b, rows.Err()
}

func (s *SQLContentStore) GetBusinessType(ctx context.Context, slug string) (*BusinessType, error) {
	return getBusinessType(ctx, s.db, slug)
}
func (s *SQLContentStore) ListBusinessTypes(ctx context.Context) ([]BusinessType, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT slug FROM business_types ORDER BY is_system DESC,slug`)
	if err != nil {
		return nil, err
	}
	var slugs []string
	for rows.Next() {
		var slug string
		if err = rows.Scan(&slug); err != nil {
			rows.Close()
			return nil, err
		}
		slugs = append(slugs, slug)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return nil, err
	}
	result := []BusinessType{}
	for _, slug := range slugs {
		b, err := s.GetBusinessType(ctx, slug)
		if err != nil {
			return nil, err
		}
		result = append(result, *b)
	}
	return result, nil
}

func validBusinessField(f *BusinessTypeField) error {
	if !businessColumn.MatchString(f.Name) || businessReservedColumns[f.Name] {
		return fmt.Errorf("字段名无效或为保留字段: %s", f.Name)
	}
	if f.DataType == "" {
		f.DataType = "text"
	}
	if _, ok := businessSQLTypes[f.DataType]; !ok {
		return fmt.Errorf("不支持的字段类型: %s", f.DataType)
	}
	if f.Label == "" {
		f.Label = f.Name
	}
	return nil
}

func (s *SQLContentStore) CreateBusinessType(ctx context.Context, b BusinessType) error {
	if !businessName.MatchString(b.Slug) || strings.HasPrefix(b.Slug, "biz_") || b.Slug == "record" || b.Slug == "article" || b.Slug == "video" {
		return fmt.Errorf("类型标识须为 2–48 位小写字母、数字、下划线，以字母开头，且不能为系统类型或以 biz_ 开头")
	}
	if strings.TrimSpace(b.Name) == "" {
		return fmt.Errorf("类型名称不能为空")
	}
	seen := map[string]bool{}
	for i := range b.Fields {
		if err := validBusinessField(&b.Fields[i]); err != nil {
			return err
		}
		if seen[b.Fields[i].Name] {
			return fmt.Errorf("字段重复")
		}
		seen[b.Fields[i].Name] = true
		b.Fields[i].IsSystem = false
	}
	if len(b.Fields) > 100 {
		return fmt.Errorf("最多 100 个字段")
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	now := time.Now().UTC().Format(time.RFC3339Nano)
	table := "biz_" + b.Slug
	key := "id"
	if len(b.Fields) > 0 {
		key = b.Fields[0].Name
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO business_types(slug,name,description,is_system,table_name,writer,key_field,created_at,updated_at) VALUES($1,$2,$3,FALSE,$4,'table',$5,$6,$6)`, b.Slug, b.Name, b.Description, table, key, now)
	if err != nil {
		return err
	}
	id := "INTEGER PRIMARY KEY AUTOINCREMENT"
	if s.postgres {
		id = "SERIAL PRIMARY KEY"
	}
	cols := []string{"id " + id, "record_key TEXT NOT NULL UNIQUE", "source_id TEXT NOT NULL DEFAULT ''", "payload TEXT NOT NULL DEFAULT '{}'", "created_at TEXT NOT NULL", "updated_at TEXT NOT NULL"}
	for _, f := range b.Fields {
		cols = append(cols, quoteIdent(f.Name)+" "+businessSQLTypes[f.DataType])
		if err = insertBusinessField(ctx, tx, b.Slug, f); err != nil {
			return err
		}
	}
	if _, err = tx.ExecContext(ctx, "CREATE TABLE "+quoteIdent(table)+" ("+strings.Join(cols, ",")+")"); err != nil {
		return err
	}
	return tx.Commit()
}

func insertBusinessField(ctx context.Context, tx *sql.Tx, slug string, f BusinessTypeField) error {
	_, err := tx.ExecContext(ctx, `INSERT INTO business_type_fields(type_slug,name,label,data_type,required,is_system,sort_order) VALUES($1,$2,$3,$4,$5,FALSE,$6)`, slug, f.Name, f.Label, f.DataType, f.Required, f.SortOrder)
	return err
}
func (s *SQLContentStore) UpdateBusinessType(ctx context.Context, slug, name, description string) error {
	if strings.TrimSpace(name) == "" {
		return fmt.Errorf("类型名称不能为空")
	}
	res, err := s.db.ExecContext(ctx, `UPDATE business_types SET name=$1,description=$2,updated_at=$3 WHERE slug=$4`, name, description, time.Now().UTC().Format(time.RFC3339Nano), slug)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err == nil && n == 0 {
		return sql.ErrNoRows
	}
	return err
}

// Only unused custom types can be hard deleted. Existing records and source
// bindings must be removed first; deletion then drops the empty physical table.
func (s *SQLContentStore) DeleteBusinessType(ctx context.Context, slug string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	b, err := getBusinessType(ctx, tx, slug)
	if err != nil {
		return err
	}
	if b.IsSystem {
		return fmt.Errorf("系统业务类型不可删除")
	}
	var n int
	if err = tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM collection_records WHERE target=$1`, slug).Scan(&n); err != nil {
		return err
	}
	if n > 0 {
		return fmt.Errorf("业务类型已有采集记录，不能删除")
	}
	// Parse JSON in Go for identical behavior on SQLite and PostgreSQL.
	rows, err := tx.QueryContext(ctx, `SELECT filter_rules FROM sources`)
	if err != nil {
		return err
	}
	used := false
	for rows.Next() {
		var raw string
		if err = rows.Scan(&raw); err != nil {
			break
		}
		var f config.FilterRule
		if json.Unmarshal([]byte(raw), &f) == nil && f.Pipeline != nil && f.Pipeline.Target == slug {
			used = true
		}
	}
	rowErr := rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	if rowErr != nil {
		return rowErr
	}
	if used {
		return fmt.Errorf("业务类型仍被采集源使用")
	}
	if err = tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM "+quoteIdent(b.TableName)).Scan(&n); err != nil {
		return err
	}
	if n > 0 {
		return fmt.Errorf("业务表非空，不能删除")
	}
	if _, err = tx.ExecContext(ctx, "DROP TABLE "+quoteIdent(b.TableName)); err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, `DELETE FROM business_type_fields WHERE type_slug=$1`, slug); err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, `DELETE FROM business_types WHERE slug=$1`, slug); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *SQLContentStore) AddBusinessTypeField(ctx context.Context, slug string, f BusinessTypeField) error {
	if err := validBusinessField(&f); err != nil {
		return err
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	b, err := getBusinessType(ctx, tx, slug)
	if err != nil {
		return err
	}
	if len(b.Fields) >= 100 {
		return fmt.Errorf("最多 100 个字段")
	}
	if err = insertBusinessField(ctx, tx, slug, f); err != nil {
		return err
	}
	if b.Writer == "table" {
		if _, err = tx.ExecContext(ctx, "ALTER TABLE "+quoteIdent(b.TableName)+" ADD COLUMN "+quoteIdent(f.Name)+" "+businessSQLTypes[f.DataType]); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *SQLContentStore) UpdateBusinessTypeField(ctx context.Context, slug, name string, f BusinessTypeField) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	b, err := getBusinessType(ctx, tx, slug)
	if err != nil {
		return err
	}
	for _, old := range b.Fields {
		if old.Name == name {
			if (f.Name != "" && f.Name != name) || (f.DataType != "" && f.DataType != old.DataType) {
				return fmt.Errorf("字段名和数据类型不可修改")
			}
			if old.IsSystem && f.Required != old.Required {
				return fmt.Errorf("系统字段必填语义不可修改")
			}
			if f.Label == "" {
				f.Label = old.Label
			}
			_, err = tx.ExecContext(ctx, `UPDATE business_type_fields SET label=$1,required=$2 WHERE type_slug=$3 AND name=$4`, f.Label, f.Required, slug, name)
			if err != nil {
				return err
			}
			return tx.Commit()
		}
	}
	return sql.ErrNoRows
}
func (s *SQLContentStore) DeleteBusinessTypeField(ctx context.Context, slug, name string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	b, err := getBusinessType(ctx, tx, slug)
	if err != nil {
		return err
	}
	for _, f := range b.Fields {
		if f.Name == name {
			if f.IsSystem {
				return fmt.Errorf("系统字段不可删除")
			}
			if b.Writer == "table" {
				if _, err = tx.ExecContext(ctx, "ALTER TABLE "+quoteIdent(b.TableName)+" DROP COLUMN "+quoteIdent(name)); err != nil {
					return err
				}
			}
			if _, err = tx.ExecContext(ctx, `DELETE FROM business_type_fields WHERE type_slug=$1 AND name=$2`, slug, name); err != nil {
				return err
			}
			return tx.Commit()
		}
	}
	return sql.ErrNoRows
}

// ValidateBusinessValues applies schema requirements and converts mapped strings
// to driver values. Unknown mapping fields remain in payload for audit/flexibility.
func ValidateBusinessValues(b *BusinessType, values map[string]string) ([]any, error) {
	result := make([]any, 0, len(b.Fields))
	for _, f := range b.Fields {
		v := values[f.Name]
		if strings.TrimSpace(v) == "" {
			if f.Required {
				return nil, fmt.Errorf("%s: 必填字段为空", f.Name)
			}
			result = append(result, nil)
			continue
		}
		var value any = v
		var err error
		switch f.DataType {
		case "integer":
			value, err = strconv.ParseInt(v, 10, 64)
		case "real":
			var n float64
			n, err = strconv.ParseFloat(v, 64)
			if math.IsNaN(n) || math.IsInf(n, 0) {
				err = fmt.Errorf("须为有限数值")
			}
			value = n
		case "boolean":
			value, err = strconv.ParseBool(v)
		case "json":
			if !json.Valid([]byte(v)) {
				err = fmt.Errorf("JSON 无效")
			}
		}
		if err != nil {
			return nil, fmt.Errorf("%s (%s): %w", f.Name, f.DataType, err)
		}
		result = append(result, value)
	}
	return result, nil
}

func upsertBusinessRow(ctx context.Context, tx *sql.Tx, b *BusinessType, r CollectionRecord) (int, error) {
	values, err := ValidateBusinessValues(b, r.Values)
	if err != nil {
		return 0, err
	}
	payload, err := json.Marshal(r.Values)
	if err != nil {
		return 0, err
	}
	now := time.Now().UTC().Format(time.RFC3339Nano)
	// Namespacing by source preserves collection_records' (source,target,key)
	// identity even when two sources send the same external key.
	identity := businessRecordKey(r.SourceID, r.Key)
	args := []any{identity, r.SourceID, string(payload), now, now}
	cols := []string{"record_key", "source_id", "payload", "created_at", "updated_at"}
	updates := []string{"payload=excluded.payload", "updated_at=excluded.updated_at"}
	for i, f := range b.Fields {
		cols = append(cols, f.Name)
		args = append(args, values[i])
		updates = append(updates, quoteIdent(f.Name)+"=excluded."+quoteIdent(f.Name))
	}
	placeholders := make([]string, len(cols))
	for i := range cols {
		cols[i] = quoteIdent(cols[i])
		placeholders[i] = fmt.Sprintf("$%d", i+1)
	}
	var id int
	err = tx.QueryRowContext(ctx, "INSERT INTO "+quoteIdent(b.TableName)+" ("+strings.Join(cols, ",")+") VALUES ("+strings.Join(placeholders, ",")+") ON CONFLICT(record_key) DO UPDATE SET "+strings.Join(updates, ",")+" RETURNING id", args...).Scan(&id)
	// TODO(RAG): custom business rows need an explicit source_type/index adapter;
	// keep existing news/post and wiki indexing hooks unchanged until then.
	return id, err
}

// Encode the source namespace without ambiguous delimiters in external keys.
func businessRecordKey(source, key string) string {
	encoded, _ := json.Marshal([]string{source, key})
	return string(encoded)
}
