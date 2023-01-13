package api

import (
	"context"
	"fmt"
	"testing"

	"video-collection-api/pkg/store"
)

func (f *contentFixture) comment(kind string, id, parent int, u *store.User) store.Comment {
	return decodeContentData[store.Comment](f.t, f.request("POST", "/api/comments", fmt.Sprintf(`{"target_type":%q,"target_id":%d,"parent_id":%d,"content":"评论正文"}`, kind, id, parent), u, 200))
}

func TestGenericCommentsTargetsRepliesAndLikes(t *testing.T) {
	f := newContentFixture(t)
	ctx := context.Background()
	videoID, err := f.s.SaveVideoManual(ctx, &store.VideoRecord{Name: "测试影视"})
	if err != nil {
		t.Fatal(err)
	}
	news := decodeContentData[store.Content](t, f.request("POST", "/api/admin/news", `{"title":"资讯","content":"正文","status":"published"}`, f.admin, 200))
	post := f.post()
	for _, target := range []struct {
		kind string
		id   int
	}{{"video", videoID}, {"news", news.ID}, {"post", post.ID}} {
		t.Run(target.kind, func(t *testing.T) {
			root := f.comment(target.kind, target.id, 0, f.alice)
			reply := f.comment(target.kind, target.id, root.ID, f.bob)
			nested := f.comment(target.kind, target.id, reply.ID, f.alice)
			if root.RootID != 0 || reply.RootID != root.ID || nested.RootID != root.ID || nested.ParentID != reply.ID {
				t.Fatalf("invalid hierarchy: %+v %+v %+v", root, reply, nested)
			}
			query := fmt.Sprintf("/api/comments?target_type=%s&target_id=%d", target.kind, target.id)
			result := f.request("GET", query, "", nil, 200)
			roots := decodeContentData[[]store.Comment](t, result)
			if len(roots) != 1 || roots[0].ID != root.ID || roots[0].ReplyCount != 1 {
				t.Fatalf("bad roots: %+v", roots)
			}
			result = f.request("GET", query+fmt.Sprintf("&root_id=%d&page_size=1&page=2", root.ID), "", nil, 200)
			thread := decodeContentData[[]store.Comment](t, result)
			if string(result["total"]) != "2" || len(thread) != 1 || thread[0].ID != nested.ID {
				t.Fatalf("bad thread pagination: %s", result)
			}
			direct := decodeContentData[[]store.Comment](t, f.request("GET", query+fmt.Sprintf("&parent_id=%d", reply.ID), "", nil, 200))
			if len(direct) != 1 || direct[0].ID != nested.ID {
				t.Fatalf("bad direct replies: %+v", direct)
			}
			likeBody := fmt.Sprintf(`{"comment_id":%d}`, reply.ID)
			f.request("POST", "/api/comments/likes", likeBody, f.alice, 200)
			f.request("POST", "/api/comments/likes", likeBody, f.alice, 200)
			liked := decodeContentData[store.Comment](t, f.request("GET", fmt.Sprintf("/api/comments?id=%d", reply.ID), "", f.alice, 200))
			if !liked.Liked || liked.LikeCount != 1 {
				t.Fatalf("bad like: %+v", liked)
			}
			anonymous := decodeContentData[store.Comment](t, f.request("GET", fmt.Sprintf("/api/comments?id=%d", reply.ID), "", nil, 200))
			if anonymous.Liked {
				t.Fatal("viewer state leaked")
			}
			for i := 0; i < 2; i++ {
				f.request("DELETE", fmt.Sprintf("/api/comments/likes?comment_id=%d", reply.ID), "", f.alice, 200)
			}
			f.request("POST", "/api/comments/likes", likeBody, f.alice, 200)
			f.request("DELETE", fmt.Sprintf("/api/comments?id=%d", reply.ID), "", f.alice, 403)
			f.request("DELETE", fmt.Sprintf("/api/comments?id=%d", reply.ID), "", f.bob, 200)
			deleted := decodeContentData[store.Comment](t, f.request("GET", fmt.Sprintf("/api/comments?id=%d", reply.ID), "", f.alice, 200))
			if !deleted.IsDeleted || deleted.Content != "" || deleted.LikeCount != 0 || deleted.ReplyCount != 1 {
				t.Fatalf("bad tombstone: %+v", deleted)
			}
			f.request("POST", "/api/comments/likes", likeBody, f.alice, 404)
			f.request("POST", "/api/comments", fmt.Sprintf(`{"target_type":%q,"target_id":%d,"parent_id":%d,"content":"回复已删除评论"}`, target.kind, target.id, reply.ID), f.alice, 404)
			f.request("GET", fmt.Sprintf("/api/comments?id=%d", nested.ID), "", nil, 200)
			f.request("DELETE", fmt.Sprintf("/api/admin/comments?id=%d", root.ID), "", f.admin, 200)
		})
	}
	// The legacy API shares IDs and remains flat, excluding deleted placeholders.
	legacy := decodeContentData[[]store.CommunityComment](t, f.request("GET", fmt.Sprintf("/api/community/comments?post_id=%d", post.ID), "", nil, 200))
	if len(legacy) != 1 || legacy[0].TargetType != "post" || legacy[0].ParentID == 0 {
		t.Fatalf("bad legacy compatibility: %+v", legacy)
	}
	updated := decodeContentData[store.Content](t, f.request("GET", fmt.Sprintf("/api/community/posts?id=%d", post.ID), "", nil, 200))
	if updated.CommentCount != 1 {
		t.Fatalf("deleted comments counted: %d", updated.CommentCount)
	}
}

func TestCommentNotificationsDeduplicationAndIsolation(t *testing.T) {
	f := newContentFixture(t)
	post := f.post() // Alice is content owner.
	root := f.comment("post", post.ID, 0, f.alice)
	reply := f.comment("post", post.ID, root.ID, f.bob)
	notes := decodeContentData[[]store.Notification](t, f.request("GET", "/api/user/notifications", "", f.alice, 200))
	if len(notes) != 1 || notes[0].CommentID != reply.ID || notes[0].ParentCommentID != root.ID || notes[0].TargetType != "post" || notes[0].TargetID != post.ID {
		t.Fatalf("bad/doubled reply notification: %+v", notes)
	}
	third := f.comment("post", post.ID, reply.ID, f.admin)
	for _, u := range []*store.User{f.alice, f.bob} {
		inbox := decodeContentData[[]store.Notification](t, f.request("GET", "/api/user/notifications", "", u, 200))
		if inbox[0].CommentID != third.ID || inbox[0].ParentCommentID != reply.ID {
			t.Fatalf("missing reply or owner notification: %+v", inbox)
		}
	}
	// Self replies do not notify self, even when also the content owner.
	f.comment("post", post.ID, root.ID, f.alice)
	notes = decodeContentData[[]store.Notification](t, f.request("GET", "/api/user/notifications", "", f.alice, 200))
	if len(notes) != 2 {
		t.Fatal("self reply notification")
	}
	like := fmt.Sprintf(`{"comment_id":%d}`, reply.ID)
	f.request("POST", "/api/comments/likes", like, f.bob, 200)
	f.request("POST", "/api/comments/likes", like, f.admin, 200)
	f.request("POST", "/api/comments/likes", like, f.admin, 200)
	bob := decodeContentData[[]store.Notification](t, f.request("GET", "/api/user/notifications?type=like", "", f.bob, 200))
	if len(bob) != 1 || bob[0].CommentID != reply.ID || bob[0].ActorID != f.admin.ID {
		t.Fatalf("bad like notices: %+v", bob)
	}
	f.request("POST", "/api/user/notifications/read", fmt.Sprintf(`{"ids":[%d]}`, bob[0].ID), f.alice, 404)
	f.request("POST", "/api/user/notifications/read", fmt.Sprintf(`{"ids":[%d]}`, bob[0].ID), f.bob, 200)
	f.request("DELETE", fmt.Sprintf("/api/comments?id=%d", reply.ID), "", f.bob, 200)
	notes = decodeContentData[[]store.Notification](t, f.request("GET", "/api/user/notifications", "", f.alice, 200))
	for _, n := range notes {
		if n.CommentID == reply.ID && n.Content != "" {
			t.Fatal("deleted comment excerpt leaked in inbox")
		}
	}
}

func TestCommentVisibilityAndValidation(t *testing.T) {
	f := newContentFixture(t)
	post := f.post()
	root := f.comment("post", post.ID, 0, f.alice)
	other := f.post()
	f.request("POST", "/api/comments", fmt.Sprintf(`{"target_type":"post","target_id":%d,"parent_id":%d,"content":"跨内容回复"}`, other.ID, root.ID), f.bob, 400)
	f.request("GET", fmt.Sprintf("/api/comments?target_type=post&target_id=%d&root_id=%d", other.ID, root.ID), "", nil, 400)
	f.request("POST", "/api/admin/community/posts", fmt.Sprintf(`{"id":%d,"title":"隐藏","content":"正文","status":"hidden"}`, post.ID), f.admin, 200)
	for _, u := range []*store.User{nil, f.alice, f.admin} {
		f.request("GET", fmt.Sprintf("/api/comments?id=%d", root.ID), "", u, 404)
	}
	f.request("GET", fmt.Sprintf("/api/admin/comments?id=%d", root.ID), "", f.admin, 200)
	f.request("GET", fmt.Sprintf("/api/comments?target_type=post&target_id=%d", post.ID), "", nil, 404)
	f.request("POST", "/api/comments", fmt.Sprintf(`{"target_type":"post","target_id":%d,"content":"隐藏帖子评论"}`, post.ID), f.admin, 404)
	f.request("POST", "/api/comments/likes", fmt.Sprintf(`{"comment_id":%d}`, root.ID), f.bob, 404)
	f.request("DELETE", fmt.Sprintf("/api/comments?id=%d", root.ID), "", f.alice, 200)
	draft := decodeContentData[store.Content](t, f.request("POST", "/api/admin/news", `{"title":"草稿","content":"正文"}`, f.admin, 200))
	f.request("POST", "/api/comments", fmt.Sprintf(`{"target_type":"news","target_id":%d,"content":"草稿评论"}`, draft.ID), f.admin, 404)
	for _, tc := range []struct {
		method, path, body string
		status             int
	}{
		{"POST", "/api/comments", `{"target_type":"arbitrary","target_id":1,"content":"正文"}`, 400},
		{"POST", "/api/comments", `{"target_type":"video","target_id":999999,"content":"正文"}`, 404},
		{"POST", "/api/comments", `{"target_type":"post","target_id":1,"parent_id":-1,"content":"正文"}`, 400},
		{"POST", "/api/comments", `{"target_type":"post","target_id":1,"content":" "}`, 400},
		{"POST", "/api/comments", `{"target_type":"post","target_id":1,"content":"正文","user_id":1}`, 400},
		{"GET", "/api/comments?target_type=post&target_id=1&parent_id=abc", "", 400},
		{"GET", "/api/comments?target_type=post&target_id=1&parent_id=1&root_id=1", "", 400},
		{"GET", "/api/comments?id=0", "", 400},
		{"POST", "/api/comments/likes", `{"comment_id":0}`, 400},
		{"GET", "/api/comments/likes", "", 405},
	} {
		f.request(tc.method, tc.path, tc.body, f.bob, tc.status)
	}
	f.request("POST", "/api/comments", `{}`, nil, 401)
	f.request("POST", "/api/comments/likes", `{}`, f.disabled, 401)
	f.request("DELETE", fmt.Sprintf("/api/admin/comments?id=%d", root.ID), "", f.bob, 401)
	news := decodeContentData[store.Content](t, f.request("POST", "/api/admin/news", `{"title":"资讯","content":"正文","status":"published"}`, f.admin, 200))
	c := f.comment("news", news.ID, 0, f.alice)
	f.request("DELETE", fmt.Sprintf("/api/community/comments?id=%d", c.ID), "", f.alice, 404)
	f.request("GET", fmt.Sprintf("/api/comments?id=%d", c.ID), "", nil, 200)
}
