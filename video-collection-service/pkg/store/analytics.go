package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"
	"unicode/utf8"
)

// ============================================================
// 轻量埋点 / 搜索日志 / 访客留存 / 广告位 存储层
// 由 SQLite 与 PostgreSQL 共享 (SQLContentStore)
// ============================================================

// validTrackEvents 埋点事件白名单（防止脏数据写库）
var validTrackEvents = map[string]bool{
	"page_view":     true,
	"page_leave":    true,
	"rec_click":     true,
	"ad_click":      true,
	"search":        true,
	"favorite":      true,
	"play":          true,
	"impression":    true, // 卡片有效曝光
	"video_click":   true, // 卡片点击（带位置排名）
	"play_progress": true, // 播放进度节点（25/50/75/100）
}

// validAdSlots 广告位白名单
var validAdSlots = map[string]bool{
	"banner":         true, // 首页顶部横幅
	"home_recommend": true, // 首页推荐(番剧列表内)
	"detail":         true, // 详情/播放页
}

// AnalyticsEvent 单条埋点事件
type AnalyticsEvent struct {
	UserID   int
	Visitor  string
	Platform string // web / app，仅两个合法值，为空时按 web 处理
	Event    string
	TargetID int
	Page     string
	DwellMS  int
	Keyword  string // 仅 search 事件使用，写入 search_logs
	Day      string // 为空时按北京时间补全
}

// VisitorCohort 单日新增访客留存快照
type VisitorCohort struct {
	Day         string  `json:"day"`
	NewVisitors int     `json:"new_visitors"`
	NextDay     float64 `json:"next_day_retention"` // 百分比，-1 表示尚无数据
	SevenDay    float64 `json:"seven_day_retention"`
}

// RetentionInfo 留存看板数据
type RetentionInfo struct {
	Cohorts     []VisitorCohort `json:"cohorts"`
	NextDayAvg  float64         `json:"next_day_avg"`  // 有数据 cohort 的次日留存均值(百分比)
	SevenDayAvg float64         `json:"seven_day_avg"` // 有数据 cohort 的 7 日留存均值(百分比)
	TodayNew    int             `json:"today_new"`     // 今日新增访客
	TodayReturn int             `json:"today_return"`  // 今日回访访客（非今日首次出现）
}

// FeaturePenetration 单个功能的使用渗透率
type FeaturePenetration struct {
	Key   string  `json:"key"`
	Name  string  `json:"name"`
	Count int     `json:"count"`
	Rate  float64 `json:"rate"` // 百分比
}

// PenetrationInfo 功能渗透率数据
type PenetrationInfo struct {
	ActiveUsers int                  `json:"active_users"` // 近30天有登录行为的注册用户
	TotalUsers  int                  `json:"total_users"`
	Features    []FeaturePenetration `json:"features"`
}

// AdItem 广告位物料
type AdItem struct {
	ID        int       `json:"id"`
	Slot      string    `json:"slot"`
	Title     string    `json:"title"`
	Image     string    `json:"image"`
	Link      string    `json:"link"`
	VideoID   int       `json:"video_id"`
	Sort      int       `json:"sort"`
	Active    bool      `json:"active"`
	StartsAt  string    `json:"starts_at"` // YYYY-MM-DD，空表示不限
	EndsAt    string    `json:"ends_at"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// AnalyticsStore 埋点与留存存储接口
type AnalyticsStore interface {
	TrackEvent(context.Context, AnalyticsEvent) error
	HotSearchKeywords(context.Context, int) ([]string, error)
	ListAds(context.Context, string, bool) ([]AdItem, error)
	SaveAd(context.Context, *AdItem) error
	DeleteAd(context.Context, int) error
	RetentionStats(context.Context) (*RetentionInfo, error)
	PenetrationStats(context.Context) (*PenetrationInfo, error)
	AnalyticsOverview(context.Context) (*AnalyticsOverviewData, error)
}

// 编译期断言：SQLContentStore 实现 AnalyticsStore
var _ AnalyticsStore = (*SQLContentStore)(nil)

// migrateAnalytics 创建埋点/搜索日志/访客/广告相关表（幂等）
func migrateAnalytics(tx *sql.Tx, id, timestamp string) error {
	schema := fmt.Sprintf(`
CREATE TABLE IF NOT EXISTS analytics_events(id %s,user_id INTEGER NOT NULL DEFAULT 0,event TEXT NOT NULL,target_id INTEGER NOT NULL DEFAULT 0,page TEXT NOT NULL DEFAULT '',dwell_ms INTEGER NOT NULL DEFAULT 0,day TEXT NOT NULL,platform TEXT NOT NULL DEFAULT 'web',created_at %s NOT NULL);
CREATE INDEX IF NOT EXISTS idx_events_day ON analytics_events(day,event);
CREATE INDEX IF NOT EXISTS idx_events_user ON analytics_events(user_id,event);
CREATE TABLE IF NOT EXISTS search_logs(id %s,user_id INTEGER NOT NULL DEFAULT 0,keyword TEXT NOT NULL,day TEXT NOT NULL,created_at %s NOT NULL);
CREATE INDEX IF NOT EXISTS idx_search_logs_day ON search_logs(day);
CREATE TABLE IF NOT EXISTS visitor_days(day TEXT NOT NULL,visitor TEXT NOT NULL,user_id INTEGER NOT NULL DEFAULT 0,platform TEXT NOT NULL DEFAULT 'web',created_at %s NOT NULL,PRIMARY KEY(day,visitor));
CREATE TABLE IF NOT EXISTS ads(id %s,slot TEXT NOT NULL,title TEXT NOT NULL DEFAULT '',image TEXT NOT NULL DEFAULT '',link TEXT NOT NULL DEFAULT '',video_id INTEGER NOT NULL DEFAULT 0,sort INTEGER NOT NULL DEFAULT 0,active INTEGER NOT NULL DEFAULT 1 CHECK(active IN(0,1)),starts_at TEXT NOT NULL DEFAULT '',ends_at TEXT NOT NULL DEFAULT '',created_at %s NOT NULL,updated_at %s NOT NULL);
CREATE INDEX IF NOT EXISTS idx_ads_slot ON ads(slot,active,sort);
	`, id, timestamp, id, timestamp, timestamp, id, timestamp, timestamp)
	err := execScript(tx, schema)
	return err
}

// sanitizeVisitor 清洗匿名访客标识
func sanitizeVisitor(v string) string {
	v = strings.TrimSpace(v)
	if utf8.RuneCountInString(v) > 64 {
		v = string([]rune(v)[:64])
	}
	for _, r := range v {
		if !(r >= '0' && r <= '9' || r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r == '-' || r == '_') {
			return ""
		}
	}
	return v
}

// TrackEvent 写入一条埋点事件，并登记当日访客（用于留存统计）
func (s *SQLContentStore) TrackEvent(ctx context.Context, ev AnalyticsEvent) error {
	ev.Event = strings.ToLower(strings.TrimSpace(ev.Event))
	if !validTrackEvents[ev.Event] {
		return ErrInvalidOperation
	}
	visitor := sanitizeVisitor(ev.Visitor)
	if visitor == "" {
		return ErrInvalidOperation
	}
	ev.Platform = strings.ToLower(strings.TrimSpace(ev.Platform))
	if ev.Platform != "app" {
		ev.Platform = "web"
	}
	ev.Page = strings.TrimSpace(ev.Page)
	if utf8.RuneCountInString(ev.Page) > 64 {
		ev.Page = string([]rune(ev.Page)[:64])
	}
	if ev.DwellMS < 0 {
		ev.DwellMS = 0
	}
	if ev.DwellMS > 6*3600*1000 {
		ev.DwellMS = 6 * 3600 * 1000
	}
	if ev.Day == "" {
		ev.Day = businessDay(time.Now())
	}
	ev.Keyword = strings.TrimSpace(ev.Keyword)
	if utf8.RuneCountInString(ev.Keyword) > 60 {
		ev.Keyword = string([]rune(ev.Keyword)[:60])
	}
	now := time.Now().UTC().Format(time.RFC3339Nano)

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err = tx.ExecContext(ctx, "INSERT INTO analytics_events(user_id,event,target_id,page,dwell_ms,day,platform,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8)",
		ev.UserID, ev.Event, ev.TargetID, ev.Page, ev.DwellMS, ev.Day, ev.Platform, now); err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO visitor_days(day,visitor,user_id,platform,created_at) VALUES($1,$2,$3,$4,$5) ON CONFLICT(day,visitor) DO NOTHING",
		ev.Day, visitor, ev.UserID, ev.Platform, now); err != nil {
		return err
	}
	if ev.Event == "search" && ev.Keyword != "" {
		if _, err = tx.ExecContext(ctx, "INSERT INTO search_logs(user_id,keyword,day,created_at) VALUES($1,$2,$3,$4)",
			ev.UserID, ev.Keyword, ev.Day, now); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// HotSearchKeywords 近 7 天真实搜索热词（无数据时返回空列表，由调用方兜底）
func (s *SQLContentStore) HotSearchKeywords(ctx context.Context, limit int) ([]string, error) {
	if limit <= 0 || limit > 20 {
		limit = 10
	}
	start := businessDay(time.Now().AddDate(0, 0, -6))
	rows, err := s.db.QueryContext(ctx, "SELECT keyword,COUNT(*) AS c FROM search_logs WHERE day >= $1 GROUP BY keyword ORDER BY c DESC LIMIT $2", start, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var kws []string
	for rows.Next() {
		var kw string
		var c int
		if err = rows.Scan(&kw, &c); err != nil {
			return nil, err
		}
		if kw = strings.TrimSpace(kw); kw != "" {
			kws = append(kws, kw)
		}
	}
	return kws, rows.Err()
}

// ---------- 广告位 ----------

func scanAd(row interface{ Scan(...any) error }) (*AdItem, error) {
	var a AdItem
	var active int
	err := row.Scan(&a.ID, &a.Slot, &a.Title, &a.Image, &a.Link, &a.VideoID, &a.Sort, &active, &a.StartsAt, &a.EndsAt, &a.CreatedAt, &a.UpdatedAt)
	if err != nil {
		return nil, err
	}
	a.Active = active == 1
	return &a, nil
}

// ListAds 广告位列表；slot 为空返回全部；admin=false 时仅返回上架且在有效期内的物料
func (s *SQLContentStore) ListAds(ctx context.Context, slot string, admin bool) ([]AdItem, error) {
	where := "WHERE ($1='' OR slot=$1)"
	if !admin {
		today := businessDay(time.Now())
		where += " AND active=1 AND (starts_at='' OR starts_at<=$2) AND (ends_at='' OR ends_at>=$2)"
		rows, err := s.db.QueryContext(ctx, "SELECT id,slot,title,image,link,video_id,sort,active,starts_at,ends_at,created_at,updated_at FROM ads "+where+" ORDER BY sort DESC,id DESC", slot, today)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		items := []AdItem{}
		for rows.Next() {
			a, err := scanAd(rows)
			if err != nil {
				return nil, err
			}
			items = append(items, *a)
		}
		return items, rows.Err()
	}
	rows, err := s.db.QueryContext(ctx, "SELECT id,slot,title,image,link,video_id,sort,active,starts_at,ends_at,created_at,updated_at FROM ads "+where+" ORDER BY slot,sort DESC,id DESC", slot)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []AdItem{}
	for rows.Next() {
		a, err := scanAd(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, *a)
	}
	return items, rows.Err()
}

// adDateLayout 广告排期日期格式
const adDateLayout = "2006-01-02"

// SaveAd 新增或更新广告物料
func (s *SQLContentStore) SaveAd(ctx context.Context, a *AdItem) error {
	a.Slot = strings.ToLower(strings.TrimSpace(a.Slot))
	a.Title = strings.TrimSpace(a.Title)
	a.Image = strings.TrimSpace(a.Image)
	a.Link = strings.TrimSpace(a.Link)
	a.StartsAt = strings.TrimSpace(a.StartsAt)
	a.EndsAt = strings.TrimSpace(a.EndsAt)
	if !validAdSlots[a.Slot] {
		return ErrInvalidOperation
	}
	if a.Title == "" || utf8.RuneCountInString(a.Title) > 60 {
		return ErrInvalidOperation
	}
	if utf8.RuneCountInString(a.Image) > 512 || utf8.RuneCountInString(a.Link) > 512 {
		return ErrInvalidOperation
	}
	if a.Image == "" {
		return ErrInvalidOperation
	}
	if a.Link != "" && !strings.HasPrefix(a.Link, "/") && !strings.HasPrefix(a.Link, "https://") {
		return ErrInvalidOperation
	}
	if a.Sort < 0 || a.Sort > 9999 || a.VideoID < 0 || a.VideoID > 1<<31 {
		return ErrInvalidOperation
	}
	for _, d := range []string{a.StartsAt, a.EndsAt} {
		if d != "" {
			if _, err := time.Parse(adDateLayout, d); err != nil {
				return ErrInvalidOperation
			}
		}
	}
	if a.StartsAt != "" && a.EndsAt != "" && a.StartsAt > a.EndsAt {
		return ErrInvalidOperation
	}
	now := time.Now().UTC().Format(time.RFC3339Nano)
	if a.ID == 0 {
		return s.db.QueryRowContext(ctx, "INSERT INTO ads(slot,title,image,link,video_id,sort,active,starts_at,ends_at,created_at,updated_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING id",
			a.Slot, a.Title, a.Image, a.Link, a.VideoID, a.Sort, boolInt(a.Active), a.StartsAt, a.EndsAt, now, now).Scan(&a.ID)
	}
	res, err := s.db.ExecContext(ctx, "UPDATE ads SET slot=$1,title=$2,image=$3,link=$4,video_id=$5,sort=$6,active=$7,starts_at=$8,ends_at=$9,updated_at=$10 WHERE id=$11",
		a.Slot, a.Title, a.Image, a.Link, a.VideoID, a.Sort, boolInt(a.Active), a.StartsAt, a.EndsAt, now, a.ID)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrConflict
	}
	return nil
}

// DeleteAd 删除广告物料
func (s *SQLContentStore) DeleteAd(ctx context.Context, id int) error {
	res, err := s.db.ExecContext(ctx, "DELETE FROM ads WHERE id=$1", id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrContentNotFound
	}
	return nil
}

// ---------- 留存与功能渗透率 ----------

// RetentionStats 近 30 天访客留存（匿名访客 + 登录用户均可）
func (s *SQLContentStore) RetentionStats(ctx context.Context) (*RetentionInfo, error) {
	start := businessDay(time.Now().AddDate(0, 0, -29))
	rows, err := s.db.QueryContext(ctx, "SELECT day,visitor FROM visitor_days WHERE day >= $1", start)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	visitorDays := make(map[string]map[string]bool) // visitor -> set(day)
	for rows.Next() {
		var day, visitor string
		if err = rows.Scan(&day, &visitor); err != nil {
			return nil, err
		}
		if visitorDays[visitor] == nil {
			visitorDays[visitor] = make(map[string]bool)
		}
		visitorDays[visitor][day] = true
	}
	if err = rows.Err(); err != nil {
		return nil, err
	}

	firstDay := make(map[string]string)
	cohortSize := make(map[string]int)
	nextRetained := make(map[string]int)
	sevenRetained := make(map[string]int)
	for visitor, days := range visitorDays {
		var earliest string
		for d := range days {
			if earliest == "" || d < earliest {
				earliest = d
			}
		}
		firstDay[visitor] = earliest
		cohortSize[earliest]++
		nextDate := shiftDay(earliest, 1)
		sevenDate := shiftDay(earliest, 7)
		if days[nextDate] {
			nextRetained[earliest]++
		}
		if days[sevenDate] {
			sevenRetained[earliest]++
		}
	}

	// 最近 14 天 cohort 展示（更早的 cohort 样本太小）
	info := &RetentionInfo{}
	today := businessDay(time.Now())
	var nextSum, sevenSum float64
	var nextCount, sevenCount int
	for i := 13; i >= 0; i-- {
		day := shiftDay(today, -i)
		c := VisitorCohort{Day: day, NewVisitors: cohortSize[day], NextDay: -1, SevenDay: -1}
		if size := cohortSize[day]; size > 0 {
			nextDate := shiftDay(day, 1)
			sevenDate := shiftDay(day, 7)
			// 仅统计已有完整观察窗口的 cohort，否则记 -1（尚无数据）
			if nextDate <= today {
				nextRate := float64(nextRetained[day]) / float64(size) * 100
				c.NextDay = round1(nextRate)
				nextSum += nextRate
				nextCount++
			}
			if sevenDate <= today {
				sevenRate := float64(sevenRetained[day]) / float64(size) * 100
				c.SevenDay = round1(sevenRate)
				sevenSum += sevenRate
				sevenCount++
			}
		}
		info.Cohorts = append(info.Cohorts, c)
	}
	if nextCount > 0 {
		info.NextDayAvg = round1(nextSum / float64(nextCount))
	}
	if sevenCount > 0 {
		info.SevenDayAvg = round1(sevenSum / float64(sevenCount))
	}

	todayTotal, todayReturn := 0, 0
	for _, days := range visitorDays {
		if days[today] {
			todayTotal++
			appearedBefore := false
			for d := range days {
				if d < today {
					appearedBefore = true
					break
				}
			}
			if appearedBefore {
				todayReturn++
			}
		}
	}
	info.TodayNew = cohortSize[today]
	info.TodayReturn = todayReturn
	return info, nil
}

func round1(v float64) float64 {
	return float64(int64(v*10+0.5)) / 10
}

// shiftDay 按 UTC 日期字符串平移 n 天
func shiftDay(day string, n int) string {
	t, err := time.Parse("2006-01-02", day)
	if err != nil {
		return day
	}
	return t.AddDate(0, 0, n).Format("2006-01-02")
}

// PenetrationStats 功能渗透率（近30天活跃注册用户为分母）
func (s *SQLContentStore) PenetrationStats(ctx context.Context) (*PenetrationInfo, error) {
	info := &PenetrationInfo{}
	if err := s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM users").Scan(&info.TotalUsers); err != nil {
		return nil, err
	}
	activeStart := businessDay(time.Now().AddDate(0, 0, -29))
	if err := s.db.QueryRowContext(ctx, "SELECT COUNT(DISTINCT user_id) FROM daily_activity WHERE day >= $1", activeStart).Scan(&info.ActiveUsers); err != nil {
		return nil, err
	}
	denominator := info.ActiveUsers
	if denominator == 0 {
		denominator = info.TotalUsers
	}

	type featureQuery struct {
		key   string
		name  string
		query string
	}
	features := []featureQuery{
		{"history", "播放历史", "SELECT COUNT(DISTINCT user_id) FROM user_history"},
		{"favorite", "追剧收藏", "SELECT COUNT(DISTINCT user_id) FROM user_favorites"},
		{"search", "站内搜索", "SELECT COUNT(DISTINCT user_id) FROM search_logs WHERE user_id > 0"},
		{"rec_click", "个性化推荐点击", "SELECT COUNT(DISTINCT user_id) FROM analytics_events WHERE event='rec_click' AND user_id > 0"},
		{"comment", "评论互动", "SELECT COUNT(DISTINCT user_id) FROM comments WHERE is_deleted=0"},
	}
	for _, f := range features {
		var count int
		if err := s.db.QueryRowContext(ctx, f.query).Scan(&count); err != nil {
			// comments 表由内容模块负责迁移，极端情况下缺失时记 0 不影响整体看板
			if errors.Is(err, sql.ErrNoRows) {
				count = 0
			} else if strings.Contains(err.Error(), "no such table") {
				count = 0
			} else {
				return nil, err
			}
		}
		rate := 0.0
		if denominator > 0 {
			rate = round1(float64(count) / float64(denominator) * 100)
		}
		info.Features = append(info.Features, FeaturePenetration{Key: f.key, Name: f.name, Count: count, Rate: rate})
	}
	sort.SliceStable(info.Features, func(i, j int) bool { return info.Features[i].Rate > info.Features[j].Rate })
	return info, nil
}

// ---------- 埋点总览（网站 / App PV / UV） ----------

// AnalyticsSummary 单日或累计 PV/UV 汇总
type AnalyticsSummary struct {
	PV    int `json:"pv"`
	UV    int `json:"uv"`
	WebPV int `json:"web_pv"`
	AppPV int `json:"app_pv"`
	WebUV int `json:"web_uv"`
	AppUV int `json:"app_uv"`
}

// AnalyticsDailyPoint 单日趋势点（近 30 天曲线用）
type AnalyticsDailyPoint struct {
	Day   string `json:"day"`
	PV    int    `json:"pv"`
	UV    int    `json:"uv"`
	WebPV int    `json:"web_pv"`
	AppPV int    `json:"app_pv"`
	WebUV int    `json:"web_uv"`
	AppUV int    `json:"app_uv"`
}

// AnalyticsPlatformStats 平台维度统计（web / app）
type AnalyticsPlatformStats struct {
	Platform string  `json:"platform"`
	PV       int     `json:"pv"`
	UV       int     `json:"uv"`
	Share    float64 `json:"share"` // PV 占比（百分比）
}

// AnalyticsTopPage 热门页面（近 7 天）
type AnalyticsTopPage struct {
	Page       string `json:"page"`
	PV         int    `json:"pv"`
	AvgDwellMS int    `json:"avg_dwell_ms"` // page_leave 平均停留毫秒数
}

// AnalyticsEventCount 埋点事件类型计数（近 7 天）
type AnalyticsEventCount struct {
	Event string `json:"event"`
	Name  string `json:"name"`
	Count int    `json:"count"`
}

// AnalyticsOverviewData 埋点信息预览总览
type AnalyticsOverviewData struct {
	Today     AnalyticsSummary         `json:"today"`
	Yesterday AnalyticsSummary         `json:"yesterday"`
	Total     AnalyticsSummary         `json:"total"`
	Trend     []AnalyticsDailyPoint    `json:"trend"`     // 近 30 天
	Platforms []AnalyticsPlatformStats `json:"platforms"` // 近 30 天平台分布
	TopPages  []AnalyticsTopPage       `json:"top_pages"` // 近 7 天热门页面
	Events    []AnalyticsEventCount    `json:"events"`    // 近 7 天事件分布
}

// analyticsEventNames 埋点事件中文名
var analyticsEventNames = map[string]string{
	"page_view":     "页面浏览",
	"page_leave":    "页面离开",
	"play":          "播放",
	"play_progress": "播放进度",
	"impression":    "卡片曝光",
	"video_click":   "卡片点击",
	"rec_click":     "推荐点击",
	"ad_click":      "广告点击",
	"search":        "搜索",
	"favorite":      "收藏",
}

// AnalyticsOverview 聚合埋点总览：今日 / 昨日 / 累计 PV-UV、近 30 天趋势、
// 网站 / App 平台分布、近 7 天热门页面与事件分布。
// PV = page_view 事件数；UV = visitor_days 去重访客数。
func (s *SQLContentStore) AnalyticsOverview(ctx context.Context) (*AnalyticsOverviewData, error) {
	overview := &AnalyticsOverviewData{
		Trend:     []AnalyticsDailyPoint{},
		Platforms: []AnalyticsPlatformStats{},
		TopPages:  []AnalyticsTopPage{},
		Events:    []AnalyticsEventCount{},
	}
	today := businessDay(time.Now())
	yesterday := shiftDay(today, -1)
	trendStart := shiftDay(today, -29)
	detailStart := shiftDay(today, -6)

	// 单日 PV（按平台分组）
	dayPV := func(day string) (int, int, error) {
		rows, err := s.db.QueryContext(ctx, "SELECT platform,COUNT(*) FROM analytics_events WHERE event='page_view' AND day=$1 GROUP BY platform", day)
		if err != nil {
			return 0, 0, err
		}
		defer rows.Close()
		var web, app int
		for rows.Next() {
			var platform string
			var count int
			if err = rows.Scan(&platform, &count); err != nil {
				return 0, 0, err
			}
			if platform == "app" {
				app = count
			} else {
				web = count
			}
		}
		return web, app, rows.Err()
	}

	// 单日 UV（按平台分组）
	dayUV := func(day string) (int, int, error) {
		rows, err := s.db.QueryContext(ctx, "SELECT platform,COUNT(*) FROM visitor_days WHERE day=$1 GROUP BY platform", day)
		if err != nil {
			return 0, 0, err
		}
		defer rows.Close()
		var web, app int
		for rows.Next() {
			var platform string
			var count int
			if err = rows.Scan(&platform, &count); err != nil {
				return 0, 0, err
			}
			if platform == "app" {
				app = count
			} else {
				web = count
			}
		}
		return web, app, rows.Err()
	}

	daySummary := func(day string) (AnalyticsSummary, error) {
		summary := AnalyticsSummary{}
		var err error
		if summary.WebPV, summary.AppPV, err = dayPV(day); err != nil {
			return summary, err
		}
		if summary.WebUV, summary.AppUV, err = dayUV(day); err != nil {
			return summary, err
		}
		summary.PV = summary.WebPV + summary.AppPV
		summary.UV = summary.WebUV + summary.AppUV
		return summary, nil
	}

	var err error
	if overview.Today, err = daySummary(today); err != nil {
		return nil, err
	}
	if overview.Yesterday, err = daySummary(yesterday); err != nil {
		return nil, err
	}

	// 累计汇总：全量 page_view 计数与全量去重访客
	totalPVRows, err := s.db.QueryContext(ctx, "SELECT platform,COUNT(*) FROM analytics_events WHERE event='page_view' GROUP BY platform")
	if err != nil {
		return nil, err
	}
	for totalPVRows.Next() {
		var platform string
		var count int
		if err = totalPVRows.Scan(&platform, &count); err != nil {
			totalPVRows.Close()
			return nil, err
		}
		if platform == "app" {
			overview.Total.AppPV = count
		} else {
			overview.Total.WebPV = count
		}
	}
	if err = totalPVRows.Err(); err != nil {
		totalPVRows.Close()
		return nil, err
	}
	totalPVRows.Close()

	totalUVRows, err := s.db.QueryContext(ctx, "SELECT platform,COUNT(DISTINCT visitor) FROM visitor_days GROUP BY platform")
	if err != nil {
		return nil, err
	}
	for totalUVRows.Next() {
		var platform string
		var count int
		if err = totalUVRows.Scan(&platform, &count); err != nil {
			totalUVRows.Close()
			return nil, err
		}
		if platform == "app" {
			overview.Total.AppUV = count
		} else {
			overview.Total.WebUV = count
		}
	}
	if err = totalUVRows.Err(); err != nil {
		totalUVRows.Close()
		return nil, err
	}
	totalUVRows.Close()
	overview.Total.PV = overview.Total.WebPV + overview.Total.AppPV
	overview.Total.UV = overview.Total.WebUV + overview.Total.AppUV

	// 近 30 天趋势（PV / UV，均带平台拆分），缺失日期补零
	type dayPlatform struct {
		Day, Platform string
	}
	trendPV := make(map[dayPlatform]int)
	rows, err := s.db.QueryContext(ctx, "SELECT day,platform,COUNT(*) FROM analytics_events WHERE event='page_view' AND day>=$1 GROUP BY day,platform", trendStart)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var key dayPlatform
		var count int
		if err = rows.Scan(&key.Day, &key.Platform, &count); err != nil {
			rows.Close()
			return nil, err
		}
		trendPV[key] = count
	}
	if err = rows.Err(); err != nil {
		rows.Close()
		return nil, err
	}
	rows.Close()

	trendUV := make(map[dayPlatform]int)
	rows, err = s.db.QueryContext(ctx, "SELECT day,platform,COUNT(*) FROM visitor_days WHERE day>=$1 GROUP BY day,platform", trendStart)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var key dayPlatform
		var count int
		if err = rows.Scan(&key.Day, &key.Platform, &count); err != nil {
			rows.Close()
			return nil, err
		}
		trendUV[key] = count
	}
	if err = rows.Err(); err != nil {
		rows.Close()
		return nil, err
	}
	rows.Close()

	window := AnalyticsSummary{}
	for i := 29; i >= 0; i-- {
		day := shiftDay(today, -i)
		point := AnalyticsDailyPoint{
			Day:   day,
			WebPV: trendPV[dayPlatform{day, "web"}],
			AppPV: trendPV[dayPlatform{day, "app"}],
			WebUV: trendUV[dayPlatform{day, "web"}],
			AppUV: trendUV[dayPlatform{day, "app"}],
		}
		point.PV = point.WebPV + point.AppPV
		point.UV = point.WebUV + point.AppUV
		window.WebPV += point.WebPV
		window.AppPV += point.AppPV
		window.WebUV += point.WebUV
		window.AppUV += point.AppUV
		overview.Trend = append(overview.Trend, point)
	}

	// 平台分布（近 30 天）
	totalWindowPV := window.WebPV + window.AppPV
	for _, stats := range []struct {
		platform string
		pv, uv   int
	}{
		{"web", window.WebPV, window.WebUV},
		{"app", window.AppPV, window.AppUV},
	} {
		share := 0.0
		if totalWindowPV > 0 {
			share = round1(float64(stats.pv) / float64(totalWindowPV) * 100)
		}
		overview.Platforms = append(overview.Platforms, AnalyticsPlatformStats{
			Platform: stats.platform,
			PV:       stats.pv,
			UV:       stats.uv,
			Share:    share,
		})
	}

	// 近 7 天热门页面（page_view 计数 + page_leave 平均停留）
	pagePV := make(map[string]int)
	rows, err = s.db.QueryContext(ctx, "SELECT page,COUNT(*) FROM analytics_events WHERE event='page_view' AND day>=$1 AND page<>'' GROUP BY page ORDER BY COUNT(*) DESC LIMIT 8", detailStart)
	if err != nil {
		return nil, err
	}
	var pageOrder []string
	for rows.Next() {
		var page string
		var count int
		if err = rows.Scan(&page, &count); err != nil {
			rows.Close()
			return nil, err
		}
		pagePV[page] = count
		pageOrder = append(pageOrder, page)
	}
	if err = rows.Err(); err != nil {
		rows.Close()
		return nil, err
	}
	rows.Close()

	dwell := make(map[string]int)
	rows, err = s.db.QueryContext(ctx, "SELECT page,AVG(dwell_ms) FROM analytics_events WHERE event='page_leave' AND day>=$1 AND page<>'' GROUP BY page", detailStart)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var page string
		var avg float64
		if err = rows.Scan(&page, &avg); err != nil {
			rows.Close()
			return nil, err
		}
		if avg > 0 {
			dwell[page] = int(avg)
		}
	}
	if err = rows.Err(); err != nil {
		rows.Close()
		return nil, err
	}
	rows.Close()

	for _, page := range pageOrder {
		overview.TopPages = append(overview.TopPages, AnalyticsTopPage{
			Page:       page,
			PV:         pagePV[page],
			AvgDwellMS: dwell[page],
		})
	}

	// 近 7 天事件分布
	rows, err = s.db.QueryContext(ctx, "SELECT event,COUNT(*) FROM analytics_events WHERE day>=$1 GROUP BY event ORDER BY COUNT(*) DESC", detailStart)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var event string
		var count int
		if err = rows.Scan(&event, &count); err != nil {
			rows.Close()
			return nil, err
		}
		name, ok := analyticsEventNames[event]
		if !ok {
			name = event
		}
		overview.Events = append(overview.Events, AnalyticsEventCount{Event: event, Name: name, Count: count})
	}
	if err = rows.Err(); err != nil {
		rows.Close()
		return nil, err
	}
	rows.Close()

	return overview, nil
}
