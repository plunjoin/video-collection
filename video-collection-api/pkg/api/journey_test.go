package api

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"
	"video-collection-api/pkg/store"
)

func TestJourneyTasksAndGrowthAccounting(t *testing.T) {
	f := newContentFixture(t)
	ctx := context.Background()
	now := time.Now()
	f.request("GET", "/api/user/journey", "", nil, 401)
	f.request("POST", "/api/user/missions/claim", `{"key":"first_favorite"}`, f.alice, 400)
	video := &store.VideoRecord{Name: "任务作品"}
	id, err := f.s.SaveVideoAtomic(ctx, video)
	if err != nil {
		t.Fatal(err)
	}
	// An arbitrary favorite without a real library entry must not finish a mission.
	if err = f.s.SaveUserFavorite(ctx, &store.UserFavoriteItem{UserID: f.alice.ID, VideoID: id + 1000, VideoName: "不存在"}); err != nil {
		t.Fatal(err)
	}
	f.request("POST", "/api/user/missions/claim", `{"key":"first_favorite"}`, f.alice, 400)
	if err = f.s.SaveUserFavorite(ctx, &store.UserFavoriteItem{UserID: f.alice.ID, VideoID: id, VideoName: video.Name}); err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	earned := make(chan int, 10)
	errs := make(chan error, 10)
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			n, e := f.s.ClaimGrowthMission(ctx, f.alice.ID, "first_favorite", now)
			earned <- n
			if e != nil {
				errs <- e
			}
		}()
	}
	wg.Wait()
	close(earned)
	close(errs)
	for e := range errs {
		t.Fatal(e)
	}
	total := 0
	for n := range earned {
		total += n
	}
	if total != 15 {
		t.Fatalf("duplicate rewards: %d", total)
	}
	if err = f.s.SaveUserHistory(ctx, &store.UserHistoryItem{UserID: f.alice.ID, VideoID: id, VideoName: video.Name}); err != nil {
		t.Fatal(err)
	}
	f.request("POST", "/api/user/missions/claim", `{"key":"daily_story"}`, f.alice, 200)
	// Tomorrow's claim cannot reuse yesterday's cloud record.
	if _, err = f.s.ClaimGrowthMission(ctx, f.alice.ID, "daily_story", now.AddDate(0, 0, 1)); err == nil {
		t.Fatal("yesterday's record earned a new daily reward")
	}
	comment := &store.Comment{UserID: f.alice.ID, TargetType: "video", TargetID: id, Content: "喜欢这个故事"}
	if err = f.s.AddComment(ctx, comment); err != nil {
		t.Fatal(err)
	}
	f.request("POST", "/api/user/missions/claim", `{"key":"first_comment"}`, f.alice, 200)
	before, err := f.s.Journey(ctx, f.alice.ID)
	if err != nil {
		t.Fatal(err)
	}
	req := &store.MovieRequest{UserID: f.alice.ID, Title: "积分成长退款验证"}
	if err = f.s.CreateMovieRequest(ctx, req); err != nil {
		t.Fatal(err)
	}
	after, err := f.s.Journey(ctx, f.alice.ID)
	if err != nil {
		t.Fatal(err)
	}
	if before["experience"] != after["experience"] {
		t.Fatal("spending reduced growth")
	}
	if err = f.s.ResolveMovieRequest(ctx, req.ID, f.admin.ID, "rejected", "找不到该资源"); err != nil {
		t.Fatal(err)
	}
	after, err = f.s.Journey(ctx, f.alice.ID)
	if err != nil {
		t.Fatal(err)
	}
	if before["experience"] != after["experience"] {
		t.Fatal("refund inflated growth")
	}
	operator := f.staff("operator")
	f.request("POST", "/api/comments", fmt.Sprintf(`{"target_type":"video","target_id":%d,"content":"待审核留言"}`, id), operator, 200)
	f.request("POST", "/api/user/missions/claim", `{"key":"first_comment"}`, operator, 400)
	for i := 6; i >= 0; i-- {
		if _, err = f.s.Checkin(ctx, f.bob.ID, now.AddDate(0, 0, -i)); err != nil {
			t.Fatal(err)
		}
	}
	if n, err := f.s.ClaimGrowthMission(ctx, f.bob.ID, "seven_checkins", now); err != nil || n != 50 {
		t.Fatalf("seven-day achievement: %d %v", n, err)
	}
	f.request("POST", "/api/admin/missions", `{"key":"daily_story","name":"观影足迹","description":"同步云端记录","kind":"history","period":"day","target":1,"reward":12,"active":false}`, f.admin, 200)
	f.request("POST", "/api/user/missions/claim", `{"key":"daily_story"}`, f.alice, 404)
	f.request("POST", "/api/admin/missions", `{"key":"daily_story","name":"改周期","kind":"history","period":"once","target":1,"reward":12,"active":true}`, f.admin, 400)
	observer := f.staff("observer")
	f.request("GET", "/api/admin/missions", "", observer, 200)
	f.request("POST", "/api/admin/missions", `{}`, observer, 403)
}

func TestWishWallPrivacySupportAndOwnership(t *testing.T) {
	f := newContentFixture(t)
	ctx := context.Background()
	f.request("POST", "/api/user/points/checkin", `{}`, f.alice, 200)
	f.request("POST", "/api/admin/growth/rules", `{"active":5,"checkin":10,"streak_step":2,"streak_cap":30,"request_cost":5}`, f.admin, 200)
	req := decodeContentData[store.MovieRequest](t, f.request("POST", "/api/user/movie-requests", `{"title":"只有主动公开才展示","details":"期望找到这个故事"}`, f.alice, 200))
	wall := f.request("GET", "/api/movie-request-wall", "", nil, 200)
	if string(wall["total"]) != "0" {
		t.Fatal("private wish leaked")
	}
	f.request("POST", "/api/user/movie-requests/share", fmt.Sprintf(`{"id":%d,"shared":true}`, req.ID), f.bob, 403)
	f.request("POST", "/api/user/movie-requests/support", fmt.Sprintf(`{"id":%d}`, req.ID), f.bob, 404)
	f.request("POST", "/api/user/movie-requests/share", fmt.Sprintf(`{"id":%d,"shared":true}`, req.ID), f.alice, 200)
	f.request("POST", "/api/user/movie-requests/support", fmt.Sprintf(`{"id":%d}`, req.ID), f.alice, 403)
	f.request("POST", "/api/user/movie-requests/support", fmt.Sprintf(`{"id":%d}`, req.ID), nil, 401)
	f.request("POST", "/api/user/movie-requests/support", fmt.Sprintf(`{"id":%d}`, req.ID), f.staff("operator"), 403)
	var wg sync.WaitGroup
	errs := make(chan error, 8)
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := f.s.SupportMovieRequest(ctx, f.bob.ID, req.ID); err != nil {
				errs <- err
			}
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Fatal(err)
	}
	items, total, err := f.s.MovieRequestWall(ctx, f.bob.ID, 1, 20)
	if err != nil || total != 1 || len(items) != 1 || items[0].SupportCount != 1 || !items[0].Supported {
		t.Fatalf("duplicate assistance: %v %d %v", items, total, err)
	}
	if items[0].Username == f.alice.Username {
		t.Fatal("account name exposed")
	}
	f.request("POST", "/api/user/missions/claim", `{"key":"first_support"}`, f.bob, 200)
	f.request("POST", "/api/user/movie-requests/share", fmt.Sprintf(`{"id":%d,"shared":false}`, req.ID), f.alice, 200)
	wall = f.request("GET", "/api/movie-request-wall", "", nil, 200)
	if string(wall["total"]) != "0" {
		t.Fatal("withdrawn wish leaked")
	}
	f.request("POST", "/api/user/movie-requests/support", fmt.Sprintf(`{"id":%d}`, req.ID), f.admin, 404)
	f.request("POST", "/api/user/movie-requests/share", fmt.Sprintf(`{"id":%d,"shared":true}`, req.ID), f.alice, 200)
	if err = f.s.ResolveMovieRequest(ctx, req.ID, f.admin.ID, "fulfilled", "资源已找到"); err != nil {
		t.Fatal(err)
	}
	wall = f.request("GET", "/api/movie-request-wall", "", nil, 200)
	if string(wall["total"]) != "0" {
		t.Fatal("closed wish still asking for assistance")
	}
	f.request("POST", "/api/user/movie-requests/support", fmt.Sprintf(`{"id":%d}`, req.ID), f.bob, 409)
}
