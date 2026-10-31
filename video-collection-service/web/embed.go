// Package webui 是 web/ 下所有前端工程的唯一 Go 壳：
// 通过 go:embed 把各前端构建产物打进单二进制，并构造对应的 http.Handler。
// web/admin、web/portal 目录本身保持纯前端工程（不含任何 Go 文件）。
//
// 约定：
//   - web/admin：Vue 3 + Vite SPA，构建到 admin/dist，由 AdminHandler 托管 /admin；
//   - web/portal：React + webfront，构建到 portal/dist，由 PortalHandler 托管 /
//     （SSR 数据注水 + 静态资源 + SPA 回退）；
//   - go:embed 的路径必须位于本包目录内，因此该壳文件只能放在 web/ 根，
//     这是"单二进制内嵌前端"在 Go 侧的最小存在形式，无法进一步消掉。
package webui

import (
	"context"
	"embed"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"path"
	"strconv"
	"strings"

	"github.com/plunjoin/webfront"
	"github.com/plunjoin/webfront/jsruntime"

	"video-collection-service/pkg/store"
)

// resolveVideoWikiSubject 解析视频对应的 Wiki 词条：优先取已绑定的 subject_id，
// 其次按片名精确匹配词条并回填绑定（幂等）。与 pkg/api 中的同名逻辑保持一致。
func resolveVideoWikiSubject(ctx context.Context, dbStore store.Store, video *store.VideoRecord) *store.WikiSubject {
	sub, err := dbStore.GetWikiSubjectByVideoID(ctx, video.ID)
	if err != nil {
		return nil
	}
	if sub != nil {
		return sub
	}
	name := strings.TrimSpace(video.Name)
	if name == "" {
		return nil
	}
	sub, err = dbStore.GetWikiSubjectByName(ctx, name)
	if err != nil || sub == nil {
		return nil
	}
	_ = dbStore.LinkVideoToSubject(ctx, video.ID, sub.ID)
	return sub
}

//go:embed all:admin/dist
var adminFiles embed.FS

//go:embed all:portal/dist
var portalFiles embed.FS

// ---------------------------------------------------------------- 管理后台 --

// AdminHandler 返回管理后台 SPA 处理器。
// 行为：
//   - /admin、/admin/ 及任意 /admin/<route> 未命中静态文件时回退 index.html；
//   - 命中 /admin/assets/* 等静态资源时直接返回（长缓存）；
//   - index.html 不缓存，保证发布后即时生效。
func AdminHandler() http.Handler {
	sub, err := fs.Sub(adminFiles, "admin/dist")
	if err != nil {
		panic("webui: 读取内嵌 admin dist 失败: " + err.Error())
	}
	fileServer := http.FileServer(http.FS(sub))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
			return
		}

		// 归一化子路径：/admin/videos -> /videos
		upath := strings.TrimPrefix(r.URL.Path, "/admin")
		upath = path.Clean("/" + strings.TrimPrefix(upath, "/"))
		if upath == "/" || upath == "." {
			upath = "/index.html"
		}

		// 静态文件存在则直接返回
		// 注意：io/fs 不接受前导斜杠，直接查询前需去掉
		if f, err := sub.Open(strings.TrimPrefix(upath, "/")); err == nil {
			_ = f.Close()
			if upath == "/index.html" {
				w.Header().Set("Cache-Control", "no-cache")
			} else if strings.HasPrefix(upath, "/assets/chunks/") {
				// 带 content-hash 的分包允许强缓存
				w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
			} else if strings.HasPrefix(upath, "/assets/") {
				// 入口产物（assets/client.js / client.css）文件名固定不带 hash，
				// 发布后必须立即生效，走协商缓存（与 PortalHandler 同策略）
				w.Header().Set("Cache-Control", "no-cache, must-revalidate")
			}
			http.StripPrefix("/admin", fileServer).ServeHTTP(w, r)
			return
		}

		// SPA history 路由回退：直接输出内嵌 index.html（避免 FileServer 的
		// /index.html -> ./ 重定向语义在子路径下产生多余跳转）
		index, err := fs.ReadFile(sub, "index.html")
		if err != nil {
			http.Error(w, "管理后台前端尚未构建（web/admin/dist 为空）", http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "no-cache")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(index)
	})
}

// ---------------------------------------------------------------- 前台门户 --

// PortalHandler 返回前台门户 HTTP 处理器，支持全站首屏直出 (SSR) 数据注入。
func PortalHandler(dbStore store.Store) http.Handler {
	sub, err := fs.Sub(portalFiles, "portal/dist")
	if err != nil {
		panic("webui: 读取内嵌 portal dist 失败: " + err.Error())
	}

	cfg := webfront.Config{
		Mode:    webfront.ModeSSR,
		EmbedFS: portalFiles,
		DistDir: "portal/dist",
	}

	// 尝试加载 SSR bundle 并初始化 goja 运行时池
	ssrBytes, err := fs.ReadFile(sub, "ssr.js")
	if err == nil && len(ssrBytes) > 0 {
		pool, err := jsruntime.New(ssrBytes, 4)
		if err == nil {
			cfg.Renderer = pool
		} else {
			fmt.Printf("[portal] 提示: SSR runtime 初始化跳过 (%v)，降级为 SPA 模式\n", err)
			cfg.Mode = webfront.ModeSPA
		}
	} else {
		cfg.Mode = webfront.ModeSPA
	}

	eng, err := webfront.New(cfg)
	if err != nil {
		panic("webui: webfront.New 初始化失败: " + err.Error())
	}

	fileServer := http.FileServer(http.FS(sub))

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
			return
		}

		cleanPath := path.Clean("/" + strings.TrimPrefix(r.URL.Path, "/"))

		// 1. 静态资源（/assets/*、/brand/*、/icons/*、/js/*、/favicon.svg 等）
		if cleanPath != "/" && cleanPath != "/index.html" {
			trimmed := strings.TrimPrefix(cleanPath, "/")
			if f, err := sub.Open(trimmed); err == nil {
				_ = f.Close()
				// 带 content-hash 的 chunk 允许强缓存；主入口 client.js / client.css 走协商缓存
				if strings.HasPrefix(cleanPath, "/assets/chunks/") {
					w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
				} else {
					w.Header().Set("Cache-Control", "no-cache, must-revalidate")
				}
				fileServer.ServeHTTP(w, r)
				return
			}
		}

		ctx := r.Context()

		// 2. 路由重定向与规范化兼容 (/detail?id=xxx -> /anime/xxx 等)
		if cleanPath == "/detail" || cleanPath == "/detail/" {
			if qId := r.URL.Query().Get("id"); qId != "" {
				http.Redirect(w, r, "/anime/"+qId, http.StatusFound)
				return
			}
			http.Redirect(w, r, "/category", http.StatusFound)
			return
		}
		if cleanPath == "/anime" || cleanPath == "/anime/" {
			if qId := r.URL.Query().Get("id"); qId != "" {
				http.Redirect(w, r, "/anime/"+qId, http.StatusFound)
				return
			}
			http.Redirect(w, r, "/category", http.StatusFound)
			return
		}
		if cleanPath == "/play" || cleanPath == "/play/" {
			if qId := r.URL.Query().Get("id"); qId != "" {
				http.Redirect(w, r, "/play/"+qId, http.StatusFound)
				return
			}
		}
		// 旧路由兼容：movie 页历史上仅重定向到分类页
		if cleanPath == "/movie" || cleanPath == "/movie/" {
			http.Redirect(w, r, "/category", http.StatusFound)
			return
		}

		// 3. 服务端数据注水 SSR 处理
		if dbStore != nil {
			// (A) 首页
			if cleanPath == "/" || cleanPath == "/index.html" {
				animes, _ := dbStore.GetHotVideos(ctx, 4, 18)
				if len(animes) < 6 {
					allHot, _ := dbStore.GetHotVideos(ctx, 0, 18)
					animes = append(animes, allHot...)
				}
				for i := range animes {
					animes[i].FillCompatFields()
				}
				// title/description 同时放进 props：entry-server 自产的 <title> 会
				// 覆盖 Page.Head（webfront assemble 只在 head 缺失时才注入），
				// 经 props 传递才能让每路由 SEO 元信息真正生效。
				pageProps := map[string]any{
					"path":        "/",
					"title":       "bllii — 在更多的故事里，遇见更好的你",
					"description": "bllii 动漫番剧在线播放与聚合平台",
					"animeList":   animes,
					"rankings": map[string]any{
						"top": animes,
					},
				}
				err := eng.Render(w, r, webfront.Page{
					URL:   "/",
					Props: pageProps,
					Head: webfront.Head{
						Title:       "bllii — 在更多的故事里，遇见更好的你",
						Description: "bllii 动漫番剧在线播放与聚合平台",
					},
				})
				if err == nil {
					return
				}
			}

			// (B) 详情页：/anime/:id
			if strings.HasPrefix(cleanPath, "/anime/") {
				idStr := strings.Trim(strings.TrimPrefix(cleanPath, "/anime/"), "/")
				if id, _ := strconv.Atoi(idStr); id > 0 {
					video, err := dbStore.GetVideoByID(ctx, id)
					if err == nil && video != nil {
						video.FillCompatFields()
						related, _ := dbStore.GetHotVideos(ctx, 4, 10)
						if len(related) == 0 {
							related, _ = dbStore.GetHotVideos(ctx, 0, 10)
						}
						for i := range related {
							related[i].FillCompatFields()
						}
						// Wiki 词条与相关资讯首屏注水：与 /api/video 聚合逻辑一致，
						// 先按绑定反查，再按片名回填绑定，保证详情页直出演职员与资讯。
						var wikiDetail *store.WikiSubjectDetail
						var relatedNews []store.Content
						if sub := resolveVideoWikiSubject(ctx, dbStore, video); sub != nil {
							if d, err := dbStore.GetWikiSubjectByID(ctx, sub.ID); err == nil {
								wikiDetail = d
							}
							if news, _, err := dbStore.ListContent(ctx, store.ContentQuery{
								Kind: "news", Status: "published", SubjectID: sub.ID, PageSize: 6,
							}); err == nil {
								relatedNews = news
							}
						}
						pageProps := map[string]any{
							"path":        cleanPath,
							"id":          strconv.Itoa(id),
							"title":       video.Name + " 在线播放与全集选集 — bllii",
							"description": video.Name + " 在线观看",
							"detail": map[string]any{
								"video":        video,
								"related":      related,
								"wiki":         wikiDetail,
								"related_news": relatedNews,
							},
						}
						err = eng.Render(w, r, webfront.Page{
							URL:   cleanPath,
							Props: pageProps,
							Head: webfront.Head{
								Title:       video.Name + " 在线播放与全集选集 — bllii",
								Description: video.Name + " 在线观看",
							},
						})
						if err == nil {
							return
						}
					}
				}
			}

			// (C) 播放页：/play/:id 或 /play
			if strings.HasPrefix(cleanPath, "/play/") || cleanPath == "/play" {
				idStr := strings.Trim(strings.TrimPrefix(cleanPath, "/play/"), "/")
				if idStr == "" || cleanPath == "/play" {
					idStr = r.URL.Query().Get("id")
				}
				id, _ := strconv.Atoi(idStr)
				if id <= 0 {
					animes, _ := dbStore.GetHotVideos(ctx, 4, 1)
					if len(animes) > 0 {
						id = animes[0].ID
					} else {
						id = 317
					}
				}
				if id > 0 {
					video, err := dbStore.GetVideoByID(ctx, id)
					if err == nil && video != nil {
						video.FillCompatFields()
						related, _ := dbStore.GetHotVideos(ctx, 4, 10)
						if len(related) == 0 {
							related, _ = dbStore.GetHotVideos(ctx, 0, 10)
						}
						pageProps := map[string]any{
							"path":        cleanPath,
							"id":          strconv.Itoa(id),
							"title":       "正在播放：" + video.Name + " - bllii 放映室",
							"description": video.Name + " 在线全集播放",
							"video":       video,
							"related":     related,
						}
						err = eng.Render(w, r, webfront.Page{
							URL:   cleanPath,
							Props: pageProps,
							Head: webfront.Head{
								Title:       "正在播放：" + video.Name + " - bllii 放映室",
								Description: video.Name + " 在线全集播放",
							},
						})
						if err == nil {
							return
						}
					}
				}
			}

			// (D) 番剧库分类页：/category
			if cleanPath == "/category" {
				animes, _ := dbStore.GetHotVideos(ctx, 4, 24)
				if len(animes) < 6 {
					allHot, _ := dbStore.GetHotVideos(ctx, 0, 24)
					animes = append(animes, allHot...)
				}
				for i := range animes {
					animes[i].FillCompatFields()
				}
				pageProps := map[string]any{
					"path":          "/category",
					"title":         "番剧库 - bllii 分类索引",
					"description":   "bllii 番剧库分类索引与多维检索",
					"initialVideos": animes,
					"initialTotal":  len(animes),
				}
				err := eng.Render(w, r, webfront.Page{
					URL:   "/category",
					Props: pageProps,
					Head: webfront.Head{
						Title:       "番剧库 - bllii 分类索引",
						Description: "bllii 番剧库分类索引与多维检索",
					},
				})
				if err == nil {
					return
				}
			}

			// (E) 排行榜：/rank
			if cleanPath == "/rank" {
				animes, _ := dbStore.GetHotVideos(ctx, 4, 20)
				if len(animes) < 5 {
					allHot, _ := dbStore.GetHotVideos(ctx, 0, 20)
					animes = append(animes, allHot...)
				}
				for i := range animes {
					animes[i].FillCompatFields()
				}
				pageProps := map[string]any{
					"path":        "/rank",
					"title":       "人气排行榜 — bllii",
					"description": "bllii 人气动漫番剧排行榜",
					"initialTop":  animes,
				}
				err := eng.Render(w, r, webfront.Page{
					URL:   "/rank",
					Props: pageProps,
					Head: webfront.Head{
						Title:       "人气排行榜 — bllii",
						Description: "bllii 人气动漫番剧排行榜",
					},
				})
				if err == nil {
					return
				}
			}

			// (F) 时间表：/latest 或 /timeline
			if cleanPath == "/latest" || cleanPath == "/timeline" {
				animes, _ := dbStore.GetHotVideos(ctx, 4, 30)
				if len(animes) < 6 {
					allHot, _ := dbStore.GetHotVideos(ctx, 0, 30)
					animes = append(animes, allHot...)
				}
				for i := range animes {
					animes[i].FillCompatFields()
				}
				n := len(animes)
				tEnd := min(8, n)
				yEnd := min(16, n)
				today := animes[:tEnd]
				yesterday := animes[tEnd:yEnd]
				earlier := animes[yEnd:]
				pageProps := map[string]any{
					"path":        "/latest",
					"title":       "新番更新 — bllii",
					"description": "bllii 新番更新时间表",
					"initialData": map[string]any{
						"today":     today,
						"yesterday": yesterday,
						"earlier":   earlier,
					},
				}
				err := eng.Render(w, r, webfront.Page{
					URL:   "/latest",
					Props: pageProps,
					Head: webfront.Head{
						Title:       "新番更新 — bllii",
						Description: "bllii 新番更新时间表",
					},
				})
				if err == nil {
					return
				}
			}
		}

		// 4. 其他路由请求由 webfront 引擎标准渲染 (SSR / 预渲染 / SPA 回退)。
		//    SSR 渲染抛错时显式降级为 SPA 外壳，避免空 body 的 200。
		page := webfront.Page{
			URL:   cleanPath,
			Props: map[string]any{"path": cleanPath, "title": "bllii — 在更多的故事里，遇见更好的你"},
			Head: webfront.Head{
				Title:       "bllii — 在更多的故事里，遇见更好的你",
				Description: "bllii 动漫番剧在线播放与聚合平台",
			},
		}
		if err := eng.Render(w, r, page); err != nil {
			fmt.Printf("[portal] SSR 渲染失败 (%s)：%v，回退 SPA 外壳\n", cleanPath, err)
			if shell, err := sub.Open("index.html"); err == nil {
				defer shell.Close()
				w.Header().Set("Content-Type", "text/html; charset=utf-8")
				w.Header().Set("Cache-Control", "no-cache")
				w.WriteHeader(http.StatusOK)
				_, _ = io.Copy(w, shell)
				return
			}
			http.Error(w, "portal render failed", http.StatusInternalServerError)
		}
	})
}
