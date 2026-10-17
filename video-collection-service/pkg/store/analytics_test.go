package store

import (
	"context"
	"path/filepath"
	"testing"
	"time"
)

func newTestStore(t *testing.T) *SQLiteStore {
	t.Helper()
	s, err := NewSQLiteStore(filepath.Join(t.TempDir(), "analytics.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = s.Close() })
	return s
}

func TestTrackEventValidatesAndPersists(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()

	if err := s.TrackEvent(ctx, AnalyticsEvent{Event: "unknown_event", Visitor: "v1"}); err != ErrInvalidOperation {
		t.Fatalf("expected ErrInvalidOperation for unknown event, got %v", err)
	}
	if err := s.TrackEvent(ctx, AnalyticsEvent{Event: "page_view", Visitor: "bad visitor!"}); err != ErrInvalidOperation {
		t.Fatalf("expected ErrInvalidOperation for bad visitor, got %v", err)
	}

	if err := s.TrackEvent(ctx, AnalyticsEvent{Event: "search", Visitor: "v1", Keyword: "斗罗大陆", DwellMS: 500}); err != nil {
		t.Fatal(err)
	}
	if err := s.TrackEvent(ctx, AnalyticsEvent{Event: "search", Visitor: "v1", Keyword: "斗罗大陆"}); err != nil {
		t.Fatal(err)
	}
	if err := s.TrackEvent(ctx, AnalyticsEvent{Event: "search", Visitor: "v2", Keyword: "海贼王"}); err != nil {
		t.Fatal(err)
	}

	hot, err := s.HotSearchKeywords(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(hot) != 2 || hot[0] != "斗罗大陆" {
		t.Fatalf("unexpected hot keywords: %v", hot)
	}

	var events, visitors int
	if err = s.db.QueryRow("SELECT COUNT(*) FROM analytics_events").Scan(&events); err != nil {
		t.Fatal(err)
	}
	if events != 3 {
		t.Fatalf("expected 3 events, got %d", events)
	}
	if err = s.db.QueryRow("SELECT COUNT(*) FROM visitor_days").Scan(&visitors); err != nil {
		t.Fatal(err)
	}
	if visitors != 2 {
		t.Fatalf("expected 2 visitors, got %d", visitors)
	}
	var dwell int
	if err = s.db.QueryRow("SELECT dwell_ms FROM analytics_events WHERE event='search' AND dwell_ms>0").Scan(&dwell); err != nil {
		t.Fatal(err)
	}
	if dwell != 500 {
		t.Fatalf("expected dwell 500, got %d", dwell)
	}
}

func TestAdsLifecycleAndVisibilityWindow(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	today := time.Now().Format(adDateLayout)
	tomorrow := time.Now().AddDate(0, 0, 1).Format(adDateLayout)
	yesterday := time.Now().AddDate(0, 0, -1).Format(adDateLayout)

	ad := &AdItem{Slot: "banner", Title: "首页横幅", Image: "/brand/ad.png", Link: "/category", Sort: 10, Active: true}
	if err := s.SaveAd(ctx, ad); err != nil {
		t.Fatal(err)
	}
	if ad.ID == 0 {
		t.Fatal("expected generated id")
	}

	if err := s.SaveAd(ctx, &AdItem{Slot: "unknown", Title: "x", Image: "/a.png"}); err != ErrInvalidOperation {
		t.Fatalf("expected ErrInvalidOperation for bad slot, got %v", err)
	}
	if err := s.SaveAd(ctx, &AdItem{Slot: "detail", Title: "缺图", Image: ""}); err != ErrInvalidOperation {
		t.Fatalf("expected ErrInvalidOperation for missing image, got %v", err)
	}
	if err := s.SaveAd(ctx, &AdItem{Slot: "detail", Title: "坏链接", Image: "/a.png", Link: "javascript:alert(1)"}); err != ErrInvalidOperation {
		t.Fatalf("expected ErrInvalidOperation for bad link, got %v", err)
	}

	public, err := s.ListAds(ctx, "banner", false)
	if err != nil {
		t.Fatal(err)
	}
	if len(public) != 1 || public[0].Title != "首页横幅" {
		t.Fatalf("unexpected public ads: %+v", public)
	}

	// 停用后公开渠道不可见，管理渠道仍可见
	ad.Active = false
	if err = s.SaveAd(ctx, ad); err != nil {
		t.Fatal(err)
	}
	public, _ = s.ListAds(ctx, "banner", false)
	if len(public) != 0 {
		t.Fatalf("expected inactive ad hidden from public, got %+v", public)
	}
	admin, _ := s.ListAds(ctx, "banner", true)
	if len(admin) != 1 {
		t.Fatalf("expected inactive ad visible to admin, got %+v", admin)
	}

	// 排期窗口：未开始 / 已过期均不可见
	ad.Active = true
	ad.StartsAt, ad.EndsAt = tomorrow, ""
	if err = s.SaveAd(ctx, ad); err != nil {
		t.Fatal(err)
	}
	public, _ = s.ListAds(ctx, "banner", false)
	if len(public) != 0 {
		t.Fatalf("expected future ad hidden, got %+v", public)
	}
	ad.StartsAt, ad.EndsAt = "", yesterday
	if err = s.SaveAd(ctx, ad); err != nil {
		t.Fatal(err)
	}
	public, _ = s.ListAds(ctx, "banner", false)
	if len(public) != 0 {
		t.Fatalf("expected expired ad hidden, got %+v", public)
	}
	ad.StartsAt, ad.EndsAt = yesterday, tomorrow
	if err = s.SaveAd(ctx, ad); err != nil {
		t.Fatal(err)
	}
	public, _ = s.ListAds(ctx, "banner", false)
	if len(public) != 1 {
		t.Fatalf("expected in-window ad visible, got %+v", public)
	}
	_ = today

	if err = s.DeleteAd(ctx, ad.ID); err != nil {
		t.Fatal(err)
	}
	if err = s.DeleteAd(ctx, ad.ID); err != ErrContentNotFound {
		t.Fatalf("expected ErrContentNotFound on second delete, got %v", err)
	}
}

func TestRetentionStatsCohortMath(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	day := func(offset int) string { return time.Now().AddDate(0, 0, offset).Format("2006-01-02") }

	// A：前天首次访问，昨天回访（次日留存）；B：昨天首次访问；C：今天首次访问
	rows := []struct{ visitor, day string }{
		{"A", day(-2)}, {"A", day(-1)},
		{"B", day(-1)},
		{"C", day(0)},
	}
	for _, r := range rows {
		if err := s.TrackEvent(ctx, AnalyticsEvent{Event: "page_view", Visitor: r.visitor, Day: r.day}); err != nil {
			t.Fatal(err)
		}
	}

	info, err := s.RetentionStats(ctx)
	if err != nil {
		t.Fatal(err)
	}
	byDay := make(map[string]VisitorCohort)
	for _, c := range info.Cohorts {
		byDay[c.Day] = c
	}
	if byDay[day(-2)].NewVisitors != 1 || byDay[day(-2)].NextDay != 100 {
		t.Fatalf("unexpected cohort for %s: %+v", day(-2), byDay[day(-2)])
	}
	// 昨天的新访客今天没有回来 => 次日留存 0%
	if byDay[day(-1)].NewVisitors != 1 || byDay[day(-1)].NextDay != 0 {
		t.Fatalf("unexpected cohort for %s: %+v", day(-1), byDay[day(-1)])
	}
	// 今天的 cohort 观察窗口未结束 => -1
	if byDay[day(0)].NewVisitors != 1 || byDay[day(0)].NextDay != -1 {
		t.Fatalf("unexpected cohort for %s: %+v", day(0), byDay[day(0)])
	}
	if info.TodayNew != 1 {
		t.Fatalf("expected today_new=1, got %d", info.TodayNew)
	}
	// A 与 B 今天都没来，C 是今天新访客 => 今日回访 0
	if info.TodayReturn != 0 {
		t.Fatalf("expected today_return=0, got %d", info.TodayReturn)
	}
}

func TestPenetrationStats(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	u := &User{Username: "pen", Status: 1, Role: "user"}
	if err := s.CreateUser(ctx, u); err != nil {
		t.Fatal(err)
	}
	if err := s.RecordActivity(ctx, u.ID, time.Now()); err != nil {
		t.Fatal(err)
	}
	if err := s.SaveUserFavorite(ctx, &UserFavoriteItem{UserID: u.ID, VideoID: 1, VideoName: "测试"}); err != nil {
		t.Fatal(err)
	}
	if err := s.TrackEvent(ctx, AnalyticsEvent{Event: "rec_click", Visitor: "v1", UserID: u.ID, TargetID: 1}); err != nil {
		t.Fatal(err)
	}

	info, err := s.PenetrationStats(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if info.ActiveUsers != 1 || info.TotalUsers < 1 {
		t.Fatalf("unexpected user counts: %+v", info)
	}
	found := 0
	for _, f := range info.Features {
		switch f.Key {
		case "favorite":
			if f.Count != 1 || f.Rate != 100 {
				t.Fatalf("unexpected favorite penetration: %+v", f)
			}
			found++
		case "rec_click":
			if f.Count != 1 || f.Rate != 100 {
				t.Fatalf("unexpected rec_click penetration: %+v", f)
			}
			found++
		}
	}
	if found != 2 {
		t.Fatalf("expected favorite and rec_click features, got %+v", info.Features)
	}
}

func TestAnalyticsOverviewPlatformPVUV(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	today := businessDay(time.Now())
	yesterday := shiftDay(today, -1)

	// 昨日：网站 2 次浏览 / 1 访客
	for _, ev := range []AnalyticsEvent{
		{Event: "page_view", Visitor: "w1", Day: yesterday, Platform: "web", Page: "/"},
		{Event: "page_view", Visitor: "w1", Day: yesterday, Platform: "web", Page: "/rank"},
	} {
		if err := s.TrackEvent(ctx, ev); err != nil {
			t.Fatal(err)
		}
	}
	// 今日：网站 1 访客 2 次浏览（含停留），App 1 访客 1 次浏览；非法平台归一为 web
	events := []AnalyticsEvent{
		{Event: "page_view", Visitor: "w2", Day: today, Platform: "web", Page: "/"},
		{Event: "page_leave", Visitor: "w2", Day: today, Platform: "web", Page: "/", DwellMS: 62000},
		{Event: "page_view", Visitor: "w2", Day: today, Platform: "weird", Page: "/play/1"},
		{Event: "page_view", Visitor: "a1", Day: today, Platform: "app", Page: "app://home"},
		{Event: "play", Visitor: "a1", Day: today, Platform: "app", TargetID: 9},
	}
	for _, ev := range events {
		if err := s.TrackEvent(ctx, ev); err != nil {
			t.Fatal(err)
		}
	}

	overview, err := s.AnalyticsOverview(ctx)
	if err != nil {
		t.Fatal(err)
	}

	// 今日汇总：PV 3（web 2 + app 1），UV 2（w2 + a1）
	if overview.Today.PV != 3 || overview.Today.WebPV != 2 || overview.Today.AppPV != 1 {
		t.Fatalf("unexpected today PV: %+v", overview.Today)
	}
	if overview.Today.UV != 2 || overview.Today.WebUV != 1 || overview.Today.AppUV != 1 {
		t.Fatalf("unexpected today UV: %+v", overview.Today)
	}
	// 昨日汇总
	if overview.Yesterday.PV != 2 || overview.Yesterday.WebPV != 2 || overview.Yesterday.UV != 1 {
		t.Fatalf("unexpected yesterday summary: %+v", overview.Yesterday)
	}
	// 累计
	if overview.Total.PV != 5 || overview.Total.UV != 3 {
		t.Fatalf("unexpected total summary: %+v", overview.Total)
	}
	// 趋势：30 天曲线今日点
	if len(overview.Trend) != 30 {
		t.Fatalf("expected 30 trend points, got %d", len(overview.Trend))
	}
	if got := overview.Trend[len(overview.Trend)-1]; got.Day != today || got.PV != 3 || got.UV != 2 || got.AppPV != 1 {
		t.Fatalf("unexpected today trend point: %+v", got)
	}
	// 平台分布：web PV 4 / app PV 1，web 占比 80%
	platformBy := map[string]AnalyticsPlatformStats{}
	for _, p := range overview.Platforms {
		platformBy[p.Platform] = p
	}
	if platformBy["web"].PV != 4 || platformBy["web"].UV != 2 || platformBy["web"].Share != 80 {
		t.Fatalf("unexpected web platform stats: %+v", platformBy["web"])
	}
	if platformBy["app"].PV != 1 || platformBy["app"].UV != 1 || platformBy["app"].Share != 20 {
		t.Fatalf("unexpected app platform stats: %+v", platformBy["app"])
	}
	// 热门页面：PV 最高的应是 “/”（2 次），平均停留 62s
	if len(overview.TopPages) == 0 || overview.TopPages[0].Page != "/" || overview.TopPages[0].PV != 2 {
		t.Fatalf("unexpected top pages: %+v", overview.TopPages)
	}
	if overview.TopPages[0].AvgDwellMS != 62000 {
		t.Fatalf("expected avg dwell 62000, got %d", overview.TopPages[0].AvgDwellMS)
	}
	// 事件分布（近 7 天）：page_view 共 5 次（昨日 2 + 今日 3）居首
	if len(overview.Events) == 0 || overview.Events[0].Event != "page_view" || overview.Events[0].Count != 5 {
		t.Fatalf("unexpected events: %+v", overview.Events)
	}
}
