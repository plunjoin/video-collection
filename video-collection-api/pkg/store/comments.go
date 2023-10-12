package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"regexp"
	"sort"
	"strings"
	"time"
	"unicode/utf8"
)

var ErrInvalidComment = errors.New("评论目标、回复关系或正文无效")

type Comment struct {
	ID           int       `json:"id"`
	TargetType   string    `json:"target_type"`
	TargetID     int       `json:"target_id"`
	PostID       int       `json:"post_id,omitempty"` // Legacy community API compatibility.
	ParentID     int       `json:"parent_id"`
	RootID       int       `json:"root_id"`
	UserID       int       `json:"user_id"`
	AuthorName   string    `json:"author_name"`
	AuthorAvatar string    `json:"author_avatar"`
	AuthorFrame  string    `json:"author_frame"`
	AuthorBadge  string    `json:"author_badge"`
	AuthorColor  string    `json:"author_color"`
	Content      string    `json:"content"`
	IsDeleted    bool      `json:"is_deleted"`
	LikeCount    int       `json:"like_count"`
	ReplyCount   int       `json:"reply_count"` // Direct, non-deleted replies.
	Liked        bool      `json:"liked"`
	CreatedAt    time.Time `json:"created_at"`
}

type CommentQuery struct {
	TargetType                                           string
	TargetID, ParentID, RootID, ViewerID, Page, PageSize int
	Admin                                                bool
	all                                                  bool // Legacy endpoint returns a flat list of live comments.
}

type CommentStore interface {
	RegisterCommentTarget(string, CommentTargetResolver) error
	QueryComments(context.Context, CommentQuery) ([]Comment, int, error)
	GetComment(context.Context, int, int, bool) (*Comment, error)
	AddComment(context.Context, *Comment) error
	RemoveComment(context.Context, int, int, bool) error
	SetCommentLike(context.Context, int, int, bool) (int, error)
}

// CommentTargetResolver validates existence and visibility in the caller's
// transaction. For write=true it must lock the target before returning, using
// the same lock order as that module's moderation/deletion. ownerID=0 means no
// owner notification. admin bypasses visibility for reads/deletion only.
type CommentTargetResolver func(ctx context.Context, tx *sql.Tx, id int, write, admin bool) (ownerID int, err error)

var commentTargetName = regexp.MustCompile(`^[a-z][a-z0-9_]{0,49}$`)

// RegisterCommentTarget extends comments without schema or HTTP handler changes.
// Unknown types are rejected; registrations belong to trusted server code.
func (s *SQLContentStore) RegisterCommentTarget(kind string, resolver CommentTargetResolver) error {
	if !commentTargetName.MatchString(kind) || resolver == nil || kind == "video" || kind == "news" || kind == "post" {
		return ErrInvalidComment
	}
	s.commentTargetsMu.Lock()
	defer s.commentTargetsMu.Unlock()
	if s.commentTargets == nil {
		s.commentTargets = make(map[string]CommentTargetResolver)
	}
	if _, exists := s.commentTargets[kind]; exists {
		return ErrInvalidComment
	}
	s.commentTargets[kind] = resolver
	return nil
}

func (s *SQLContentStore) commentTarget(ctx context.Context, tx *sql.Tx, kind string, id int, write, admin bool) (int, error) {
	if id < 1 {
		return 0, ErrInvalidComment
	}
	var owner int
	var err error
	switch kind {
	case "post", "news":
		var status string
		if write {
			owner, status, err = lockContent(ctx, tx, kind, id)
		} else {
			err = tx.QueryRowContext(ctx, "SELECT author_id,status FROM content_entries WHERE kind=$1 AND id=$2", kind, id).Scan(&owner, &status)
		}
		if err == nil && !admin && status != "published" {
			return 0, ErrContentNotFound
		}
	case "video":
		var found int
		query := "SELECT id FROM videos WHERE id=$1"
		if write {
			query = "UPDATE videos SET id=id WHERE id=$1 RETURNING id"
		}
		err = tx.QueryRowContext(ctx, query, id).Scan(&found)
	default:
		s.commentTargetsMu.RLock()
		resolver := s.commentTargets[kind]
		s.commentTargetsMu.RUnlock()
		if resolver == nil {
			return 0, ErrInvalidComment
		}
		owner, err = resolver(ctx, tx, id, write, admin)
	}
	if errors.Is(err, sql.ErrNoRows) {
		err = ErrContentNotFound
	}
	return owner, err
}

// Run once, transactionally. Old IDs are retained so clients' references survive
// upgrade; a migration marker prevents deleted comments reappearing on restart.
func migrateComments(tx *sql.Tx, postgres bool, id, timestamp string) error {
	_, err := tx.Exec(fmt.Sprintf(`
CREATE TABLE IF NOT EXISTS content_migrations (name TEXT PRIMARY KEY);
CREATE TABLE IF NOT EXISTS comments (
 id %s, target_type TEXT NOT NULL, target_id INTEGER NOT NULL,
 parent_id INTEGER NOT NULL DEFAULT 0, root_id INTEGER NOT NULL DEFAULT 0,
 user_id INTEGER NOT NULL, content TEXT NOT NULL,
 is_deleted INTEGER NOT NULL DEFAULT 0 CHECK(is_deleted IN (0,1)), created_at %s NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_comments_target ON comments(target_type,target_id,parent_id,id);
CREATE INDEX IF NOT EXISTS idx_comments_root ON comments(root_id,id);
CREATE INDEX IF NOT EXISTS idx_comments_parent ON comments(parent_id,id);
CREATE TABLE IF NOT EXISTS comment_likes (
 comment_id INTEGER NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
 user_id INTEGER NOT NULL, created_at %s NOT NULL, PRIMARY KEY(comment_id,user_id)
);`, id, timestamp, timestamp))
	if err != nil {
		return err
	}
	// In PostgreSQL this insert also serializes simultaneous migration attempts.
	result, err := tx.Exec("INSERT INTO content_migrations(name) VALUES('generic_comments_v1') ON CONFLICT(name) DO NOTHING")
	if err != nil {
		return err
	}
	count, err := result.RowsAffected()
	if err != nil || count == 0 {
		return err
	}
	if _, err = tx.Exec(`INSERT INTO comments(id,target_type,target_id,user_id,content,created_at)
 SELECT c.id,'post',c.post_id,c.user_id,c.content,c.created_at FROM community_comments c
 JOIN content_entries e ON e.id=c.post_id AND e.kind='post'`); err != nil {
		return err
	}
	if postgres {
		if _, err = tx.Exec("SELECT setval(pg_get_serial_sequence('comments','id'),COALESCE(MAX(id),1),COUNT(*)>0) FROM comments"); err != nil {
			return err
		}
	}
	for _, column := range []string{"comment_id", "parent_comment_id"} {
		if _, err = tx.Exec("ALTER TABLE user_notifications ADD COLUMN " + column + " INTEGER NOT NULL DEFAULT 0"); err != nil {
			return err
		}
	}
	_, err = tx.Exec("CREATE INDEX IF NOT EXISTS idx_notifications_comment ON user_notifications(comment_id)")
	return err
}

const commentColumns = `c.id,c.target_type,c.target_id,c.parent_id,c.root_id,c.user_id,
 COALESCE(NULLIF(u.nickname,''),u.username,''),` + identityColumns + `,c.content,c.is_deleted,
 (SELECT COUNT(*) FROM comment_likes l WHERE l.comment_id=c.id),
 (SELECT COUNT(*) FROM comments r WHERE r.parent_id=c.id AND r.is_deleted=0),
 (SELECT COUNT(*) FROM comment_likes l WHERE l.comment_id=c.id AND l.user_id=$1),c.created_at`

func scanComment(row contentScanner) (*Comment, error) {
	var c Comment
	var deleted, liked int
	err := row.Scan(&c.ID, &c.TargetType, &c.TargetID, &c.ParentID, &c.RootID, &c.UserID, &c.AuthorName, &c.AuthorAvatar, &c.AuthorFrame, &c.AuthorBadge, &c.AuthorColor, &c.Content, &deleted, &c.LikeCount, &c.ReplyCount, &liked, &c.CreatedAt)
	c.IsDeleted, c.Liked = deleted != 0, liked != 0
	if c.TargetType == "post" {
		c.PostID = c.TargetID
	}
	return &c, err
}

func commentByID(ctx context.Context, tx *sql.Tx, id, viewer int) (*Comment, error) {
	c, err := scanComment(tx.QueryRowContext(ctx, "SELECT "+commentColumns+" FROM comments c LEFT JOIN users u ON u.id=c.user_id WHERE c.id=$2", viewer, id))
	if errors.Is(err, sql.ErrNoRows) {
		err = ErrContentNotFound
	}
	return c, err
}

func (s *SQLContentStore) QueryComments(ctx context.Context, q CommentQuery) ([]Comment, int, error) {
	if q.ParentID < 0 || q.RootID < 0 || (q.ParentID > 0 && q.RootID > 0) {
		return nil, 0, ErrInvalidComment
	}
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelRepeatableRead, ReadOnly: true})
	if err != nil {
		return nil, 0, err
	}
	defer tx.Rollback()
	if _, err = s.commentTarget(ctx, tx, q.TargetType, q.TargetID, false, q.Admin); err != nil {
		return nil, 0, err
	}
	where := " WHERE $1>=0 AND c.target_type=$2 AND c.target_id=$3"
	args := []any{q.ViewerID, q.TargetType, q.TargetID}
	if q.all {
		where += " AND c.is_deleted=0"
	} else {
		filter, id := "parent_id", q.ParentID
		if q.RootID > 0 {
			filter, id = "root_id", q.RootID
		}
		if id > 0 {
			parent, err := commentByID(ctx, tx, id, q.ViewerID)
			if err != nil {
				return nil, 0, err
			}
			if parent.TargetType != q.TargetType || parent.TargetID != q.TargetID || (q.RootID > 0 && parent.ParentID != 0) {
				return nil, 0, ErrInvalidComment
			}
		}
		where += " AND c." + filter + "=$4"
		args = append(args, id)
	}
	var total int
	if err = tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM comments c"+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	limit, offset := contentPage(q.Page, q.PageSize)
	args = append(args, limit, offset)
	rows, err := tx.QueryContext(ctx, "SELECT "+commentColumns+" FROM comments c LEFT JOIN users u ON u.id=c.user_id"+where+fmt.Sprintf(" ORDER BY c.id ASC LIMIT $%d OFFSET $%d", len(args)-1, len(args)), args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	items := make([]Comment, 0)
	for rows.Next() {
		c, err := scanComment(rows)
		if err != nil {
			return nil, 0, err
		}
		items = append(items, *c)
	}
	if err = rows.Err(); err != nil {
		return nil, 0, err
	}
	if err = rows.Close(); err != nil {
		return nil, 0, err
	}
	return items, total, tx.Commit()
}

func (s *SQLContentStore) GetComment(ctx context.Context, id, viewer int, admin bool) (*Comment, error) {
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelRepeatableRead, ReadOnly: true})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	c, err := commentByID(ctx, tx, id, viewer)
	if err != nil {
		return nil, err
	}
	if _, err = s.commentTarget(ctx, tx, c.TargetType, c.TargetID, false, admin); err != nil {
		return nil, err
	}
	return c, tx.Commit()
}

func (s *SQLContentStore) AddComment(ctx context.Context, c *Comment) error {
	c.Content = strings.TrimSpace(c.Content)
	if c.UserID < 1 || c.ParentID < 0 || c.Content == "" || utf8.RuneCountInString(c.Content) > 2000 {
		return ErrInvalidComment
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err = s.addCommentTx(ctx, tx, c); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *SQLContentStore) addCommentTx(ctx context.Context, tx *sql.Tx, c *Comment) error {
	owner, err := s.commentTarget(ctx, tx, c.TargetType, c.TargetID, true, false)
	if err != nil {
		return err
	}
	c.RootID = 0
	replyOwner := 0
	if c.ParentID > 0 {
		parent, err := commentByID(ctx, tx, c.ParentID, c.UserID)
		if err != nil {
			return err
		}
		if parent.TargetType != c.TargetType || parent.TargetID != c.TargetID {
			return ErrInvalidComment
		}
		if parent.IsDeleted {
			return ErrContentNotFound
		}
		c.RootID = parent.RootID
		if c.RootID == 0 {
			c.RootID = parent.ID
		}
		replyOwner = parent.UserID
	}
	c.CreatedAt = time.Now().UTC()
	if err = tx.QueryRowContext(ctx, `INSERT INTO comments(target_type,target_id,parent_id,root_id,user_id,content,created_at)
 VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id`, c.TargetType, c.TargetID, c.ParentID, c.RootID, c.UserID, c.Content, c.CreatedAt).Scan(&c.ID); err != nil {
		return err
	}
	// Notify the directly replied-to author and content owner once each, excluding self.
	recipients := map[int]string{}
	if owner > 0 && owner != c.UserID {
		recipients[owner] = "你的内容收到新评论"
	}
	if replyOwner > 0 && replyOwner != c.UserID {
		recipients[replyOwner] = "你的评论收到新回复"
	}
	for user, title := range recipients {
		if err = insertNotification(ctx, tx, &Notification{UserID: user, ActorID: c.UserID, Type: "comment", Title: title, Content: c.Content, TargetType: c.TargetType, TargetID: c.TargetID, CommentID: c.ID, ParentCommentID: c.ParentID}); err != nil {
			return err
		}
	}
	if c.TargetType == "post" {
		c.PostID = c.TargetID
	}
	return nil
}

// Lock the target first, then re-read the comment after acquiring that lock.
// All comment writes for a target and target deletion use this lock order.
func (s *SQLContentStore) lockedComment(ctx context.Context, tx *sql.Tx, id int, admin bool) (*Comment, error) {
	c, err := commentByID(ctx, tx, id, 0)
	if err != nil {
		return nil, err
	}
	if _, err = s.commentTarget(ctx, tx, c.TargetType, c.TargetID, true, admin); err != nil {
		return nil, err
	}
	c, err = commentByID(ctx, tx, id, 0)
	if err == nil && c.IsDeleted {
		return nil, ErrContentNotFound
	}
	return c, err
}

func (s *SQLContentStore) RemoveComment(ctx context.Context, id, actor int, admin bool) error {
	return s.removeComment(ctx, id, actor, admin, "")
}

func (s *SQLContentStore) removeComment(ctx context.Context, id, actor int, admin bool, kind string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	// Authors may delete their own comment even after its target is hidden.
	c, err := s.lockedComment(ctx, tx, id, true)
	if err != nil {
		return err
	}
	if kind != "" && c.TargetType != kind {
		return ErrContentNotFound
	}
	if !admin && actor != c.UserID {
		return ErrContentForbidden
	}
	if _, err = tx.ExecContext(ctx, "DELETE FROM comment_likes WHERE comment_id=$1", id); err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, "UPDATE comments SET content='',is_deleted=1 WHERE id=$1", id); err != nil {
		return err
	}
	// Clear notification excerpts too; retain navigation and read history.
	if _, err = tx.ExecContext(ctx, "UPDATE user_notifications SET content='' WHERE comment_id=$1", id); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *SQLContentStore) SetCommentLike(ctx context.Context, id, userID int, liked bool) (int, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	c, err := s.lockedComment(ctx, tx, id, false)
	if err != nil {
		return 0, err
	}
	if liked {
		result, err := tx.ExecContext(ctx, "INSERT INTO comment_likes(comment_id,user_id,created_at) VALUES($1,$2,$3) ON CONFLICT(comment_id,user_id) DO NOTHING", id, userID, time.Now().UTC())
		if err != nil {
			return 0, err
		}
		added, err := result.RowsAffected()
		if err != nil {
			return 0, err
		}
		if added > 0 && c.UserID != userID {
			if err = insertNotification(ctx, tx, &Notification{UserID: c.UserID, ActorID: userID, Type: "like", Title: "你的评论收到新点赞", TargetType: c.TargetType, TargetID: c.TargetID, CommentID: c.ID, ParentCommentID: c.ParentID}); err != nil {
				return 0, err
			}
		}
	} else if _, err = tx.ExecContext(ctx, "DELETE FROM comment_likes WHERE comment_id=$1 AND user_id=$2", id, userID); err != nil {
		return 0, err
	}
	var count int
	if err = tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM comment_likes WHERE comment_id=$1", id).Scan(&count); err != nil {
		return 0, err
	}
	return count, tx.Commit()
}

// DeleteTargetComments must be called in the target's deletion transaction,
// after acquiring its write lock. It is also available to future content modules.
func DeleteTargetComments(ctx context.Context, tx *sql.Tx, kind string, id int) error {
	for _, query := range []string{
		"UPDATE user_notifications SET content='' WHERE comment_id IN (SELECT id FROM comments WHERE target_type=$1 AND target_id=$2)",
		"DELETE FROM comment_likes WHERE comment_id IN (SELECT id FROM comments WHERE target_type=$1 AND target_id=$2)",
		"DELETE FROM comments WHERE target_type=$1 AND target_id=$2",
	} {
		if _, err := tx.ExecContext(ctx, query, kind, id); err != nil {
			return err
		}
	}
	return nil
}

func (s *SQLContentStore) deleteVideosWithComments(ctx context.Context, ids []int) error {
	ids = append([]int(nil), ids...)
	sort.Ints(ids)
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for _, id := range ids {
		_, err = s.commentTarget(ctx, tx, "video", id, true, true)
		if errors.Is(err, ErrContentNotFound) {
			continue
		}
		if err != nil {
			return err
		}
		if err = DeleteTargetComments(ctx, tx, "video", id); err != nil {
			return err
		}
		if _, err = tx.ExecContext(ctx, "DELETE FROM play_sources WHERE video_id=$1", id); err != nil {
			return err
		}
		if _, err = tx.ExecContext(ctx, "DELETE FROM videos WHERE id=$1", id); err != nil {
			return err
		}
	}
	return tx.Commit()
}
