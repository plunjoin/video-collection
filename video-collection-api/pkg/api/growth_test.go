package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"
	"video-collection-api/pkg/auth"
	"video-collection-api/pkg/store"
)

func TestBearerLogoutDoesNotRevokeOtherCookieAccount(t *testing.T) {
	f := newContentFixture(t)
	r := httptest.NewRequest(http.MethodPost, "/api/logout", nil)
	r.Header.Set("Authorization", "Bearer "+f.tokens[f.admin.ID])
	r.AddCookie(&http.Cookie{Name: auth.CookieAuthToken, Value: f.tokens[f.alice.ID]})
	w := httptest.NewRecorder()
	f.mux.ServeHTTP(w, r)
	if w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	f.request("GET", "/api/me", "", f.alice, 200)
	f.request("GET", "/api/me", "", f.admin, 401)
}

func (f *contentFixture) staff(role string) *store.User {
	f.t.Helper()
	u := &store.User{Username: "staff_" + role, Role: role, Status: 1}
	if err := f.s.CreateUser(context.Background(), u); err != nil {
		f.t.Fatal(err)
	}
	token := auth.DefaultSessionManager.CreateSession(u)
	f.tokens[u.ID] = token
	f.t.Cleanup(func() { auth.DefaultSessionManager.DeleteSession(token) })
	return u
}
func TestBackendRolesAndAssignment(t *testing.T) {
	f := newContentFixture(t)
	observer := f.staff("observer")
	operator := f.staff("operator")
	admin := f.staff("admin")
	if f.admin.Role != "super_admin" {
		t.Fatal("bootstrap must be super administrator")
	}
	for _, path := range []string{"/api/admin/users", "/api/admin/news", "/api/admin/growth", "/api/admin/reviews", "/api/admin/db/info"} {
		f.request("GET", path, "", observer, 200)
	}
	for _, role := range []*store.User{observer, operator} {
		for _, path := range []string{"/api/admin/users", "/api/admin/db/sql", "/api/admin/sources/collect", "/api/admin/reviews", "/api/admin/notifications"} {
			f.request("POST", path, `{}`, role, 403)
		}
	}
	f.request("POST", "/api/community/posts", `{"title":"不应发布","content":"正文"}`, observer, 403)
	f.request("POST", "/api/admin/users", `{"username":"escalate","password":"abc12345","role":"super_admin","status":1}`, admin, 403)
	f.request("POST", "/api/admin/db/sql", `{"sql":"SELECT 1"}`, admin, 403)
	f.request("POST", "/api/admin/users", fmt.Sprintf(`{"id":%d,"role":"user","status":1}`, f.admin.ID), admin, 403)
	f.request("POST", "/api/admin/users", fmt.Sprintf(`{"id":%d,"role":"user","status":1}`, f.admin.ID), f.admin, 403)
	f.request("POST", "/api/admin/users", `{"username":"staff_new","password":"abc12345","role":"operator","status":1}`, f.admin, 200)
	f.request("POST", "/api/admin/users", `{"username":"invalid_role","password":"abc12345","role":"root","status":1}`, f.admin, 400)
	f.request("POST", "/api/admin/users", fmt.Sprintf(`{"id":%d,"role":"observer","status":1}`, operator.ID), f.admin, 200)
	// Session role snapshots do not preserve stale mutation privileges.
	f.request("POST", "/api/admin/news", `{"title":"标题","content":"正文"}`, operator, 403)
}

func TestOperatorPublicationApprovalAndRejection(t *testing.T) {
	f := newContentFixture(t)
	u := f.staff("operator")
	ctx := context.Background()
	cases := []struct{ path, body, kind, publicPath string }{
		{"/api/admin/news", `{"title":"审核资讯","content":"正文","status":"published"}`, "news", "/api/news"},
		{"/api/community/posts", `{"title":"审核帖子","content":"正文"}`, "post", "/api/community/posts"},
		{"/api/admin/videos/save", `{"name":"审核视频","play_groups":[{"player_code":"hls","episodes":[{"name":"第一集","url":"https://example.com/a.m3u8"}]}]}`, "video", "/api/videos"},
	}
	for _, c := range cases {
		t.Run(c.kind, func(t *testing.T) {
			r := f.request("POST", c.path, c.body, u, 200)
			if string(r["pending"]) != "true" {
				t.Fatal("must queue operator content")
			}
			f.request("GET", c.publicPath, "", nil, 200)
			pending, _, err := f.s.ListReviews(ctx, u.ID, "pending", 1, 20)
			if err != nil || len(pending) != 1 {
				t.Fatalf("pending %v %v", pending, err)
			}
			if c.kind == "video" {
				_, n, _ := f.s.QueryVideos(ctx, store.VideoQuery{Page: 1, PageSize: 20})
				if n != 0 {
					t.Fatal("video leaked")
				}
			} else {
				_, n, _ := f.s.ListContent(ctx, store.ContentQuery{Kind: c.kind})
				if n != 0 {
					t.Fatal("content leaked")
				}
			}
			id := pending[0].ID
			f.request("POST", "/api/admin/reviews", fmt.Sprintf(`{"id":%d,"approve":true}`, id), u, 403)
			f.request("POST", "/api/admin/reviews", fmt.Sprintf(`{"id":%d,"approve":true}`, id), f.admin, 200)
			f.request("POST", "/api/admin/reviews", fmt.Sprintf(`{"id":%d,"approve":true}`, id), f.admin, 409)
			if c.kind == "video" {
				list, n, _ := f.s.QueryVideos(ctx, store.VideoQuery{Page: 1, PageSize: 20})
				if n != 1 || len(list[0].PlayGroups) != 1 {
					t.Fatal("video not published atomically")
				}
			} else {
				list, n, _ := f.s.ListContent(ctx, store.ContentQuery{Kind: c.kind})
				if n != 1 || list[0].AuthorID != u.ID {
					t.Fatal("wrong publication")
				}
			}
		})
	}
	post := f.post()
	for _, path := range []string{"/api/comments", "/api/community/comments"} {
		body := fmt.Sprintf(`{"target_type":"post","target_id":%d,"content":"待审评论"}`, post.ID)
		if path == "/api/community/comments" {
			body = fmt.Sprintf(`{"post_id":%d,"content":"待审评论"}`, post.ID)
		}
		r := f.request("POST", path, body, u, 200)
		var id int
		_ = json.Unmarshal(r["review_id"], &id)
		comments, n, _ := f.s.ListComments(ctx, post.ID, 1, 20, false)
		if n != 0 || len(comments) != 0 {
			t.Fatal("unreviewed comment leaked")
		}
		f.request("POST", "/api/admin/reviews", fmt.Sprintf(`{"id":%d,"approve":false}`, id), f.admin, 400)
		f.request("POST", "/api/admin/reviews", fmt.Sprintf(`{"id":%d,"approve":false,"note":"请补充来源"}`, id), f.admin, 200)
	}
	// Approved generic comments are validated against their live target and parent.
	r := f.request("POST", "/api/comments", fmt.Sprintf(`{"target_type":"post","target_id":%d,"content":"审核通过评论"}`, post.ID), u, 200)
	var id int
	_ = json.Unmarshal(r["review_id"], &id)
	f.request("POST", "/api/admin/reviews", fmt.Sprintf(`{"id":%d,"approve":true}`, id), f.admin, 200)
	_, n, _ := f.s.ListComments(ctx, post.ID, 1, 20, false)
	if n != 1 {
		t.Fatal("approved comment missing")
	}
	// Proposed edits preserve the old public version and fail after concurrent moderation.
	r = f.request("POST", "/api/admin/community/posts", fmt.Sprintf(`{"id":%d,"title":"提案版本","content":"新正文","status":"published"}`, post.ID), u, 200)
	_ = json.Unmarshal(r["review_id"], &id)
	public, _ := f.s.GetContent(ctx, "post", post.ID, 0, false)
	if public.Title == "提案版本" {
		t.Fatal("proposed edit leaked")
	}
	f.request("POST", "/api/admin/community/posts", fmt.Sprintf(`{"id":%d,"title":"管理员修订","content":"正文","status":"published"}`, post.ID), f.admin, 200)
	f.request("POST", "/api/admin/reviews", fmt.Sprintf(`{"id":%d,"approve":true}`, id), f.admin, 409)
	_, _, unread, err := f.s.ListNotifications(ctx, store.NotificationQuery{UserID: u.ID})
	if err != nil || unread < 1 {
		t.Fatal("missing review results notification")
	}
}

func TestPointsConcurrencyRedemptionAndRequestRefund(t *testing.T) {
	f := newContentFixture(t)
	ctx := context.Background()
	u := f.alice
	now := time.Now()
	var wg sync.WaitGroup
	errs := make(chan error, 30)
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := f.s.RecordActivity(ctx, u.ID, now); err != nil {
				errs <- err
			}
			_, err := f.s.Checkin(ctx, u.ID, now)
			if err != nil {
				errs <- err
			}
		}()
	}
	wg.Wait()
	close(errs)
	for e := range errs {
		t.Fatal(e)
	}
	wallet, _ := f.s.Wallet(ctx, u.ID)
	if wallet["balance"] != 15 {
		t.Fatalf("double awards: %v", wallet)
	}
	// Repeated redemption consumes once, negative balances and unowned equipment fail.
	items, _ := f.s.ListCosmetics(ctx, u.ID, true)
	item := items[0]
	item.Price = 3
	item.Active = true
	if err := f.s.SaveCosmetic(ctx, &item); err != nil {
		t.Fatal(err)
	}
	if err := f.s.Equip(ctx, u.ID, item.ID, ""); err == nil {
		t.Fatal("equipped unowned item")
	}
	errs = make(chan error, 10)
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := f.s.Redeem(ctx, u.ID, item.ID); err != nil {
				errs <- err
			}
		}()
	}
	wg.Wait()
	close(errs)
	for e := range errs {
		t.Fatal(e)
	}
	wallet, _ = f.s.Wallet(ctx, u.ID)
	if wallet["balance"] != 12 {
		t.Fatal("double redemption")
	}
	if err := f.s.Equip(ctx, u.ID, item.ID, ""); err != nil {
		t.Fatal(err)
	}
	d, _ := f.s.Decorations(ctx, u.ID)
	if d.Avatar != item.Value {
		t.Fatal("decoration not equipped")
	}
	if err := f.s.Redeem(ctx, u.ID, items[1].ID); err != store.ErrInsufficientPoints {
		t.Fatalf("negative balance: %v", err)
	}
	rules, _ := f.s.GrowthRules(ctx)
	rules.RequestCost = 5
	if err := f.s.SaveGrowthRules(ctx, rules); err != nil {
		t.Fatal(err)
	}
	req := store.MovieRequest{UserID: u.ID, Title: "想看的番剧"}
	if err := f.s.CreateMovieRequest(ctx, &req); err != nil {
		t.Fatal(err)
	}
	duplicate := store.MovieRequest{UserID: u.ID, Title: req.Title}
	if err := f.s.CreateMovieRequest(ctx, &duplicate); err != store.ErrConflict {
		t.Fatal("duplicate request accepted")
	}
	if err := f.s.ResolveMovieRequest(ctx, req.ID, f.admin.ID, "rejected", "未找到资源"); err != nil {
		t.Fatal(err)
	}
	if err := f.s.ResolveMovieRequest(ctx, req.ID, f.admin.ID, "rejected", "重复退款"); err != store.ErrConflict {
		t.Fatal("repeated refund accepted")
	}
	wallet, _ = f.s.Wallet(ctx, u.ID)
	if wallet["balance"] != 12 {
		t.Fatal("wrong refund")
	}
	// Ledger remains private to the current account.
	f.request("GET", "/api/user/points", "", nil, 401)
	other := decodeContentData[map[string]any](t, f.request("GET", "/api/user/points?user_id=2", "", f.bob, 200))
	if other["balance"] != float64(5) {
		t.Fatal("wallet ownership bypass")
	}
}
