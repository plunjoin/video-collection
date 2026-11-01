package store

import (
	"context"
	"database/sql"
	"errors"
	"time"
)

// AvatarHistory 用户上传过的头像记录。
// ObjectKey 是存储层的逻辑键（如 avatars/12-xxx.png），删除时据此定位源文件；
// 外链头像没有源文件，ObjectKey 为空、Provider 为 external。
type AvatarHistory struct {
	ID        int       `json:"id"`
	URL       string    `json:"url"`
	ObjectKey string    `json:"-"`
	Provider  string    `json:"provider"`
	CreatedAt time.Time `json:"created_at"`
}

// avatarHistoryLimit 每个账号保留的历史头像条数，超出后从最旧的开始清理。
const avatarHistoryLimit = 20

func insertAvatar(ctx context.Context, db *sql.DB, userID int, url, objectKey, provider string, ph func(int) string) (int, error) {
	now := time.Now()
	res, err := db.ExecContext(ctx, `
		INSERT INTO avatar_history (user_id, url, object_key, provider, created_at)
		VALUES (`+ph(1)+`, `+ph(2)+`, `+ph(3)+`, `+ph(4)+`, `+ph(5)+`)`,
		userID, url, objectKey, provider, now)
	if err != nil {
		return 0, err
	}
	id, err := res.LastInsertId()
	if err != nil {
		// PostgreSQL 驱动不支持 LastInsertId，回查一次即可。
		var lastID int
		if qerr := db.QueryRowContext(ctx,
			"SELECT id FROM avatar_history WHERE user_id = "+ph(1)+" ORDER BY id DESC LIMIT 1", userID).Scan(&lastID); qerr != nil {
			return 0, qerr
		}
		return lastID, nil
	}
	return int(id), nil
}

func listAvatars(ctx context.Context, db *sql.DB, userID, limit int, ph func(int) string) ([]AvatarHistory, error) {
	if limit <= 0 {
		limit = avatarHistoryLimit
	}
	rows, err := db.QueryContext(ctx, `
		SELECT id, url, object_key, provider, created_at FROM avatar_history
		WHERE user_id = `+ph(1)+` ORDER BY id DESC LIMIT `+ph(2), userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	list := make([]AvatarHistory, 0, limit)
	for rows.Next() {
		var item AvatarHistory
		if err := rows.Scan(&item.ID, &item.URL, &item.ObjectKey, &item.Provider, &item.CreatedAt); err != nil {
			return nil, err
		}
		list = append(list, item)
	}
	return list, rows.Err()
}

func getAvatar(ctx context.Context, db *sql.DB, userID, id int, ph func(int) string) (*AvatarHistory, error) {
	var item AvatarHistory
	err := db.QueryRowContext(ctx, `
		SELECT id, url, object_key, provider, created_at FROM avatar_history
		WHERE id = `+ph(1)+` AND user_id = `+ph(2), id, userID).
		Scan(&item.ID, &item.URL, &item.ObjectKey, &item.Provider, &item.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &item, nil
}

func deleteAvatar(ctx context.Context, db *sql.DB, userID, id int, ph func(int) string) error {
	_, err := db.ExecContext(ctx, "DELETE FROM avatar_history WHERE id = "+ph(1)+" AND user_id = "+ph(2), id, userID)
	return err
}

// trimAvatars 只保留最新的 keep 条，返回被裁掉、需要清理源文件的记录。
// keepURL 为当前正在使用的头像，即使超出窗口也不会被裁掉。
func trimAvatars(ctx context.Context, db *sql.DB, userID, keep int, keepURL string, ph func(int) string) ([]AvatarHistory, error) {
	if keep <= 0 {
		keep = avatarHistoryLimit
	}
	all, err := listAvatars(ctx, db, userID, 500, ph)
	if err != nil {
		return nil, err
	}
	if len(all) <= keep {
		return nil, nil
	}
	removed := make([]AvatarHistory, 0, len(all)-keep)
	for _, item := range all[keep:] {
		if keepURL != "" && item.URL == keepURL {
			continue
		}
		if err := deleteAvatar(ctx, db, userID, item.ID, ph); err != nil {
			return removed, err
		}
		removed = append(removed, item)
	}
	return removed, nil
}

// ---------------------------------------------------------------------------
// SQLite
// ---------------------------------------------------------------------------

func (s *SQLiteStore) AddAvatar(ctx context.Context, userID int, url, objectKey, provider string) (int, error) {
	return insertAvatar(ctx, s.db, userID, url, objectKey, provider, qmarkPlaceholder)
}

func (s *SQLiteStore) ListAvatars(ctx context.Context, userID, limit int) ([]AvatarHistory, error) {
	return listAvatars(ctx, s.db, userID, limit, qmarkPlaceholder)
}

func (s *SQLiteStore) GetAvatar(ctx context.Context, userID, id int) (*AvatarHistory, error) {
	return getAvatar(ctx, s.db, userID, id, qmarkPlaceholder)
}

func (s *SQLiteStore) DeleteAvatar(ctx context.Context, userID, id int) error {
	return deleteAvatar(ctx, s.db, userID, id, qmarkPlaceholder)
}

func (s *SQLiteStore) TrimAvatars(ctx context.Context, userID, keep int, keepURL string) ([]AvatarHistory, error) {
	return trimAvatars(ctx, s.db, userID, keep, keepURL, qmarkPlaceholder)
}

// ---------------------------------------------------------------------------
// PostgreSQL
// ---------------------------------------------------------------------------

func (s *PostgresStore) AddAvatar(ctx context.Context, userID int, url, objectKey, provider string) (int, error) {
	return insertAvatar(ctx, s.db, userID, url, objectKey, provider, dollarPlaceholder)
}

func (s *PostgresStore) ListAvatars(ctx context.Context, userID, limit int) ([]AvatarHistory, error) {
	return listAvatars(ctx, s.db, userID, limit, dollarPlaceholder)
}

func (s *PostgresStore) GetAvatar(ctx context.Context, userID, id int) (*AvatarHistory, error) {
	return getAvatar(ctx, s.db, userID, id, dollarPlaceholder)
}

func (s *PostgresStore) DeleteAvatar(ctx context.Context, userID, id int) error {
	return deleteAvatar(ctx, s.db, userID, id, dollarPlaceholder)
}

func (s *PostgresStore) TrimAvatars(ctx context.Context, userID, keep int, keepURL string) ([]AvatarHistory, error) {
	return trimAvatars(ctx, s.db, userID, keep, keepURL, dollarPlaceholder)
}
