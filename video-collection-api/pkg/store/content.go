package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"
)

var (
	ErrContentNotFound  = errors.New("内容不存在或不可访问")
	ErrContentForbidden = errors.New("无权操作此内容")
	ErrInvalidRecipient = errors.New("接收用户不存在或已被禁用")
)

// Content contains plain text, not trusted HTML. Kind is news or post.
type Content struct {
	ID           int       `json:"id"`
	Kind         string    `json:"kind"`
	AuthorID     int       `json:"author_id"`
	AuthorName   string    `json:"author_name"`
	AuthorAvatar string    `json:"author_avatar"`
	Title        string    `json:"title"`
	Summary      string    `json:"summary"`
	Content      string    `json:"content"`
	Cover        string    `json:"cover"`
	Category     string    `json:"category"`
	Status       string    `json:"status"`
	Pinned       bool      `json:"pinned"`
	LikeCount    int       `json:"like_count"`
	CommentCount int       `json:"comment_count"`
	Liked        bool      `json:"liked"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type ContentQuery struct {
	Page, PageSize, ViewerID, AuthorID int
	Kind, Status, Keyword, Category    string
	Admin                              bool
}

type CommunityComment = Comment

type Notification struct {
	ID              int        `json:"id"`
	UserID          int        `json:"user_id"`
	ActorID         int        `json:"actor_id"`
	Type            string     `json:"type"`
	CommentID       int        `json:"comment_id"`
	ParentCommentID int        `json:"parent_comment_id"`
	Title           string     `json:"title"`
	Content         string     `json:"content"`
	TargetType      string     `json:"target_type"`
	TargetID        int        `json:"target_id"`
	IsRead          bool       `json:"is_read"`
	ReadAt          *time.Time `json:"read_at"`
	CreatedAt       time.Time  `json:"created_at"`
}

type NotificationQuery struct {
	UserID, Page, PageSize int
	UnreadOnly             bool
	Type                   string
}

type ContentStore interface {
	CollectionStore
	CommentStore
	ListContent(context.Context, ContentQuery) ([]Content, int, error)
	GetContent(context.Context, string, int, int, bool) (*Content, error)
	SaveContent(context.Context, *Content, int, bool) error
	DeleteContent(context.Context, string, int, int, bool) error
	ListComments(context.Context, int, int, int, bool) ([]CommunityComment, int, error)
	CreateComment(context.Context, *CommunityComment) error
	DeleteComment(context.Context, int, int, bool) error
	SetPostLike(context.Context, int, int, bool) (int, error)
	ListNotifications(context.Context, NotificationQuery) ([]Notification, int, int, error)
	CountUnreadNotifications(context.Context, int) (int, error)
	ReadNotifications(context.Context, int, []int, bool) (int64, error)
	DeleteNotification(context.Context, int, int) error
	SendNotification(context.Context, *Notification, []int, bool) (int64, error)
}

// Both supported drivers accept numbered $n placeholders and RETURNING.
type SQLContentStore struct {
	db               *sql.DB
	commentTargetsMu sync.RWMutex
	commentTargets   map[string]CommentTargetResolver
}

// Close releases the shared database connection pool.
func (s *SQLContentStore) Close() error { return s.db.Close() }

func (s *SQLContentStore) initSchema(postgres bool) error {
	id, timestamp := "INTEGER PRIMARY KEY AUTOINCREMENT", "DATETIME"
	if postgres {
		id, timestamp = "SERIAL PRIMARY KEY", "TIMESTAMPTZ"
	}
	schema := fmt.Sprintf(`
CREATE TABLE IF NOT EXISTS content_entries (
 id %s, kind TEXT NOT NULL CHECK(kind IN ('news','post')), author_id INTEGER NOT NULL,
 title TEXT NOT NULL, summary TEXT NOT NULL DEFAULT '', content TEXT NOT NULL,
 cover TEXT NOT NULL DEFAULT '', category TEXT NOT NULL DEFAULT '',
 status TEXT NOT NULL CHECK(status IN ('draft','published','hidden')),
 pinned INTEGER NOT NULL DEFAULT 0 CHECK(pinned IN (0,1)),
 created_at %s NOT NULL, updated_at %s NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_content_listing ON content_entries(kind,status,pinned,created_at,id);
CREATE INDEX IF NOT EXISTS idx_content_author ON content_entries(author_id,kind);
CREATE TABLE IF NOT EXISTS community_comments (
 id %s, post_id INTEGER NOT NULL REFERENCES content_entries(id) ON DELETE CASCADE,
 user_id INTEGER NOT NULL, content TEXT NOT NULL, created_at %s NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_comments_post ON community_comments(post_id,id);
CREATE TABLE IF NOT EXISTS community_likes (
 post_id INTEGER NOT NULL REFERENCES content_entries(id) ON DELETE CASCADE,
 user_id INTEGER NOT NULL, created_at %s NOT NULL, PRIMARY KEY(post_id,user_id)
);
CREATE TABLE IF NOT EXISTS user_notifications (
 id %s, user_id INTEGER NOT NULL, actor_id INTEGER NOT NULL DEFAULT 0,
 type TEXT NOT NULL CHECK(type IN ('system','comment','like')), title TEXT NOT NULL,
 content TEXT NOT NULL DEFAULT '', target_type TEXT NOT NULL DEFAULT '', target_id INTEGER NOT NULL DEFAULT 0,
 is_read INTEGER NOT NULL DEFAULT 0 CHECK(is_read IN (0,1)), read_at %s, created_at %s NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_notifications_inbox ON user_notifications(user_id,is_read,id);
`, id, timestamp, timestamp, id, timestamp, timestamp, id, timestamp, timestamp)
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err = tx.Exec(schema); err != nil {
		return err
	}
	if err = migrateComments(tx, postgres, id, timestamp); err != nil {
		return err
	}
	if _, err = tx.Exec(`CREATE TABLE IF NOT EXISTS collection_records (
 source_id TEXT NOT NULL, target TEXT NOT NULL, record_key TEXT NOT NULL,
 payload TEXT NOT NULL, content_id INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL,
 PRIMARY KEY(source_id,target,record_key)
);`); err != nil {
		return err
	}
	return tx.Commit()
}

func contentPage(page, size int) (int, int) {
	if page < 1 {
		page = 1
	}
	if size < 1 {
		size = 20
	}
	if size > 100 {
		size = 100
	}
	return size, (page - 1) * size
}

const contentColumns = `e.id,e.kind,e.author_id,COALESCE(NULLIF(u.nickname,''),u.username,''),COALESCE(u.avatar,''),
 e.title,e.summary,e.content,e.cover,e.category,e.status,e.pinned,
 (SELECT COUNT(*) FROM community_likes l WHERE l.post_id=e.id),
 (SELECT COUNT(*) FROM comments c WHERE c.target_type=e.kind AND c.target_id=e.id AND c.is_deleted=0),
 (SELECT COUNT(*) FROM community_likes l WHERE l.post_id=e.id AND l.user_id=$1),e.created_at,e.updated_at`

type contentScanner interface{ Scan(...any) error }

func scanContent(row contentScanner) (*Content, error) {
	var c Content
	var pinned, liked int
	err := row.Scan(&c.ID, &c.Kind, &c.AuthorID, &c.AuthorName, &c.AuthorAvatar, &c.Title, &c.Summary, &c.Content, &c.Cover, &c.Category, &c.Status, &pinned, &c.LikeCount, &c.CommentCount, &liked, &c.CreatedAt, &c.UpdatedAt)
	c.Pinned, c.Liked = pinned != 0, liked != 0
	return &c, err
}

func (s *SQLContentStore) ListContent(ctx context.Context, q ContentQuery) ([]Content, int, error) {
	// $1 is also used by the liked expression; bind it in the count query too.
	where := " WHERE $1 >= 0 AND e.kind=$2"
	args := []any{q.ViewerID, q.Kind}
	add := func(clause string, value any) { args = append(args, value); where += fmt.Sprintf(clause, len(args)) }
	if !q.Admin {
		q.Status = "published"
	}
	if q.Status != "" {
		add(" AND e.status=$%d", q.Status)
	}
	if q.AuthorID > 0 {
		add(" AND e.author_id=$%d", q.AuthorID)
	}
	if q.Category != "" {
		add(" AND e.category=$%d", q.Category)
	}
	if q.Keyword != "" {
		// Search literally, including percent and underscore characters.
		keyword := strings.NewReplacer("!", "!!", "%", "!%", "_", "!_").Replace(strings.ToLower(q.Keyword))
		args = append(args, "%"+keyword+"%")
		where += fmt.Sprintf(" AND (LOWER(e.title) LIKE $%d ESCAPE '!' OR LOWER(e.content) LIKE $%d ESCAPE '!')", len(args), len(args))
	}
	var total int
	if err := s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM content_entries e"+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	limit, offset := contentPage(q.Page, q.PageSize)
	args = append(args, limit, offset)
	query := "SELECT " + contentColumns + " FROM content_entries e LEFT JOIN users u ON u.id=e.author_id" + where + fmt.Sprintf(" ORDER BY e.pinned DESC,e.created_at DESC,e.id DESC LIMIT $%d OFFSET $%d", len(args)-1, len(args))
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	items := make([]Content, 0)
	for rows.Next() {
		c, err := scanContent(rows)
		if err != nil {
			return nil, 0, err
		}
		items = append(items, *c)
	}
	return items, total, rows.Err()
}

func (s *SQLContentStore) GetContent(ctx context.Context, kind string, id, viewer int, admin bool) (*Content, error) {
	query := "SELECT " + contentColumns + " FROM content_entries e LEFT JOIN users u ON u.id=e.author_id WHERE e.kind=$2 AND e.id=$3"
	if !admin {
		query += " AND e.status='published'"
	}
	c, err := scanContent(s.db.QueryRowContext(ctx, query, viewer, kind, id))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrContentNotFound
	}
	return c, err
}

// Acquire a write lock before checking permissions/status so moderation and
// deletion cannot race with replies, likes or edits on either database.
func lockContent(ctx context.Context, tx *sql.Tx, kind string, id int) (int, string, error) {
	var owner int
	var status string
	err := tx.QueryRowContext(ctx, "UPDATE content_entries SET id=id WHERE id=$1 AND kind=$2 RETURNING author_id,status", id, kind).Scan(&owner, &status)
	if errors.Is(err, sql.ErrNoRows) {
		err = ErrContentNotFound
	}
	return owner, status, err
}

func (s *SQLContentStore) SaveContent(ctx context.Context, c *Content, actor int, admin bool) error {
	if c.Kind == "news" && !admin {
		return ErrContentForbidden
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	now := time.Now().UTC()
	if c.ID == 0 {
		c.AuthorID = actor
		if !admin {
			c.Status = "published"
			c.Pinned = false
		}
		c.CreatedAt = now
		err = tx.QueryRowContext(ctx, `INSERT INTO content_entries(kind,author_id,title,summary,content,cover,category,status,pinned,created_at,updated_at)
 VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$10) RETURNING id`, c.Kind, c.AuthorID, c.Title, c.Summary, c.Content, c.Cover, c.Category, c.Status, boolInt(c.Pinned), now).Scan(&c.ID)
	} else {
		owner, status, lockErr := lockContent(ctx, tx, c.Kind, c.ID)
		if lockErr != nil {
			return lockErr
		}
		if !admin && owner != actor {
			return ErrContentForbidden
		}
		c.AuthorID = owner
		if !admin {
			c.Status = status
		}
		// Ordinary authors cannot undo moderation or change a moderator's pin.
		pinSQL := "pinned"
		if admin {
			pinSQL = fmt.Sprint(boolInt(c.Pinned))
		}
		_, err = tx.ExecContext(ctx, `UPDATE content_entries SET title=$1,summary=$2,content=$3,cover=$4,category=$5,status=$6,pinned=`+pinSQL+`,updated_at=$7 WHERE id=$8`, c.Title, c.Summary, c.Content, c.Cover, c.Category, c.Status, now, c.ID)
	}
	if err != nil {
		return err
	}
	c.UpdatedAt = now
	return tx.Commit()
}

func (s *SQLContentStore) DeleteContent(ctx context.Context, kind string, id, actor int, admin bool) error {
	if kind == "news" && !admin {
		return ErrContentForbidden
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	owner, _, err := lockContent(ctx, tx, kind, id)
	if err != nil {
		return err
	}
	if !admin && owner != actor {
		return ErrContentForbidden
	}
	if err = DeleteTargetComments(ctx, tx, kind, id); err != nil {
		return err
	}
	// Explicit cleanup also supports existing SQLite connections without FK enforcement.
	for _, query := range []string{"DELETE FROM community_comments WHERE post_id=$1", "DELETE FROM community_likes WHERE post_id=$1", "DELETE FROM content_entries WHERE id=$1"} {
		if _, err = tx.ExecContext(ctx, query, id); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *SQLContentStore) ListComments(ctx context.Context, postID, page, size int, admin bool) ([]CommunityComment, int, error) {
	return s.QueryComments(ctx, CommentQuery{TargetType: "post", TargetID: postID, Page: page, PageSize: size, Admin: admin, all: true})
}

func insertNotification(ctx context.Context, tx *sql.Tx, n *Notification) error {
	_, err := tx.ExecContext(ctx, `INSERT INTO user_notifications(user_id,actor_id,type,title,content,target_type,target_id,created_at,comment_id,parent_comment_id)
 SELECT id,$2,$3,$4,$5,$6,$7,$8,$9,$10 FROM users WHERE id=$1 AND status=1`, n.UserID, n.ActorID, n.Type, n.Title, n.Content, n.TargetType, n.TargetID, time.Now().UTC(), n.CommentID, n.ParentCommentID)
	return err
}

func (s *SQLContentStore) CreateComment(ctx context.Context, c *CommunityComment) error {
	c.TargetType, c.TargetID = "post", c.PostID
	return s.AddComment(ctx, c)
}

func (s *SQLContentStore) DeleteComment(ctx context.Context, id, actor int, admin bool) error {
	return s.removeComment(ctx, id, actor, admin, "post")
}

func (s *SQLContentStore) SetPostLike(ctx context.Context, postID, userID int, liked bool) (int, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	owner, status, err := lockContent(ctx, tx, "post", postID)
	if err != nil {
		return 0, err
	}
	if status != "published" {
		return 0, ErrContentNotFound
	}
	if liked {
		result, err := tx.ExecContext(ctx, "INSERT INTO community_likes(post_id,user_id,created_at) VALUES($1,$2,$3) ON CONFLICT(post_id,user_id) DO NOTHING", postID, userID, time.Now().UTC())
		if err != nil {
			return 0, err
		}
		added, err := result.RowsAffected()
		if err != nil {
			return 0, err
		}
		if added > 0 && owner != userID {
			if err = insertNotification(ctx, tx, &Notification{UserID: owner, ActorID: userID, Type: "like", Title: "你的帖子收到新点赞", TargetType: "post", TargetID: postID}); err != nil {
				return 0, err
			}
		}
	} else if _, err = tx.ExecContext(ctx, "DELETE FROM community_likes WHERE post_id=$1 AND user_id=$2", postID, userID); err != nil {
		return 0, err
	}
	var count int
	if err = tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM community_likes WHERE post_id=$1", postID).Scan(&count); err != nil {
		return 0, err
	}
	return count, tx.Commit()
}

func (s *SQLContentStore) CountUnreadNotifications(ctx context.Context, userID int) (int, error) {
	var count int
	err := s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM user_notifications WHERE user_id=$1 AND is_read=0", userID).Scan(&count)
	return count, err
}

func (s *SQLContentStore) ListNotifications(ctx context.Context, q NotificationQuery) ([]Notification, int, int, error) {
	where := " WHERE user_id=$1"
	args := []any{q.UserID}
	if q.UnreadOnly {
		where += " AND is_read=0"
	}
	if q.Type != "" {
		where += " AND type=$2"
		args = append(args, q.Type)
	}
	var total int
	if err := s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM user_notifications"+where, args...).Scan(&total); err != nil {
		return nil, 0, 0, err
	}
	unread, err := s.CountUnreadNotifications(ctx, q.UserID)
	if err != nil {
		return nil, 0, 0, err
	}
	limit, offset := contentPage(q.Page, q.PageSize)
	args = append(args, limit, offset)
	rows, err := s.db.QueryContext(ctx, "SELECT id,user_id,actor_id,type,title,content,target_type,target_id,is_read,read_at,created_at,comment_id,parent_comment_id FROM user_notifications"+where+fmt.Sprintf(" ORDER BY id DESC LIMIT $%d OFFSET $%d", len(args)-1, len(args)), args...)
	if err != nil {
		return nil, 0, 0, err
	}
	defer rows.Close()
	items := make([]Notification, 0)
	for rows.Next() {
		var n Notification
		var read int
		if err = rows.Scan(&n.ID, &n.UserID, &n.ActorID, &n.Type, &n.Title, &n.Content, &n.TargetType, &n.TargetID, &read, &n.ReadAt, &n.CreatedAt, &n.CommentID, &n.ParentCommentID); err != nil {
			return nil, 0, 0, err
		}
		n.IsRead = read != 0
		items = append(items, n)
	}
	return items, total, unread, rows.Err()
}

func (s *SQLContentStore) ReadNotifications(ctx context.Context, userID int, ids []int, all bool) (int64, error) {
	if !all && len(ids) == 0 {
		return 0, ErrContentNotFound
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	var count int64
	if all {
		result, err := tx.ExecContext(ctx, "UPDATE user_notifications SET is_read=1,read_at=$1 WHERE user_id=$2 AND is_read=0", time.Now().UTC(), userID)
		if err != nil {
			return 0, err
		}
		count, err = result.RowsAffected()
		if err != nil {
			return 0, err
		}
	} else {
		for _, id := range ids {
			// Already-read items are valid and preserve their original read time.
			var changed int
			err = tx.QueryRowContext(ctx, `UPDATE user_notifications SET read_at=$1,is_read=1 WHERE id=$2 AND user_id=$3 AND is_read=0 RETURNING id`, time.Now().UTC(), id, userID).Scan(&changed)
			if errors.Is(err, sql.ErrNoRows) {
				var exists int
				if err = tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM user_notifications WHERE id=$1 AND user_id=$2", id, userID).Scan(&exists); err != nil {
					return 0, err
				}
				if exists == 0 {
					return 0, ErrContentNotFound
				}
				continue
			}
			if err != nil {
				return 0, err
			}
			count++
		}
	}
	return count, tx.Commit()
}

func (s *SQLContentStore) DeleteNotification(ctx context.Context, userID, id int) error {
	result, err := s.db.ExecContext(ctx, "DELETE FROM user_notifications WHERE id=$1 AND user_id=$2", id, userID)
	if err != nil {
		return err
	}
	count, err := result.RowsAffected()
	if err == nil && count == 0 {
		return ErrContentNotFound
	}
	return err
}

func (s *SQLContentStore) SendNotification(ctx context.Context, n *Notification, ids []int, broadcast bool) (int64, error) {
	if !broadcast && len(ids) == 0 {
		return 0, ErrInvalidRecipient
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	where := " WHERE status=1"
	args := []any{n.ActorID, n.Title, n.Content, time.Now().UTC()}
	if !broadcast {
		unique := make(map[int]bool)
		var placeholders []string
		for _, id := range ids {
			if !unique[id] {
				unique[id] = true
				args = append(args, id)
				placeholders = append(placeholders, fmt.Sprintf("$%d", len(args)))
			}
		}
		where += " AND id IN (" + strings.Join(placeholders, ",") + ")"
		result, err := tx.ExecContext(ctx, `INSERT INTO user_notifications(user_id,actor_id,type,title,content,created_at)
 SELECT id,$1,'system',$2,$3,$4 FROM users`+where, args...)
		if err != nil {
			return 0, err
		}
		count, err := result.RowsAffected()
		if err != nil {
			return 0, err
		}
		if count != int64(len(unique)) {
			return 0, ErrInvalidRecipient
		}
		return count, tx.Commit()
	}
	result, err := tx.ExecContext(ctx, `INSERT INTO user_notifications(user_id,actor_id,type,title,content,created_at)
 SELECT id,$1,'system',$2,$3,$4 FROM users`+where, args...)
	if err != nil {
		return 0, err
	}
	count, err := result.RowsAffected()
	if err != nil {
		return 0, err
	}
	return count, tx.Commit()
}

func boolInt(value bool) int {
	if value {
		return 1
	}
	return 0
}
