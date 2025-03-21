package api

import (
	"context"
	"encoding/json"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"video-collection-service/pkg/auth"
	"video-collection-service/pkg/store"
)

// ============================================================
// 轻量埋点 / 搜索建议 / 个性化推荐 / 广告位 / 留存看板
// ============================================================

// trackLimiter 轻量级内存限流：同一访客每分钟最多 60 条埋点
type trackLimiter struct {
	mu   sync.Mutex
	hits map[string][]time.Time
}

func (l *trackLimiter) allow(key string) bool {
	if l.hits == nil {
		l.hits = make(map[string][]time.Time)
	}
	now := time.Now()
	window := now.Add(-time.Minute)
	l.mu.Lock()
	defer l.mu.Unlock()
	var kept []time.Time
	for _, t := range l.hits[key] {
		if t.After(window) {
			kept = append(kept, t)
		}
	}
	if len(kept) >= 60 {
		l.hits[key] = kept
		return false
	}
	l.hits[key] = append(kept, now)
	if len(l.hits) > 20000 { // 防止 map 无限增长
		for k, v := range l.hits {
			if len(v) == 0 {
				delete(l.hits, k)
			}
		}
	}
	return true
}

var trackRateLimiter = &trackLimiter{}

func (srv *Server) registerAnalyticsRoutes(mux *http.ServeMux) {
	// 埋点上报（公开，登录用户自动关联身份）
	mux.HandleFunc("/api/track", srv.handleTrack)
	// 搜索建议 / 热搜词（公开）
	mux.HandleFunc("/api/search/suggest", srv.handleSearchSuggest)
	// 个性化推荐（需登录）
	mux.HandleFunc("/api/recommend/for-you", srv.handleRecommendForYou)
	// 广告位物料（公开，按位置拉取）
	mux.HandleFunc("/api/ads", srv.handleAds)
	// 广告位管理（管理员）
	mux.HandleFunc("/api/admin/ads", auth.AdminRequired(srv.store, srv.handleAdminAds))
	// 留存与功能渗透率看板（管理员）
	mux.HandleFunc("/api/admin/retention", auth.AdminRequired(srv.store, srv.handleAdminRetention))
}

// handleTrack 轻量埋点上报：页面停留、推荐点击、广告点击、搜索等
func (srv *Server) handleTrack(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 8<<10)
	var req struct {
		Event    string `json:"event"`
		TargetID int    `json:"target_id"`
		Page     string `json:"page"`
		DwellMS  int    `json:"dwell_ms"`
		Visitor  string `json:"vid"`
		Keyword  string `json:"keyword"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		errorResponse(w, http.StatusBadRequest, "参数解析失败")
		return
	}
	if !trackRateLimiter.allow(strings.TrimSpace(req.Visitor)) {
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "ok"})
		return
	}
	userID := 0
	if u := auth.GetCurrentUser(r, srv.store); u != nil {
		userID = u.ID
	}
	ev := store.AnalyticsEvent{
		UserID:   userID,
		Visitor:  req.Visitor,
		Event:    req.Event,
		TargetID: req.TargetID,
		Page:     req.Page,
		DwellMS:  req.DwellMS,
		Keyword:  req.Keyword,
	}
	if err := srv.store.TrackEvent(r.Context(), ev); err != nil {
		growthError(w, err)
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "ok"})
}

// handleSearchSuggest 搜索自动补全 + 热搜词
func (srv *Server) handleSearchSuggest(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodGet) {
		return
	}
	q := strings.TrimSpace(r.URL.Query().Get("keyword"))
	if q == "" {
		q = strings.TrimSpace(r.URL.Query().Get("q"))
	}
	limit := 8
	if l, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && l >= 1 && l <= 10 {
		limit = l
	}

	// 无输入：返回真实搜索热词（无数据时兜底为高热度番剧名）
	if q == "" {
		hot, err := srv.store.HotSearchKeywords(r.Context(), limit)
		if err != nil {
			errorResponse(w, http.StatusInternalServerError, err.Error())
			return
		}
		if len(hot) == 0 {
			if recs, herr := srv.store.GetHotVideos(r.Context(), 4, limit); herr == nil {
				for _, v := range recs {
					if v.Name != "" {
						hot = append(hot, v.Name)
					}
				}
			}
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": map[string]any{"keyword": "", "suggestions": hot, "hot": true}})
		return
	}

	// 有输入：按作品名模糊匹配返回补全建议
	recs, _, err := srv.store.QueryVideos(r.Context(), store.VideoQuery{
		NameKeyword: q,
		Page:        1,
		PageSize:    limit * 3,
		OrderBy:     "hits",
		OrderDesc:   true,
	})
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	seen := make(map[string]bool)
	suggestions := make([]string, 0, limit)
	for _, v := range recs {
		name := strings.TrimSpace(v.Name)
		if name == "" || seen[name] {
			continue
		}
		seen[name] = true
		suggestions = append(suggestions, name)
		if len(suggestions) >= limit {
			break
		}
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": map[string]any{"keyword": q, "suggestions": suggestions, "hot": false}})
}

// handleRecommendForYou 个性化首页推荐（基于 history/favorites 的标签匹配）
func (srv *Server) handleRecommendForYou(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodGet) {
		return
	}
	u := auth.GetCurrentUser(r, srv.store)
	if u == nil {
		errorResponse(w, http.StatusUnauthorized, "登录后开启专属推荐")
		return
	}
	limit := 12
	if l, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && l >= 4 && l <= 30 {
		limit = l
	}
	items, basedOn, err := srv.recommendForYou(r.Context(), u.ID, limit)
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{
		"code": 1,
		"data": map[string]any{
			"items":        items,
			"based_on":     basedOn,
			"personalized": len(basedOn) > 0,
		},
	})
}

// recommendForYou 标签匹配推荐：
// 1) 汇总播放历史与追剧收藏的类型亲和度（越近期的行为权重越高，收藏权重额外加成）
// 2) 按 Top3 类型的分热门配额拉取，排除已观看/已收藏
// 3) 数据不足时用全网热门补齐；无任何历史时返回空列表（冷启动）
func (srv *Server) recommendForYou(ctx context.Context, userID, limit int) ([]store.VideoRecord, []string, error) {
	history, _ := srv.store.GetUserHistory(ctx, userID, 30)
	favorites, _ := srv.store.GetUserFavorites(ctx, userID, 30)

	seen := make(map[int]bool)
	var ids []int
	historyOrder := make(map[int]int)
	for i, h := range history {
		if !seen[h.VideoID] {
			seen[h.VideoID] = true
			ids = append(ids, h.VideoID)
		}
		historyOrder[h.VideoID] = i
	}
	favSet := make(map[int]bool)
	for _, f := range favorites {
		favSet[f.VideoID] = true
		if !seen[f.VideoID] {
			seen[f.VideoID] = true
			ids = append(ids, f.VideoID)
		}
	}
	if len(ids) == 0 {
		return []store.VideoRecord{}, []string{}, nil
	}

	typeWeight := make(map[int]int)
	typeName := make(map[int]string)
	if recs, _, err := srv.store.QueryVideos(ctx, store.VideoQuery{IDs: ids, Page: 1, PageSize: 60}); err == nil {
		for _, v := range recs {
			w := 3
			if i, ok := historyOrder[v.ID]; ok {
				w = 3 - i/10 // 最近观看的权重最高
				if w < 1 {
					w = 1
				}
			}
			if favSet[v.ID] {
				w += 3
			}
			typeWeight[v.TypeID] += w
			if v.TypeName != "" {
				typeName[v.TypeID] = v.TypeName
			}
		}
	}
	if len(typeWeight) == 0 {
		return []store.VideoRecord{}, []string{}, nil
	}

	type kv struct {
		ID    int
		Score int
	}
	var pairs []kv
	for id, score := range typeWeight {
		pairs = append(pairs, kv{id, score})
	}
	sort.Slice(pairs, func(i, j int) bool {
		if pairs[i].Score != pairs[j].Score {
			return pairs[i].Score > pairs[j].Score
		}
		return pairs[i].ID < pairs[j].ID
	})
	if len(pairs) > 3 {
		pairs = pairs[:3]
	}

	excluded := make([]int, 0, len(seen))
	for id := range seen {
		excluded = append(excluded, id)
	}
	sort.Ints(excluded)

	items := make([]store.VideoRecord, 0, limit)
	added := make(map[int]bool)
	quota := limit/len(pairs) + 1
	for _, p := range pairs {
		if len(items) >= limit {
			break
		}
		recs, _, err := srv.store.QueryVideos(ctx, store.VideoQuery{
			TypeID:     p.ID,
			ExcludeIDs: excluded,
			Page:       1,
			PageSize:   quota * 2,
			OrderBy:    "hits",
			OrderDesc:  true,
		})
		if err != nil {
			continue
		}
		for _, v := range recs {
			if added[v.ID] {
				continue
			}
			added[v.ID] = true
			excluded = append(excluded, v.ID)
			items = append(items, v)
			if len(items) >= limit {
				break
			}
		}
	}
	// 兜底：全网热门补齐剩余额度
	if len(items) < limit {
		recs, _, err := srv.store.QueryVideos(ctx, store.VideoQuery{
			ExcludeIDs: excluded,
			Page:       1,
			PageSize:   (limit - len(items)) * 2,
			OrderBy:    "hits",
			OrderDesc:  true,
		})
		if err == nil {
			for _, v := range recs {
				if added[v.ID] {
					continue
				}
				added[v.ID] = true
				items = append(items, v)
				if len(items) >= limit {
					break
				}
			}
		}
	}

	basedOn := make([]string, 0, len(pairs))
	for _, p := range pairs {
		name := typeName[p.ID]
		if name == "" {
			name = "分类 " + strconv.Itoa(p.ID)
		}
		basedOn = append(basedOn, name)
	}
	return items, basedOn, nil
}

// handleAds 公开广告位拉取
func (srv *Server) handleAds(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodGet) {
		return
	}
	slot := strings.TrimSpace(r.URL.Query().Get("slot"))
	items, err := srv.store.ListAds(r.Context(), slot, false)
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": items})
}

// handleAdminAds 广告位管理（列表 + 新增/更新 + 删除）
func (srv *Server) handleAdminAds(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodGet, http.MethodPost, http.MethodDelete) {
		return
	}
	if r.Method == http.MethodDelete {
		id, _ := strconv.Atoi(r.URL.Query().Get("id"))
		if id <= 0 {
			errorResponse(w, http.StatusBadRequest, "缺少有效 id 参数")
			return
		}
		if err := srv.store.DeleteAd(r.Context(), id); err != nil {
			growthError(w, err)
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "广告已删除"})
		return
	}
	if r.Method == http.MethodGet {
		items, err := srv.store.ListAds(r.Context(), strings.TrimSpace(r.URL.Query().Get("slot")), true)
		if err != nil {
			errorResponse(w, http.StatusInternalServerError, err.Error())
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": items})
		return
	}
	var ad store.AdItem
	if !contentBody(w, r, &ad) {
		return
	}
	if err := srv.store.SaveAd(r.Context(), &ad); err != nil {
		growthError(w, err)
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": ad, "msg": "广告已保存"})
}

// handleAdminRetention 留存与功能渗透率看板数据
func (srv *Server) handleAdminRetention(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodGet) {
		return
	}
	retention, err := srv.store.RetentionStats(r.Context())
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	penetration, err := srv.store.PenetrationStats(r.Context())
	if err != nil {
		errorResponse(w, http.StatusInternalServerError, err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": map[string]any{"retention": retention, "penetration": penetration}})
}
