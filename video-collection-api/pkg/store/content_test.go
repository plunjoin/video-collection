package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

func TestSQLiteContentPersistenceAndAtomicity(t *testing.T) {
	path := filepath.Join(t.TempDir(), "content.db")
	s, err := NewSQLiteStore(path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = s.Close() })
	ctx := context.Background()
	user := &User{Username: "reader", Status: 1, Role: "user"}
	if err = s.CreateUser(ctx, user); err != nil {
		t.Fatal(err)
	}
	post := &Content{Kind: "post", Title: "讨论", Content: "正文", Status: "published"}
	if err = s.SaveContent(ctx, post, 1, false); err != nil {
		t.Fatal(err)
	}
	// A failure while writing the notification must roll back the interaction too.
	if _, err = s.db.Exec(`CREATE TRIGGER fail_notification BEFORE INSERT ON user_notifications BEGIN SELECT RAISE(ABORT,'injected failure'); END`); err != nil {
		t.Fatal(err)
	}
	if err = s.CreateComment(ctx, &CommunityComment{PostID: post.ID, UserID: user.ID, Content: "回复"}); err == nil {
		t.Fatal("expected injected failure")
	}
	if _, err = s.SetPostLike(ctx, post.ID, user.ID, true); err == nil {
		t.Fatal("expected injected failure")
	}
	current, err := s.GetContent(ctx, "post", post.ID, user.ID, false)
	if err != nil {
		t.Fatal(err)
	}
	if current.LikeCount != 0 || current.CommentCount != 0 {
		t.Fatal("interaction committed without notification")
	}
	if _, err = s.db.Exec("DROP TRIGGER fail_notification"); err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	errorsCh := make(chan error, 16)
	for i := 0; i < 16; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); _, err := s.SetPostLike(ctx, post.ID, user.ID, true); errorsCh <- err }()
	}
	wg.Wait()
	close(errorsCh)
	for err := range errorsCh {
		if err != nil {
			t.Fatal(err)
		}
	}
	notifications, total, _, err := s.ListNotifications(ctx, NotificationQuery{UserID: 1})
	if err != nil {
		t.Fatal(err)
	}
	if total != 1 || len(notifications) != 1 {
		t.Fatalf("duplicate like notifications: %d", total)
	}
	if err = s.Close(); err != nil {
		t.Fatal(err)
	}
	s, err = NewSQLiteStore(path)
	if err != nil {
		t.Fatal(err)
	}
	current, err = s.GetContent(ctx, "post", post.ID, user.ID, false)
	if err != nil || current.LikeCount != 1 || !current.Liked {
		t.Fatalf("content not persisted: %+v %v", current, err)
	}
	if _, err = s.SetPostLike(ctx, post.ID, user.ID, false); err != nil {
		t.Fatal(err)
	}
	if _, err = s.SetPostLike(ctx, post.ID, user.ID, false); err != nil {
		t.Fatal(err)
	}
	if err = s.CreateComment(ctx, &CommunityComment{PostID: post.ID, UserID: user.ID, Content: "回复"}); err != nil {
		t.Fatal(err)
	}
	if err = s.DeleteContent(ctx, "post", post.ID, 1, false); err != nil {
		t.Fatal(err)
	}
	for _, table := range []string{"community_comments", "community_likes"} {
		var count int
		if err = s.db.QueryRow("SELECT COUNT(*) FROM " + table).Scan(&count); err != nil || count != 0 {
			t.Fatalf("orphaned %s: %d %v", table, count, err)
		}
	}
}

// Use an explicitly supplied test database and an isolated schema, never the
// application's production tables. This verifies the shared SQL on PostgreSQL.
func TestPostgresContentStore(t *testing.T) {
	dsn := os.Getenv("TEST_POSTGRES_DSN")
	if dsn == "" {
		t.Skip("set TEST_POSTGRES_DSN to run isolated PostgreSQL content tests")
	}
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	db.SetMaxOpenConns(1)
	schema := fmt.Sprintf("content_test_%d", time.Now().UnixNano())
	if _, err = db.Exec("CREATE SCHEMA " + schema); err != nil {
		t.Fatal(err)
	}
	defer db.Exec("DROP SCHEMA " + schema + " CASCADE")
	if _, err = db.Exec("SET search_path TO " + schema); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec("CREATE TABLE users(id INTEGER PRIMARY KEY,username TEXT,nickname TEXT,avatar TEXT,status INTEGER); INSERT INTO users VALUES(1,'author','','',1),(2,'reader','','',1)"); err != nil {
		t.Fatal(err)
	}
	s := &SQLContentStore{db: db}
	if err = s.initSchema(true); err != nil {
		t.Fatal(err)
	}
	if err = s.initSchema(true); err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	post := &Content{Kind: "post", Title: "PostgreSQL", Content: "正文", Status: "published"}
	if err = s.SaveContent(ctx, post, 1, false); err != nil {
		t.Fatal(err)
	}
	if err = s.CreateComment(ctx, &CommunityComment{PostID: post.ID, UserID: 2, Content: "回复"}); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ {
		if _, err = s.SetPostLike(ctx, post.ID, 2, true); err != nil {
			t.Fatal(err)
		}
	}
	items, total, err := s.ListContent(ctx, ContentQuery{Kind: "post", ViewerID: 2, Keyword: "POSTGRES"})
	if err != nil || total != 1 || len(items) != 1 || items[0].LikeCount != 1 || !items[0].Liked {
		t.Fatalf("bad listing: %+v %d %v", items, total, err)
	}
	comments, total, err := s.ListComments(ctx, post.ID, 1, 20, false)
	if err != nil || total != 1 || len(comments) != 1 {
		t.Fatalf("bad comments: %+v %v", comments, err)
	}
	if err = s.DeleteComment(ctx, comments[0].ID, 2, false); err != nil {
		t.Fatal(err)
	}
	if count, err := s.SendNotification(ctx, &Notification{ActorID: 1, Title: "系统通知", Content: "正文"}, []int{1, 2}, false); err != nil || count != 2 {
		t.Fatalf("send: %d %v", count, err)
	}
	notes, total, unread, err := s.ListNotifications(ctx, NotificationQuery{UserID: 1, UnreadOnly: true})
	if err != nil || total != 3 || unread != 3 || len(notes) != 3 {
		t.Fatalf("bad inbox: %+v %v", notes, err)
	}
	if count, err := s.ReadNotifications(ctx, 1, []int{notes[0].ID}, false); err != nil || count != 1 {
		t.Fatalf("read: %d %v", count, err)
	}
	if count, err := s.ReadNotifications(ctx, 1, []int{notes[0].ID}, false); err != nil || count != 0 {
		t.Fatalf("repeat read: %d %v", count, err)
	}
	if err = s.DeleteNotification(ctx, 2, notes[0].ID); !errors.Is(err, ErrContentNotFound) {
		t.Fatalf("ownership: %v", err)
	}
	if err = s.DeleteContent(ctx, "post", post.ID, 1, false); err != nil {
		t.Fatal(err)
	}
}
