package store

import (
	"context"
	"database/sql"
	"errors"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

func TestGenericCommentStorage(t *testing.T) {
	s, err := NewSQLiteStore(filepath.Join(t.TempDir(), "comments.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if err = s.CreateUser(context.Background(), &User{Username: "reader", Role: "user", Status: 1}); err != nil {
		t.Fatal(err)
	}
	exerciseGenericCommentStorage(t, s.SQLContentStore)
	exerciseCommentMigration(t, s.SQLContentStore, false)
}

// Used against SQLite and PostgreSQL to verify the same SQL and guarantees.
func exerciseGenericCommentStorage(t *testing.T, s *SQLContentStore) {
	t.Helper()
	ctx := context.Background()
	news := &Content{Kind: "news", Title: "资讯", Content: "正文", Status: "published"}
	if err := s.SaveContent(ctx, news, 1, true); err != nil {
		t.Fatal(err)
	}
	root := &Comment{TargetType: "news", TargetID: news.ID, UserID: 1, Content: "评论"}
	if err := s.AddComment(ctx, root); err != nil {
		t.Fatal(err)
	}
	reply := &Comment{TargetType: "news", TargetID: news.ID, ParentID: root.ID, UserID: 2, Content: "回复"}
	if err := s.AddComment(ctx, reply); err != nil {
		t.Fatal(err)
	}
	if reply.RootID != root.ID {
		t.Fatal("wrong root")
	}
	var wg sync.WaitGroup
	errorsCh := make(chan error, 12)
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); _, err := s.SetCommentLike(ctx, reply.ID, 1, true); errorsCh <- err }()
	}
	wg.Wait()
	close(errorsCh)
	for err := range errorsCh {
		if err != nil {
			t.Fatal(err)
		}
	}
	comments, total, err := s.QueryComments(ctx, CommentQuery{TargetType: "news", TargetID: news.ID, RootID: root.ID, ViewerID: 1})
	if err != nil || total != 1 || len(comments) != 1 || !comments[0].Liked || comments[0].LikeCount != 1 {
		t.Fatalf("bad comments: %+v %v", comments, err)
	}
	var count int
	if err = s.db.QueryRow("SELECT COUNT(*) FROM user_notifications WHERE user_id=2 AND comment_id=$1 AND type='like'", reply.ID).Scan(&count); err != nil || count != 1 {
		t.Fatalf("duplicate notices %d %v", count, err)
	}
	if err = s.RemoveComment(ctx, root.ID, 1, false); err != nil {
		t.Fatal(err)
	}
	deleted, err := s.GetComment(ctx, root.ID, 1, false)
	if err != nil || !deleted.IsDeleted || deleted.Content != "" || deleted.ReplyCount != 1 {
		t.Fatalf("bad deleted parent: %+v %v", deleted, err)
	}
	if err = s.AddComment(ctx, &Comment{TargetType: "news", TargetID: news.ID, ParentID: root.ID, UserID: 2, Content: "invalid"}); !errors.Is(err, ErrContentNotFound) {
		t.Fatalf("deleted parent accepted: %v", err)
	}
	if err = s.DeleteContent(ctx, "news", news.ID, 1, true); err != nil {
		t.Fatal(err)
	}
	if _, err = s.GetComment(ctx, reply.ID, 1, false); !errors.Is(err, ErrContentNotFound) {
		t.Fatalf("orphan comment: %v", err)
	}
	if err = s.db.QueryRow("SELECT COUNT(*) FROM comment_likes WHERE comment_id=$1", reply.ID).Scan(&count); err != nil || count != 0 {
		t.Fatalf("orphan likes: %v", err)
	}
	// Verify server-side registration of a future target; no enum migration needed.
	if _, err = s.db.Exec("CREATE TABLE comment_test_topics(id INTEGER PRIMARY KEY,owner_id INTEGER,status TEXT); INSERT INTO comment_test_topics VALUES(1,1,'published'),(2,1,'hidden')"); err != nil {
		t.Fatal(err)
	}
	resolver := func(ctx context.Context, tx *sql.Tx, id int, write, admin bool) (int, error) {
		query := "SELECT owner_id,status FROM comment_test_topics WHERE id=$1"
		if write {
			query = "UPDATE comment_test_topics SET id=id WHERE id=$1 RETURNING owner_id,status"
		}
		var owner int
		var status string
		err := tx.QueryRowContext(ctx, query, id).Scan(&owner, &status)
		if err == nil && !admin && status != "published" {
			return 0, ErrContentNotFound
		}
		return owner, err
	}
	if err = s.RegisterCommentTarget("topic", resolver); err != nil {
		t.Fatal(err)
	}
	if err = s.RegisterCommentTarget("post", resolver); !errors.Is(err, ErrInvalidComment) {
		t.Fatal("built-in resolver replaced")
	}
	topic := &Comment{TargetType: "topic", TargetID: 1, UserID: 2, Content: "扩展评论"}
	if err = s.AddComment(ctx, topic); err != nil {
		t.Fatal(err)
	}
	if _, err = s.GetComment(ctx, topic.ID, 1, false); err != nil {
		t.Fatal(err)
	}
	if err = s.AddComment(ctx, &Comment{TargetType: "topic", TargetID: 2, UserID: 2, Content: "隐藏"}); !errors.Is(err, ErrContentNotFound) {
		t.Fatalf("resolver visibility ignored: %v", err)
	}
}

// Reconstruct the previous release's schema only inside an isolated test DB.
func exerciseCommentMigration(t *testing.T, s *SQLContentStore, postgres bool) {
	t.Helper()
	for _, query := range []string{
		"DROP TABLE comment_likes", "DROP TABLE comments", "DROP TABLE content_migrations",
		"DROP INDEX idx_notifications_comment",
		"ALTER TABLE user_notifications DROP COLUMN comment_id",
		"ALTER TABLE user_notifications DROP COLUMN parent_comment_id",
	} {
		if _, err := s.db.Exec(query); err != nil {
			t.Fatal(err)
		}
	}
	ctx := context.Background()
	post := &Content{Kind: "post", Title: "旧帖子", Content: "正文", Status: "published"}
	if err := s.SaveContent(ctx, post, 1, false); err != nil {
		t.Fatal(err)
	}
	when := time.Now().UTC().Truncate(time.Second)
	if _, err := s.db.Exec("INSERT INTO community_comments(id,post_id,user_id,content,created_at) VALUES(501,$1,2,'旧评论',$2)", post.ID, when); err != nil {
		t.Fatal(err)
	}
	if err := s.initSchema(postgres); err != nil {
		t.Fatal(err)
	}
	old, err := s.GetComment(ctx, 501, 1, false)
	if err != nil || old.Content != "旧评论" || old.TargetID != post.ID || old.TargetType != "post" || !old.CreatedAt.Equal(when) {
		t.Fatalf("migration lost data: %+v %v", old, err)
	}
	newComment := &Comment{TargetType: "post", TargetID: post.ID, UserID: 1, Content: "迁移后回复", ParentID: 501}
	if err = s.AddComment(ctx, newComment); err != nil {
		t.Fatal(err)
	}
	if newComment.ID <= 501 || newComment.RootID != 501 {
		t.Fatalf("sequence/references broken: %+v", newComment)
	}
	if err = s.RemoveComment(ctx, 501, 2, false); err != nil {
		t.Fatal(err)
	}
	if err = s.initSchema(postgres); err != nil {
		t.Fatal(err)
	}
	old, err = s.GetComment(ctx, 501, 1, false)
	if err != nil || !old.IsDeleted || old.Content != "" {
		t.Fatalf("comment resurrected: %+v %v", old, err)
	}
	if err = s.DeleteContent(ctx, "post", post.ID, 1, false); err != nil {
		t.Fatal(err)
	}
	if err = s.initSchema(postgres); err != nil {
		t.Fatal(err)
	}
	if _, err = s.GetComment(ctx, 501, 1, false); !errors.Is(err, ErrContentNotFound) {
		t.Fatalf("deleted target comment resurrected: %v", err)
	}
}

func TestCommentTransactionsAndVideoCleanup(t *testing.T) {
	s, err := NewSQLiteStore(filepath.Join(t.TempDir(), "transactions.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	ctx := context.Background()
	if err = s.CreateUser(ctx, &User{Username: "reader", Role: "user", Status: 1}); err != nil {
		t.Fatal(err)
	}
	id, err := s.SaveVideoManual(ctx, &VideoRecord{Name: "测试影片"})
	if err != nil {
		t.Fatal(err)
	}
	root := &Comment{TargetType: "video", TargetID: id, UserID: 1, Content: "影评"}
	if err = s.AddComment(ctx, root); err != nil {
		t.Fatal(err)
	}
	if _, err = s.db.Exec(`CREATE TRIGGER fail_comment_notification BEFORE INSERT ON user_notifications BEGIN SELECT RAISE(ABORT,'injected failure'); END`); err != nil {
		t.Fatal(err)
	}
	if err = s.AddComment(ctx, &Comment{TargetType: "video", TargetID: id, UserID: 2, Content: "回复", ParentID: root.ID}); err == nil {
		t.Fatal("reply should roll back")
	}
	if _, err = s.SetCommentLike(ctx, root.ID, 2, true); err == nil {
		t.Fatal("like should roll back")
	}
	c, err := s.GetComment(ctx, root.ID, 2, false)
	if err != nil || c.LikeCount != 0 || c.ReplyCount != 0 {
		t.Fatalf("partial transaction: %+v %v", c, err)
	}
	if _, err = s.db.Exec("DROP TRIGGER fail_comment_notification"); err != nil {
		t.Fatal(err)
	}
	if _, err = s.SetCommentLike(ctx, root.ID, 2, true); err != nil {
		t.Fatal(err)
	}
	if err = s.BatchDeleteVideos(ctx, []int{id, id, 999999}); err != nil {
		t.Fatal(err)
	}
	if _, err = s.GetComment(ctx, root.ID, 2, false); !errors.Is(err, ErrContentNotFound) {
		t.Fatalf("orphan video comment: %v", err)
	}
	var count int
	if err = s.db.QueryRow("SELECT COUNT(*) FROM comment_likes").Scan(&count); err != nil || count != 0 {
		t.Fatalf("orphan video likes: %v", err)
	}
}
