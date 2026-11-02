package api

import (
	"context"
	"encoding/xml"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"video-collection-service/pkg/store"
)

// RegisterSEORoutes 注册 SEO 相关路由（sitemap、robots、llms.txt）
func (srv *Server) RegisterSEORoutes(mux *http.ServeMux) {
	mux.HandleFunc("/sitemap.xml", srv.handleSitemap)
	mux.HandleFunc("/sitemap_index.xml", srv.handleSitemapIndex)
	mux.HandleFunc("/sitemap_videos.xml", srv.handleSitemapVideos)
	mux.HandleFunc("/robots.txt", srv.handleRobotsTxt)
	mux.HandleFunc("/llms.txt", srv.handleLLMsTxt)
	mux.HandleFunc("/.well-known/llms.txt", srv.handleLLMsTxt)
}

// SitemapIndex XML 结构
type SitemapIndex struct {
	XMLName xml.Name  `xml:"sitemapindex"`
	XMLNS   string    `xml:"xmlns,attr"`
	Sitemap []Sitemap `xml:"sitemap"`
}

type Sitemap struct {
	Loc     string `xml:"loc"`
	LastMod string `xml:"lastmod,omitempty"`
}

// SitemapURLSet XML 结构（Google Video 扩展）
type SitemapURLSet struct {
	XMLName xml.Name     `xml:"urlset"`
	XMLNS   string       `xml:"xmlns,attr"`
	Video   string       `xml:"xmlns:video,attr"`
	URLs    []SitemapURL `xml:"url"`
}

type SitemapURL struct {
	Loc        string         `xml:"loc"`
	LastMod    string         `xml:"lastmod,omitempty"`
	ChangeFreq string         `xml:"changefreq,omitempty"`
	Priority   string         `xml:"priority,omitempty"`
	Video      *SitemapVideo  `xml:"video:video,omitempty"`
}

type SitemapVideo struct {
	ThumbnailLoc  string `xml:"video:thumbnail_loc"`
	Title         string `xml:"video:title"`
	Description   string `xml:"video:description"`
	ContentLoc    string `xml:"video:content_loc,omitempty"`
	PlayerLoc     string `xml:"video:player_loc,omitempty"`
	Duration      int    `xml:"video:duration,omitempty"`
	PublicationDate string `xml:"video:publication_date,omitempty"`
	FamilyFriendly string `xml:"video:family_friendly,omitempty"`
}

func (srv *Server) getSiteOrigin() string {
	// 读取配置中的站点域名，默认为 https://bllii.com
	return "https://bllii.com"
}

// handleSitemapIndex 生成 sitemap index（索引多个 sitemap）
func (srv *Server) handleSitemapIndex(w http.ResponseWriter, r *http.Request) {
	origin := srv.getSiteOrigin()
	now := time.Now().Format("2006-01-02")

	index := SitemapIndex{
		XMLNS: "http://www.sitemaps.org/schemas/sitemap/0.9",
		Sitemap: []Sitemap{
			{Loc: origin + "/sitemap.xml", LastMod: now},
			{Loc: origin + "/sitemap_videos.xml", LastMod: now},
		},
	}

	w.Header().Set("Content-Type", "application/xml; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(xml.Header))
	_ = xml.NewEncoder(w).Encode(index)
}

// handleSitemap 生成主 sitemap（静态页面 + 首批视频）
func (srv *Server) handleSitemap(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	origin := srv.getSiteOrigin()

	// 获取所有视频（分页获取，确保覆盖大部分目录）
	videos, err := srv.getAllPublicVideos(ctx)
	if err != nil {
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	urls := []SitemapURL{
		// 静态页面
		{Loc: origin + "/", ChangeFreq: "daily", Priority: "1.0"},
		{Loc: origin + "/category", ChangeFreq: "daily", Priority: "0.9"},
		{Loc: origin + "/rank", ChangeFreq: "daily", Priority: "0.8"},
		{Loc: origin + "/latest", ChangeFreq: "hourly", Priority: "0.8"},
	}

	// 添加视频详情页和播放页（带 Google Video 扩展）
	for _, video := range videos {
		videoURL := SitemapURL{
			Loc:        fmt.Sprintf("%s/anime/%d", origin, video.ID),
			ChangeFreq: "weekly",
			Priority:   "0.7",
		}

		// 添加 Google Video 扩展元数据
		if video.Pic != "" {
			thumbnailURL := video.Pic
			if !strings.HasPrefix(thumbnailURL, "http") {
				thumbnailURL = origin + thumbnailURL
			}

			description := video.Name
			if video.Remarks != "" {
				description = video.Name + " - " + video.Remarks
			}

			videoURL.Video = &SitemapVideo{
				ThumbnailLoc:    thumbnailURL,
				Title:           video.Name,
				Description:     description,
				PlayerLoc:       fmt.Sprintf("%s/play/%d", origin, video.ID),
				FamilyFriendly:  "yes",
			}

			if video.UpdatedAt.After(time.Time{}) {
				videoURL.Video.PublicationDate = video.UpdatedAt.Format(time.RFC3339)
			}
		}

		urls = append(urls, videoURL)

		// 播放页也加入 sitemap
		urls = append(urls, SitemapURL{
			Loc:        fmt.Sprintf("%s/play/%d", origin, video.ID),
			ChangeFreq: "weekly",
			Priority:   "0.6",
		})
	}

	urlset := SitemapURLSet{
		XMLNS: "http://www.sitemaps.org/schemas/sitemap/0.9",
		Video: "http://www.google.com/schemas/sitemap-video/1.1",
		URLs:  urls,
	}

	w.Header().Set("Content-Type", "application/xml; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(xml.Header))
	_ = xml.NewEncoder(w).Encode(urlset)
}

// handleSitemapVideos 生成视频专用 sitemap（Google Video 扩展）
func (srv *Server) handleSitemapVideos(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	origin := srv.getSiteOrigin()

	videos, err := srv.getAllPublicVideos(ctx)
	if err != nil {
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	urls := []SitemapURL{}

	for _, video := range videos {
		if video.Pic == "" {
			continue
		}

		thumbnailURL := video.Pic
		if !strings.HasPrefix(thumbnailURL, "http") {
			thumbnailURL = origin + thumbnailURL
		}

		description := video.Name
		if video.Remarks != "" {
			description = video.Name + " - " + video.Remarks
		}

		videoURL := SitemapURL{
			Loc:        fmt.Sprintf("%s/anime/%d", origin, video.ID),
			ChangeFreq: "weekly",
			Priority:   "0.7",
			Video: &SitemapVideo{
				ThumbnailLoc:    thumbnailURL,
				Title:           video.Name,
				Description:     description,
				PlayerLoc:       fmt.Sprintf("%s/play/%d", origin, video.ID),
				FamilyFriendly:  "yes",
			},
		}

		if video.UpdatedAt.After(time.Time{}) {
			videoURL.Video.PublicationDate = video.UpdatedAt.Format(time.RFC3339)
		}

		urls = append(urls, videoURL)
	}

	urlset := SitemapURLSet{
		XMLNS: "http://www.sitemaps.org/schemas/sitemap/0.9",
		Video: "http://www.google.com/schemas/sitemap-video/1.1",
		URLs:  urls,
	}

	w.Header().Set("Content-Type", "application/xml; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(xml.Header))
	_ = xml.NewEncoder(w).Encode(urlset)
}

// getAllPublicVideos 获取所有公开视频（分页获取直到全部）
func (srv *Server) getAllPublicVideos(ctx context.Context) ([]store.VideoRecord, error) {
	var allVideos []store.VideoRecord
	pageSize := 100
	page := 1

	for {
		videos, total, err := srv.store.QueryVideos(ctx, store.VideoQuery{
			Page:      page,
			PageSize:  pageSize,
			OrderBy:   "id",
			OrderDesc: true,
		})
		if err != nil {
			return nil, err
		}

		allVideos = append(allVideos, videos...)

		// 如果已经获取了所有视频，或者这一页没有数据，退出循环
		if len(allVideos) >= total || len(videos) == 0 {
			break
		}

		// 为避免无限循环，限制最多获取 5000 条（50 页 * 100 条）
		if page >= 50 {
			break
		}

		page++
	}

	return allVideos, nil
}

// handleRobotsTxt 生成 robots.txt（保留 GEO 允许列表）
func (srv *Server) handleRobotsTxt(w http.ResponseWriter, r *http.Request) {
	robotsTxt := `# Bllii robots.txt
User-agent: *
Allow: /

# Sitemap
Sitemap: https://bllii.com/sitemap.xml
Sitemap: https://bllii.com/sitemap_videos.xml

# GEO 允许列表（AI 爬虫）
User-agent: GPTBot
Allow: /

User-agent: PerplexityBot
Allow: /

User-agent: ClaudeBot
Allow: /

User-agent: Applebot-Extended
Allow: /

User-agent: CCBot
Allow: /
`

	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(robotsTxt))
}

// handleLLMsTxt 生成 llms.txt（用于 LLM 爬虫发现）
func (srv *Server) handleLLMsTxt(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	origin := srv.getSiteOrigin()

	// 获取热门视频作为示例
	hotVideos, _ := srv.store.GetHotVideos(ctx, 0, 10)

	llmsTxt := fmt.Sprintf(`# bllii - 动漫番剧在线播放平台

> bllii 是一个专注于动漫番剧的在线播放与聚合平台

## 主要功能

- 番剧在线播放
- 分类检索与排行榜
- 新番更新时间表
- 用户追番与历史记录

## 主要页面

- 首页: %s/
- 番剧库: %s/category
- 排行榜: %s/rank
- 新番更新: %s/latest

## API 文档

- OpenAPI 规范: %s/openapi.json
- Swagger UI: %s/docs
- RSS 订阅: %s/rss.xml
`, origin, origin, origin, origin, origin, origin, origin)

	if len(hotVideos) > 0 {
		llmsTxt += "\n## 热门番剧示例\n\n"
		for i, v := range hotVideos {
			if i >= 5 {
				break
			}
			llmsTxt += fmt.Sprintf("- %s: %s/anime/%d\n", v.Name, origin, v.ID)
		}
	}

	llmsTxt += fmt.Sprintf(`
## 技术栈

- 后端: Go + PostgreSQL/SQLite
- 前端: React 18 + webfront
- 管理后台: Vue 3

## 数据来源

本平台聚合多个公开视频源，所有内容均来自互联网公开资源。

---

完整文档请访问: %s/docs
`, origin)

	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(llmsTxt))
}
