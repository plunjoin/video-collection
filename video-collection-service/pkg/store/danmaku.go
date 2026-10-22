package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

var ErrDanmakuLimited = errors.New("发送太频繁，请稍后再试")

// Danmaku 是按剧集时间轴播放的弹幕。Mode：0 滚动，1 顶部，2 底部。
type Danmaku struct {
	ID         int       `json:"id"`
	VideoID    int       `json:"video_id"`
	EpisodeKey string    `json:"episode_key"`
	PlayTimeMs int       `json:"play_time_ms"`
	Mode       int       `json:"mode"`
	Color      string    `json:"color"`
	Content    string    `json:"content"`
	UserID     int       `json:"user_id"`
	AuthorName string    `json:"author_name"`
	CreatedAt  time.Time `json:"created_at"`
}

func migrateDanmaku(tx *sql.Tx, id, timestamp string) error {
	schema := fmt.Sprintf(`CREATE TABLE IF NOT EXISTS danmaku (
 id %s, video_id INTEGER NOT NULL, episode_key TEXT NOT NULL,
 play_time_ms INTEGER NOT NULL, mode INTEGER NOT NULL DEFAULT 0,
 color TEXT NOT NULL DEFAULT '#FFFFFF', content TEXT NOT NULL,
 user_id INTEGER NOT NULL, author_name TEXT NOT NULL DEFAULT '',
 created_at %s NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_danmaku_lookup ON danmaku(video_id, episode_key, play_time_ms, id);
CREATE INDEX IF NOT EXISTS idx_danmaku_user_time ON danmaku(user_id, created_at);`, id, timestamp)
	err := execScript(tx, schema)
	return err
}

func (s *SQLContentStore) ListDanmaku(ctx context.Context, videoID int, episodeKey string) ([]Danmaku, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, video_id, episode_key, play_time_ms, mode, color, content, user_id, author_name, created_at
 FROM danmaku WHERE video_id=$1 AND episode_key=$2 ORDER BY play_time_ms ASC, id ASC LIMIT 2000`, videoID, episodeKey)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	list := make([]Danmaku, 0)
	for rows.Next() {
		var item Danmaku
		if err = rows.Scan(&item.ID, &item.VideoID, &item.EpisodeKey, &item.PlayTimeMs, &item.Mode, &item.Color, &item.Content, &item.UserID, &item.AuthorName, &item.CreatedAt); err != nil {
			return nil, err
		}
		list = append(list, item)
	}
	return list, rows.Err()
}

func (s *SQLContentStore) AddDanmaku(ctx context.Context, item *Danmaku) error {
	var found int
	err := s.db.QueryRowContext(ctx, `SELECT id FROM videos WHERE id=$1`, item.VideoID).Scan(&found)
	if err == sql.ErrNoRows {
		return ErrContentNotFound
	}
	if err != nil {
		return err
	}
	since := time.Now().UTC().Add(-time.Minute)
	var recent int
	if err = s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM danmaku WHERE user_id=$1 AND created_at>=$2`, item.UserID, since).Scan(&recent); err != nil {
		return err
	}
	if recent >= 8 {
		return ErrDanmakuLimited
	}
	var same int
	if err = s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM danmaku WHERE user_id=$1 AND video_id=$2 AND episode_key=$3 AND content=$4 AND created_at>=$5`, item.UserID, item.VideoID, item.EpisodeKey, item.Content, time.Now().UTC().Add(-15*time.Second)).Scan(&same); err != nil {
		return err
	}
	if same > 0 {
		return ErrDanmakuLimited
	}
	item.CreatedAt = time.Now().UTC()
	return s.db.QueryRowContext(ctx, `INSERT INTO danmaku(video_id,episode_key,play_time_ms,mode,color,content,user_id,author_name,created_at)
 VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id, created_at`,
		item.VideoID, item.EpisodeKey, item.PlayTimeMs, item.Mode, item.Color, item.Content, item.UserID, item.AuthorName, item.CreatedAt).
		Scan(&item.ID, &item.CreatedAt)
}

func (s *SQLContentStore) DeleteDanmaku(ctx context.Context, id, userID int, admin bool) error {
	var owner int
	err := s.db.QueryRowContext(ctx, `SELECT user_id FROM danmaku WHERE id=$1`, id).Scan(&owner)
	if err == sql.ErrNoRows {
		return ErrContentNotFound
	}
	if err != nil {
		return err
	}
	if !admin && owner != userID {
		return ErrContentForbidden
	}
	_, err = s.db.ExecContext(ctx, `DELETE FROM danmaku WHERE id=$1`, id)
	return err
}
