package api

import (
	"context"
	"fmt"
	"testing"
	"video-collection-api/pkg/store"
)

func TestEquippedAppearanceAppearsOnExistingPostsAndReplies(t *testing.T) {
	f := newContentFixture(t)
	ctx := context.Background()
	post := f.post()
	root := decodeContentData[store.Comment](t, f.request("POST", "/api/comments", fmt.Sprintf(`{"target_type":"post","target_id":%d,"content":"旧评论"}`, post.ID), f.alice, 200))
	reply := decodeContentData[store.Comment](t, f.request("POST", "/api/comments", fmt.Sprintf(`{"target_type":"post","target_id":%d,"parent_id":%d,"content":"楼中楼"}`, post.ID, root.ID), f.alice, 200))
	items, err := f.s.ListCosmetics(ctx, f.alice.ID, true)
	if err != nil {
		t.Fatal(err)
	}
	want := store.Decorations{}
	for _, item := range items {
		switch item.Kind {
		case "animated_avatar":
			want.Avatar = item.Value
		case "frame":
			want.Frame = item.Value
		case "badge":
			want.Badge = item.Value
		case "nickname_color":
			if want.NicknameColor != "" {
				continue
			}
			want.NicknameColor = item.Value
		default:
			continue
		}
		item.Price = 0
		if err = f.s.SaveCosmetic(ctx, &item); err != nil {
			t.Fatal(err)
		}
		if err = f.s.Redeem(ctx, f.alice.ID, item.ID); err != nil {
			t.Fatal(err)
		}
		if err = f.s.Equip(ctx, f.alice.ID, item.ID, ""); err != nil {
			t.Fatal(err)
		}
	}
	check := func(avatar, frame, badge, color string) {
		t.Helper()
		if avatar != want.Avatar || frame != want.Frame || badge != want.Badge || color != want.NicknameColor {
			t.Fatalf("public identity mismatch: %q %q %q %q, want %+v", avatar, frame, badge, color, want)
		}
	}
	// Identities are read from current equipment, including content published earlier.
	public := decodeContentData[store.Content](t, f.request("GET", fmt.Sprintf("/api/community/posts?id=%d", post.ID), "", nil, 200))
	check(public.AuthorAvatar, public.AuthorFrame, public.AuthorBadge, public.AuthorColor)
	for _, id := range []int{root.ID, reply.ID} {
		comment := decodeContentData[store.Comment](t, f.request("GET", fmt.Sprintf("/api/comments?id=%d", id), "", nil, 200))
		check(comment.AuthorAvatar, comment.AuthorFrame, comment.AuthorBadge, comment.AuthorColor)
	}
	list := decodeContentData[[]store.Content](t, f.request("GET", "/api/community/posts", "", nil, 200))
	check(list[0].AuthorAvatar, list[0].AuthorFrame, list[0].AuthorBadge, list[0].AuthorColor)
	if err = f.s.Equip(ctx, f.alice.ID, 0, "frame"); err != nil {
		t.Fatal(err)
	}
	want.Frame = ""
	comment := decodeContentData[store.Comment](t, f.request("GET", fmt.Sprintf("/api/comments?id=%d", reply.ID), "", nil, 200))
	check(comment.AuthorAvatar, comment.AuthorFrame, comment.AuthorBadge, comment.AuthorColor)
}
