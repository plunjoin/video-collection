package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// RAGChunkRow 持久化的向量块记录。
type RAGChunkRow struct {
	ID         int64
	SourceType string
	SourceID   string
	SubjectID  int
	ChunkIndex int
	Text       string
	Metadata   map[string]any
	Embedding  []byte
	Dimensions int
}

// RAGSearchHit 带相似度的检索命中。
type RAGSearchHit struct {
	RAGChunkRow
	Similarity float64
}

// RAGStore 向量块读写（默认 SQLite BLOB；后续可接 pgvector）。
type RAGStore interface {
	ReplaceRAGChunks(ctx context.Context, sourceType, sourceID string, rows []RAGChunkRow) error
	DeleteRAGChunksBySource(ctx context.Context, sourceType, sourceID string) error
	DeleteRAGChunksBySubjectID(ctx context.Context, subjectID int) error
	DeleteAllRAGChunks(ctx context.Context) error
	ListRAGChunksForSearch(ctx context.Context, sourceType string) ([]RAGChunkRow, error)
	CountRAGChunks(ctx context.Context) (int, error)
}

func migrateRAG(tx *sql.Tx, postgres bool, id, timestamp string) error {
	embeddingType := "BLOB"
	if postgres {
		embeddingType = "BYTEA"
	}
	schema := fmt.Sprintf(`
	CREATE TABLE IF NOT EXISTS rag_chunks (
		id %s,
		source_type TEXT NOT NULL,
		source_id TEXT NOT NULL,
		subject_id INTEGER NOT NULL DEFAULT 0,
		chunk_index INTEGER NOT NULL DEFAULT 0,
		text TEXT NOT NULL,
		metadata TEXT NOT NULL DEFAULT '{}',
		embedding %s NOT NULL,
		dimensions INTEGER NOT NULL,
		updated_at %s NOT NULL,
		UNIQUE(source_type, source_id, chunk_index)
	);
	CREATE INDEX IF NOT EXISTS idx_rag_chunks_subject ON rag_chunks(subject_id);
	CREATE INDEX IF NOT EXISTS idx_rag_chunks_source ON rag_chunks(source_type, source_id);
	`, id, embeddingType, timestamp)
	if _, err := tx.Exec(schema); err != nil {
		return err
	}
	_, err := tx.Exec("INSERT INTO content_migrations(name) VALUES('rag_vector_chunks_v1') ON CONFLICT(name) DO NOTHING")
	return err
}

func (s *SQLContentStore) ReplaceRAGChunks(ctx context.Context, sourceType, sourceID string, rows []RAGChunkRow) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err = tx.ExecContext(ctx, `DELETE FROM rag_chunks WHERE source_type=$1 AND source_id=$2`, sourceType, sourceID); err != nil {
		return err
	}
	now := time.Now().UTC().Format(time.RFC3339Nano)
	for _, row := range rows {
		meta := "{}"
		if len(row.Metadata) > 0 {
			b, _ := json.Marshal(row.Metadata)
			meta = string(b)
		}
		_, err = tx.ExecContext(ctx, `INSERT INTO rag_chunks(source_type, source_id, subject_id, chunk_index, text, metadata, embedding, dimensions, updated_at)
			VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
			row.SourceType, row.SourceID, row.SubjectID, row.ChunkIndex, row.Text, meta, row.Embedding, row.Dimensions, now)
		if err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *SQLContentStore) DeleteRAGChunksBySource(ctx context.Context, sourceType, sourceID string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM rag_chunks WHERE source_type=$1 AND source_id=$2`, sourceType, sourceID)
	return err
}

func (s *SQLContentStore) DeleteRAGChunksBySubjectID(ctx context.Context, subjectID int) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM rag_chunks WHERE subject_id=$1`, subjectID)
	return err
}

func (s *SQLContentStore) DeleteAllRAGChunks(ctx context.Context) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM rag_chunks`)
	return err
}

func (s *SQLContentStore) ListRAGChunksForSearch(ctx context.Context, sourceType string) ([]RAGChunkRow, error) {
	query := `SELECT id, source_type, source_id, subject_id, chunk_index, text, metadata, embedding, dimensions FROM rag_chunks`
	var args []any
	if strings.TrimSpace(sourceType) != "" {
		query += ` WHERE source_type=$1`
		args = append(args, sourceType)
	}
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var list []RAGChunkRow
	for rows.Next() {
		var row RAGChunkRow
		var metaRaw string
		if err := rows.Scan(&row.ID, &row.SourceType, &row.SourceID, &row.SubjectID, &row.ChunkIndex, &row.Text, &metaRaw, &row.Embedding, &row.Dimensions); err != nil {
			return nil, err
		}
		_ = json.Unmarshal([]byte(metaRaw), &row.Metadata)
		list = append(list, row)
	}
	return list, nil
}

func (s *SQLContentStore) CountRAGChunks(ctx context.Context) (int, error) {
	var n int
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM rag_chunks`).Scan(&n)
	return n, err
}
