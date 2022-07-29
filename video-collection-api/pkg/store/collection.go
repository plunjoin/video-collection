package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"
)

type CollectionRecord struct {
	SourceID  string            `json:"source_id"`
	Target    string            `json:"target"`
	Key       string            `json:"key"`
	Values    map[string]string `json:"values"`
	ContentID int               `json:"content_id"`
	UpdatedAt string            `json:"updated_at"`
}

type CollectionStore interface {
	SaveCollectionRecord(context.Context, CollectionRecord, bool) (bool, error)
	ListCollectionRecords(context.Context, string, int, int) ([]CollectionRecord, int, error)
	HasCollectionRecord(context.Context, string, string, string) (bool, error)
}

func (s *SQLContentStore) HasCollectionRecord(ctx context.Context, source, target, key string) (bool, error) {
	var n int
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM collection_records WHERE source_id=$1 AND target=$2 AND record_key=$3`, source, target, key).Scan(&n)
	return n > 0, err
}

// Article and provenance are committed together. Reimports update drafts only;
// a published/hidden editorial decision is never silently overwritten.
func (s *SQLContentStore) SaveCollectionRecord(ctx context.Context, r CollectionRecord, skip bool) (bool, error) {
	if r.SourceID == "" || r.Key == "" {
		return false, fmt.Errorf("记录缺少来源或唯一标识")
	}
	data, err := json.Marshal(r.Values)
	if err != nil {
		return false, err
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return false, err
	}
	defer tx.Rollback()
	var id int
	err = tx.QueryRowContext(ctx, `SELECT content_id FROM collection_records WHERE source_id=$1 AND target=$2 AND record_key=$3`, r.SourceID, r.Target, r.Key).Scan(&id)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return false, err
	}
	if err == nil && skip {
		return false, nil
	}
	if r.Target == "article" {
		if id > 0 {
			var status string
			err = tx.QueryRowContext(ctx, `SELECT status FROM content_entries WHERE id=$1 AND kind='news'`, id).Scan(&status)
			if errors.Is(err, sql.ErrNoRows) {
				id = 0
			} else if err != nil {
				return false, err
			} else if status != "draft" {
				return false, nil
			}
		}
		now := time.Now().UTC()
		if id == 0 {
			var author int
			if err = tx.QueryRowContext(ctx, `SELECT id FROM users WHERE role='admin' AND status=1 ORDER BY id LIMIT 1`).Scan(&author); err != nil {
				return false, fmt.Errorf("没有可用的管理员作为文章作者")
			}
			err = tx.QueryRowContext(ctx, `INSERT INTO content_entries(kind,author_id,title,summary,content,cover,category,status,created_at,updated_at) VALUES ('news',$1,$2,$3,$4,$5,$6,'draft',$7,$8) RETURNING id`, author, r.Values["title"], r.Values["summary"], r.Values["content"], r.Values["cover"], r.Values["category"], now, now).Scan(&id)
		} else {
			_, err = tx.ExecContext(ctx, `UPDATE content_entries SET title=$1,summary=$2,content=$3,cover=$4,category=$5,updated_at=$6 WHERE id=$7 AND status='draft'`, r.Values["title"], r.Values["summary"], r.Values["content"], r.Values["cover"], r.Values["category"], now, id)
		}
		if err != nil {
			return false, err
		}
		r.ContentID = id
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO collection_records(source_id,target,record_key,payload,content_id,updated_at) VALUES ($1,$2,$3,$4,$5,$6)
 ON CONFLICT(source_id,target,record_key) DO UPDATE SET payload=excluded.payload,content_id=excluded.content_id,updated_at=excluded.updated_at`, r.SourceID, r.Target, r.Key, string(data), r.ContentID, time.Now().UTC().Format(time.RFC3339Nano))
	if err != nil {
		return false, err
	}
	return true, tx.Commit()
}

func (s *SQLContentStore) ListCollectionRecords(ctx context.Context, source string, page, size int) ([]CollectionRecord, int, error) {
	size, offset := contentPage(page, size)
	var total int
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM collection_records WHERE source_id=$1`, source).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := s.db.QueryContext(ctx, `SELECT source_id,target,record_key,payload,content_id,updated_at FROM collection_records WHERE source_id=$1 ORDER BY updated_at DESC,record_key LIMIT $2 OFFSET $3`, source, size, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	result := []CollectionRecord{}
	for rows.Next() {
		var r CollectionRecord
		var payload string
		if err := rows.Scan(&r.SourceID, &r.Target, &r.Key, &payload, &r.ContentID, &r.UpdatedAt); err != nil {
			return nil, 0, err
		}
		if err := json.Unmarshal([]byte(payload), &r.Values); err != nil {
			return nil, 0, err
		}
		result = append(result, r)
	}
	return result, total, rows.Err()
}
