package api

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"video-collection-service/pkg/auth"
	"video-collection-service/pkg/cache"
)

// 缓存命名空间划分（读多写少的公开接口才值得缓存，管理端接口直连数据库保证实时性）。
const (
	nsVideos      = "videos"       // 视频列表 / 检索
	nsVideoDetail = "video_detail" // 视频详情
	nsCategories  = "categories"   // 分类
	nsRankings    = "rankings"     // 排行榜（热度随播放累加，短 TTL）
	nsLatest      = "latest"       // 最近更新
	nsSite        = "site"         // 站点配置
	nsPlayer      = "player"       // 当前激活播放器
)

// serverCache 汇聚各命名空间，nil 表示未接入 Redis，全部接口透传数据库。
type serverCache struct {
	videos     *cache.Namespace
	detail     *cache.Namespace
	categories *cache.Namespace
	rankings   *cache.Namespace
	latest     *cache.Namespace
	site       *cache.Namespace
	player     *cache.Namespace
}

// UseCache 接入 radix/Redis 缓存。ttl<=0 时使用默认 120s。
// 传入 nil 或未启用 Redis 时，所有缓存方法均为透传（等价于未接入）。
func (srv *Server) UseCache(c *cache.Client, ttl time.Duration) {
	if ttl <= 0 {
		ttl = 120 * time.Second
	}
	srv.sc = &serverCache{
		videos:     c.Namespace(nsVideos, ttl),
		detail:     c.Namespace(nsVideoDetail, ttl),
		categories: c.Namespace(nsCategories, ttl),
		rankings:   c.Namespace(nsRankings, 60*time.Second),
		latest:     c.Namespace(nsLatest, 60*time.Second),
		site:       c.Namespace(nsSite, ttl),
		player:     c.Namespace(nsPlayer, ttl),
	}
}

// CacheEnabled 表示缓存层是否已接入 Redis。
func (srv *Server) CacheEnabled() bool {
	return srv.sc != nil && srv.sc.videos.Enabled()
}

// errVideoNotFound 详情接口约定：影片不存在时经 serveCached 统一映射为 404。
var errVideoNotFound = errors.New("video not found")

// serveCached 带缓存地输出 JSON。
// 命中 Redis 时直接输出缓存字节；未命中时执行 produce 生成响应体并回写。
// 缓存故障不影响正确性，只影响性能。
func (srv *Server) serveCached(ctx context.Context, w http.ResponseWriter, ns *cache.Namespace, key string, produce func(context.Context) (any, error)) {
	fail := func(err error) {
		if errors.Is(err, errVideoNotFound) {
			errorResponse(w, http.StatusNotFound, "未找到该影片详情")
			return
		}
		errorResponse(w, http.StatusInternalServerError, err.Error())
	}
	if srv.sc == nil || !ns.Enabled() {
		data, err := produce(ctx)
		if err != nil {
			fail(err)
			return
		}
		jsonResponse(w, http.StatusOK, data)
		return
	}
	payload, err := ns.Fetch(ctx, key, 0, func(ctx context.Context) ([]byte, error) {
		data, err := produce(ctx)
		if err != nil {
			return nil, err
		}
		return json.Marshal(data)
	})
	if err != nil {
		fail(err)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(payload)
}

// invalidateCaches 写操作后统一失效全部公开读缓存（代份递增，旧键由 TTL 自然回收）。
func (srv *Server) invalidateCaches(ctx context.Context) {
	if srv.sc == nil {
		return
	}
	for _, ns := range []*cache.Namespace{
		srv.sc.videos, srv.sc.detail, srv.sc.categories,
		srv.sc.rankings, srv.sc.latest, srv.sc.site, srv.sc.player,
	} {
		ns.Invalidate(ctx)
	}
}

// cachedWrite 包装公开写接口：执行完成后失效相关缓存。
func (srv *Server) cachedWrite(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		h(w, r)
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			srv.invalidateCaches(r.Context())
		}
	}
}

// adminWrite 包装管理端写接口：鉴权 + 执行 + 失效公开读缓存。
// 读方法（GET/HEAD）不触发失效，避免后台轮询把公共缓存打穿。
func (srv *Server) adminWrite(h http.HandlerFunc) http.HandlerFunc {
	return auth.AdminRequired(srv.store, func(w http.ResponseWriter, r *http.Request) {
		h(w, r)
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			srv.invalidateCaches(r.Context())
		}
	})
}

// superAdminWrite 仅超级管理员可执行的写操作（破坏性数据操作专用），写后失效缓存
func (srv *Server) superAdminWrite(h http.HandlerFunc) http.HandlerFunc {
	return auth.SuperAdminRequired(srv.store, func(w http.ResponseWriter, r *http.Request) {
		h(w, r)
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			srv.invalidateCaches(r.Context())
		}
	})
}

// videosCacheKey 由检索参数生成稳定缓存键（排序后拼接，保证同语义同键）。
func videosCacheKey(page, pageSize, typeID int, keyword, area, year, orderBy string, orderDesc bool) string {
	norm := func(s string) string {
		return strings.ToLower(strings.TrimSpace(s))
	}
	parts := []string{
		"p" + strconv.Itoa(page),
		"s" + strconv.Itoa(pageSize),
		"t" + strconv.Itoa(typeID),
		"k" + norm(keyword),
		"a" + norm(area),
		"y" + norm(year),
		"o" + norm(orderBy),
	}
	if orderDesc {
		parts = append(parts, "desc")
	} else {
		parts = append(parts, "asc")
	}
	return strings.Join(parts, ":")
}
