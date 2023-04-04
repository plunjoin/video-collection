package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"video-collection-api/pkg/auth"
	"video-collection-api/pkg/store"
)

type contentFixture struct {
	t                           *testing.T
	s                           *store.SQLiteStore
	mux                         *http.ServeMux
	admin, alice, bob, disabled *store.User
	tokens                      map[int]string
}

func newContentFixture(t *testing.T) *contentFixture {
	t.Helper()
	s, err := store.NewSQLiteStore(filepath.Join(t.TempDir(), "content.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = s.Close() })
	f := &contentFixture{t: t, s: s, mux: http.NewServeMux(), tokens: make(map[int]string)}
	NewServer(s, nil, nil, nil).RegisterRoutes(f.mux)
	f.admin, err = s.GetUserByUsername(context.Background(), "admin")
	if err != nil {
		t.Fatal(err)
	}
	f.alice = &store.User{Username: "alice", Nickname: "小爱", Role: "user", Status: 1}
	f.bob = &store.User{Username: "bob", Role: "user", Status: 1}
	f.disabled = &store.User{Username: "disabled", Role: "user", Status: 0}
	for _, u := range []*store.User{f.alice, f.bob, f.disabled} {
		if err := s.CreateUser(context.Background(), u); err != nil {
			t.Fatal(err)
		}
	}
	for _, u := range []*store.User{f.admin, f.alice, f.bob, f.disabled} {
		token := auth.DefaultSessionManager.CreateSession(u)
		f.tokens[u.ID] = token
		t.Cleanup(func() { auth.DefaultSessionManager.DeleteSession(token) })
	}
	return f
}

func (f *contentFixture) request(method, path, body string, u *store.User, status int) map[string]json.RawMessage {
	f.t.Helper()
	r := httptest.NewRequest(method, path, strings.NewReader(body))
	if u != nil {
		r.Header.Set("Authorization", "Bearer "+f.tokens[u.ID])
	}
	w := httptest.NewRecorder()
	f.mux.ServeHTTP(w, r)
	if w.Code != status {
		f.t.Fatalf("%s %s: status=%d want=%d body=%s", method, path, w.Code, status, w.Body.String())
	}
	var result map[string]json.RawMessage
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		f.t.Fatal(err)
	}
	return result
}

func decodeContentData[T any](t *testing.T, result map[string]json.RawMessage) T {
	t.Helper()
	var value T
	if err := json.Unmarshal(result["data"], &value); err != nil {
		t.Fatal(err)
	}
	return value
}

func (f *contentFixture) post() store.Content {
	return decodeContentData[store.Content](f.t, f.request("POST", "/api/community/posts", `{"title":"新番讨论","content":"大家都在看什么？","category":"新番"}`, f.alice, 200))
}

func TestNewsPublicationAndPagination(t *testing.T) {
	f := newContentFixture(t)
	f.request("POST", "/api/admin/news", `{"title":"资讯","content":"正文"}`, f.alice, 401)
	draft := decodeContentData[store.Content](t, f.request("POST", "/api/admin/news", `{"title":"春季资讯","content":"发布前正文"}`, f.admin, 200))
	if draft.Status != "draft" || draft.AuthorID != f.admin.ID {
		t.Fatalf("bad draft: %+v", draft)
	}
	f.request("GET", fmt.Sprintf("/api/news?id=%d", draft.ID), "", nil, 404)
	f.request("GET", fmt.Sprintf("/api/news?id=%d", draft.ID), "", f.admin, 404)
	result := f.request("GET", "/api/news?status=draft", "", nil, 200)
	if string(result["data"]) != "[]" || string(result["total"]) != "0" {
		t.Fatalf("draft leaked: %s", result)
	}
	f.request("GET", fmt.Sprintf("/api/admin/news?id=%d", draft.ID), "", f.admin, 200)
	published := decodeContentData[store.Content](t, f.request("POST", "/api/admin/news", fmt.Sprintf(`{"id":%d,"title":"春季资讯","content":"已发布","status":"published","pinned":true,"category":"新番"}`, draft.ID), f.admin, 200))
	if !published.Pinned || published.CreatedAt.IsZero() || !published.CreatedAt.Equal(draft.CreatedAt) {
		t.Fatalf("bad publication: %+v", published)
	}
	f.request("POST", "/api/admin/news", `{"title":"100%_!情报","content":"正文","status":"published"}`, f.admin, 200)
	result = f.request("GET", "/api/news?page=1&page_size=1", "", nil, 200)
	items := decodeContentData[[]store.Content](t, result)
	if string(result["total"]) != "2" || len(items) != 1 || items[0].ID != draft.ID {
		t.Fatalf("bad ordering/page: %s", result)
	}
	result = f.request("GET", "/api/news?keyword=%25_!", "", nil, 200)
	if string(result["total"]) != "1" {
		t.Fatalf("wildcards not escaped: %s", result)
	}
	result = f.request("GET", "/api/news?category="+"%E6%96%B0%E7%95%AA", "", nil, 200)
	if string(result["total"]) != "1" {
		t.Fatalf("bad category: %s", result)
	}
	f.request("DELETE", fmt.Sprintf("/api/admin/news?id=%d", draft.ID), "", f.admin, 200)
	f.request("GET", fmt.Sprintf("/api/news?id=%d", draft.ID), "", nil, 404)
}

func TestCommunityPermissionsModerationAndNotifications(t *testing.T) {
	f := newContentFixture(t)
	post := f.post()
	path := fmt.Sprintf("/api/community/posts?id=%d", post.ID)
	likeBody := fmt.Sprintf(`{"post_id":%d}`, post.ID)
	commentBody := fmt.Sprintf(`{"post_id":%d,"content":"我也喜欢"}`, post.ID)
	f.request("POST", "/api/community/posts", fmt.Sprintf(`{"id":%d,"title":"篡改","content":"正文"}`, post.ID), f.bob, 403)
	f.request("DELETE", path, "", f.bob, 403)
	f.request("POST", "/api/community/posts", `{"title":"越权","content":"正文","pinned":true}`, f.alice, 403)
	f.request("POST", "/api/community/likes", likeBody, f.alice, 200)
	f.request("POST", "/api/community/comments", commentBody, f.alice, 200)
	result := f.request("GET", "/api/user/notifications", "", f.alice, 200)
	if string(result["total"]) != "0" {
		t.Fatal("self actions must not notify")
	}
	f.request("POST", "/api/community/likes", likeBody, f.bob, 200)
	f.request("POST", "/api/community/likes", likeBody, f.bob, 200)
	comment := decodeContentData[store.CommunityComment](t, f.request("POST", "/api/community/comments", commentBody, f.bob, 200))
	f.request("DELETE", fmt.Sprintf("/api/community/comments?id=%d", comment.ID), "", f.alice, 403)
	result = f.request("GET", path, "", f.bob, 200)
	updated := decodeContentData[store.Content](t, result)
	if !updated.Liked || updated.LikeCount != 2 || updated.CommentCount != 2 {
		t.Fatalf("bad counts: %+v", updated)
	}
	result = f.request("GET", "/api/user/notifications", "", f.alice, 200)
	notifications := decodeContentData[[]store.Notification](t, result)
	if len(notifications) != 2 || string(result["unread_count"]) != "2" || notifications[0].Type != "comment" || notifications[1].Type != "like" || notifications[0].TargetID != post.ID {
		t.Fatalf("bad notifications: %s", result)
	}
	f.request("GET", fmt.Sprintf("/api/community/comments?post_id=%d", post.ID), "", nil, 200)
	f.request("POST", "/api/admin/community/posts", fmt.Sprintf(`{"id":%d,"title":"新番讨论","content":"正文","status":"hidden","pinned":true}`, post.ID), f.admin, 200)
	f.request("GET", path, "", nil, 404)
	f.request("GET", fmt.Sprintf("/api/community/comments?post_id=%d", post.ID), "", nil, 404)
	f.request("POST", "/api/community/likes", likeBody, f.bob, 404)
	f.request("POST", "/api/community/comments", commentBody, f.bob, 404)
	updated = decodeContentData[store.Content](t, f.request("POST", "/api/community/posts", fmt.Sprintf(`{"id":%d,"title":"作者修订","content":"修订正文"}`, post.ID), f.alice, 200))
	if updated.Status != "hidden" || !updated.Pinned {
		t.Fatal("author bypassed moderation")
	}
	f.request("GET", fmt.Sprintf("/api/admin/community/comments?post_id=%d", post.ID), "", f.admin, 200)
	f.request("DELETE", fmt.Sprintf("/api/admin/community/comments?id=%d", comment.ID), "", f.admin, 200)
	f.request("DELETE", path, "", f.alice, 200)
	f.request("DELETE", path, "", f.alice, 404)
}

func TestNotificationOwnershipReadAndBroadcast(t *testing.T) {
	f := newContentFixture(t)
	path := "/api/admin/notifications"
	body := fmt.Sprintf(`{"user_ids":[%d,%d,%d],"title":"通知","content":"系统维护"}`, f.alice.ID, f.alice.ID, f.bob.ID)
	f.request("POST", path, body, f.bob, 401)
	result := f.request("POST", path, body, f.admin, 200)
	if decodeContentData[map[string]int](t, result)["sent_count"] != 2 {
		t.Fatal("duplicate recipients")
	}
	f.request("POST", path, fmt.Sprintf(`{"user_ids":[%d,%d],"title":"无效通知","content":"不应部分发送"}`, f.alice.ID, f.disabled.ID), f.admin, 400)
	alice := decodeContentData[[]store.Notification](t, f.request("GET", "/api/user/notifications", "", f.alice, 200))
	bob := decodeContentData[[]store.Notification](t, f.request("GET", "/api/user/notifications", "", f.bob, 200))
	if len(alice) != 1 || len(bob) != 1 {
		t.Fatal("send was not atomic")
	}
	readBody := fmt.Sprintf(`{"ids":[%d,%d]}`, alice[0].ID, bob[0].ID)
	f.request("POST", "/api/user/notifications/read", readBody, f.alice, 404)
	result = f.request("GET", "/api/user/notifications/unread-count", "", f.alice, 200)
	if decodeContentData[map[string]int](t, result)["unread_count"] != 1 {
		t.Fatal("partial read was not rolled back")
	}
	f.request("DELETE", fmt.Sprintf("/api/user/notifications?id=%d", bob[0].ID), "", f.alice, 404)
	readBody = fmt.Sprintf(`{"ids":[%d,%d]}`, alice[0].ID, alice[0].ID)
	f.request("POST", "/api/user/notifications/read", readBody, f.alice, 200)
	first := decodeContentData[[]store.Notification](t, f.request("GET", "/api/user/notifications", "", f.alice, 200))[0]
	f.request("POST", "/api/user/notifications/read", readBody, f.alice, 200)
	second := decodeContentData[[]store.Notification](t, f.request("GET", "/api/user/notifications", "", f.alice, 200))[0]
	if !second.IsRead || first.ReadAt == nil || second.ReadAt == nil || !first.ReadAt.Equal(*second.ReadAt) {
		t.Fatal("read must be idempotent")
	}
	result = f.request("GET", "/api/user/notifications?unread_only=true&type=system", "", f.alice, 200)
	if string(result["data"]) != "[]" {
		t.Fatal("unread filter failed")
	}
	result = f.request("POST", path, `{"broadcast":true,"title":"全站通知","content":"欢迎"}`, f.admin, 200)
	if decodeContentData[map[string]int](t, result)["sent_count"] != 3 {
		t.Fatal("broadcast should target current active users")
	}
	f.request("POST", "/api/user/notifications/read", `{"all":true}`, f.alice, 200)
	result = f.request("GET", "/api/user/notifications/unread-count", "", f.bob, 200)
	if decodeContentData[map[string]int](t, result)["unread_count"] != 2 {
		t.Fatal("mark all leaked across users")
	}
	f.request("DELETE", fmt.Sprintf("/api/user/notifications?id=%d", alice[0].ID), "", f.alice, 200)
}

func TestContentValidationAndAuthentication(t *testing.T) {
	f := newContentFixture(t)
	for _, tc := range []struct {
		method, path, body string
		user               *store.User
		status             int
	}{
		{"POST", "/api/community/posts", `{"title":"标题","content":"正文"}`, nil, 401},
		{"POST", "/api/community/posts", `{"title":"标题","content":"正文"}`, f.disabled, 401},
		{"GET", "/api/user/notifications", "", nil, 401},
		{"GET", "/api/admin/news", "", nil, 401},
		{"POST", "/api/news", `{}`, f.admin, 405},
		{"PATCH", "/api/community/posts", `{}`, f.alice, 405},
		{"GET", "/api/news?page=0", "", nil, 400},
		{"GET", "/api/news?page_size=101", "", nil, 400},
		{"GET", "/api/news?id=abc", "", nil, 400},
		{"GET", "/api/news?author_id=-1", "", nil, 400},
		{"GET", "/api/admin/news?status=hidden", "", f.admin, 400},
		{"GET", "/api/community/comments?post_id=999999", "", nil, 404},
		{"POST", "/api/community/posts", `{"title":" ","content":"正文"}`, f.alice, 400},
		{"POST", "/api/community/posts", `{"title":"标题","content":"正文","cover":"javascript:alert(1)"}`, f.alice, 400},
		{"POST", "/api/community/posts", `{"title":"标题","content":"正文","author_id":1}`, f.alice, 400},
		{"POST", "/api/community/posts", `{"title":"标题","content":"正文"}{}`, f.alice, 400},
		{"POST", "/api/community/posts", `{"title":"` + strings.Repeat("文", 201) + `","content":"正文"}`, f.alice, 400},
		{"POST", "/api/community/comments", `{"post_id":1,"content":" "}`, f.alice, 400},
		{"POST", "/api/community/likes", `null`, f.alice, 400},
		{"GET", "/api/user/notifications?unread_only=invalid", "", f.alice, 400},
		{"GET", "/api/user/notifications?type=invalid", "", f.alice, 400},
		{"POST", "/api/user/notifications/read", `{}`, f.alice, 400},
		{"POST", "/api/user/notifications/read", `{"ids":[1],"all":true}`, f.alice, 400},
		{"POST", "/api/admin/notifications", `{"title":"标题","content":"正文"}`, f.admin, 400},
		{"POST", "/api/admin/notifications", `{"title":"标题","content":"正文","broadcast":true,"user_ids":[1]}`, f.admin, 400},
		{"POST", "/api/community/posts", `{"title":"标题","content":"` + strings.Repeat("x", 1<<20) + `"}`, f.alice, 413},
	} {
		t.Run(tc.method+tc.path, func(t *testing.T) { f.request(tc.method, tc.path, tc.body, tc.user, tc.status) })
	}
	// Cookie authentication uses the real cookie name, independently of Bearer.
	r := httptest.NewRequest("GET", "/api/user/notifications", nil)
	r.AddCookie(&http.Cookie{Name: auth.CookieAuthToken, Value: f.tokens[f.alice.ID]})
	w := httptest.NewRecorder()
	f.mux.ServeHTTP(w, r)
	if w.Code != 200 {
		t.Fatalf("cookie auth failed: %s", w.Body.String())
	}
}
