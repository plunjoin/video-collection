package api

import (
	"context"
	"encoding/xml"
	"fmt"
	"net/http"
	"strings"
	"time"

	"video-collection-service/pkg/store"
)

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
	Loc        string        `xml:"loc"`
	LastMod    string        `xml:"lastmod,omitempty"`
	ChangeFreq string        `xml:"changefreq,omitempty"`
	Priority   string        `xml:"priority,omitempty"`
	Video      *SitemapVideo `xml:"video:video,omitempty"`
}

type SitemapVideo struct {
	ThumbnailLoc    string `xml:"video:thumbnail_loc"`
	Title           string `xml:"video:title"`
	Description     string `xml:"video:description"`
	PlayerLoc       string `xml:"video:player_loc,omitempty"`
	PublicationDate string `xml:"video:publication_date,omitempty"`
	FamilyFriendly  string `xml:"video:family_friendly,omitempty"`
}

func (srv *Server) getSiteOrigin() string {
	// 读取配置中的站点域名，默认为 https://bllii.com
	return "https://bllii.com"
}

// HandleSitemap 生成主 sitemap（静态页面 + 所有视频，带 Google Video 扩展）
func (srv *Server) HandleSitemap(w http.ResponseWriter, r *http.Request) {
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
		{Loc: origin + "/news", ChangeFreq: "weekly", Priority: "0.7"},
		{Loc: origin + "/community", ChangeFreq: "daily", Priority: "0.7"},
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
				ThumbnailLoc:   thumbnailURL,
				Title:          video.Name,
				Description:    description,
				PlayerLoc:      fmt.Sprintf("%s/play/%d", origin, video.ID),
				FamilyFriendly: "yes",
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
	w.Header().Set("Cache-Control", "public, max-age=3600")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(xml.Header))
	_ = xml.NewEncoder(w).Encode(urlset)
}

// getAllPublicVideos 获取所有公开视频（分页获取直到全部）
func (srv *Server) getAllPublicVideos(ctx context.Context) ([]store.VideoRecord, error) {
	var allVideos []store.VideoRecord
	pageSize := 100
	page := 1
	maxPages := 50 // 最多获取 5000 条视频

	for page <= maxPages {
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

		page++
	}

	return allVideos, nil
}

// HandleRobotsTxt 生成 robots.txt（保留 GEO 允许列表）
func (srv *Server) HandleRobotsTxt(w http.ResponseWriter, r *http.Request) {
	origin := srv.getSiteOrigin()

	robotsTxt := fmt.Sprintf(`# AniPocket 故事口袋 Robots.txt
User-agent: *
Allow: /
Disallow: /api/
Disallow: /admin/
Disallow: /login
Disallow: /notifications

# Google & Major Search Engines
User-agent: Googlebot
Allow: /
User-agent: Googlebot-Video
Allow: /
User-agent: Bingbot
Allow: /

# GEO / AI Search Bots (放行 AI 搜索引擎爬虫以优化 GEO 收录)
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

# Sitemap
Sitemap: %s/sitemap.xml
`, origin)

	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=86400")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(robotsTxt))
}

// HandleLLMsTxt 生成 llms.txt（用于 LLM 爬虫发现）
func (srv *Server) HandleLLMsTxt(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	origin := srv.getSiteOrigin()

	// 获取热门视频作为示例
	hotVideos, _ := srv.store.GetHotVideos(ctx, 0, 10)

	llmsTxt := fmt.Sprintf(`# AniPocket 故事口袋 · 影视与番剧智能聚合平台

> AniPocket 是一个现代化的动漫番剧与影视在线浏览、选集播放与同好交流平台。

## 核心频道
- [首页](%s/): 精选番剧、最新更新推荐与热门合集
- [番剧库](%s/category): 多维度题材筛选（热血、恋爱、悬疑、科幻、奇幻、治愈等）
- [人气榜单](%s/rank): 全站热播榜、口碑榜与好评作品推荐
- [新番时间表](%s/latest): 每日番剧更新日历与追番进度同步
- [交流社区](%s/community): 追番心得、番剧讨论与漫迷社区
`, origin, origin, origin, origin, origin)

	if len(hotVideos) > 0 {
		llmsTxt += "\n## 热门番剧与索引精选\n"
		for i, v := range hotVideos {
			if i >= 5 {
				break
			}
			desc := v.Remarks
			if desc == "" {
				desc = v.Name
			}
			// 移除 HTML 标签
			desc = strings.ReplaceAll(desc, "<", "")
			desc = strings.ReplaceAll(desc, ">", "")
			if len(desc) > 100 {
				desc = desc[:100] + "..."
			}
			llmsTxt += fmt.Sprintf("- [%s](%s/anime/%d): %s | %s | %s\n",
				v.Name, origin, v.ID, v.TypeName, v.Area, desc)
		}
	} else {
		llmsTxt += "\n## 热门番剧与索引精选\n- 请访问网站首页与番剧库查看全量作品目录。\n"
	}

	llmsTxt += fmt.Sprintf(`
## 开发者与平台说明
- 平台提供 RESTful API，并支持 PWA 离线浏览与多端播放。
- OpenAPI 文档: %s/openapi.json
- Swagger UI: %s/docs
- RSS 订阅: %s/rss.xml
- 更多详细内容请访问：%s
`, origin, origin, origin, origin)

	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=86400")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(llmsTxt))
}
