// Package admin 通过 go:embed 内嵌管理后台 SPA 构建产物
// （video-collection-service/web/admin/dist），由 Go 服务直接托管 /admin，
// 无需额外 Nginx 容器，单二进制即可交付「API + 管理后台」。
//
// 约定：
//   - 前端构建：cd web/admin && pnpm build，输出至 web/admin/dist；
//   - SPA 采用 history 路由，未命中静态文件的 /admin/<route> 统一回退 index.html；
//   - dist 为空（未构建）时该包仍可编译（保留占位 index.html）。
package admin

import (
	"embed"
	"io/fs"
	"net/http"
	"path"
	"strings"
)

//go:embed all:dist
var files embed.FS

// Handler 返回管理后台 SPA 处理器。
// 行为：
//   - /admin、/admin/ 及任意 /admin/<route> 未命中静态文件时回退 index.html；
//   - 命中 /admin/assets/* 等静态资源时直接返回（长缓存）；
//   - index.html 不缓存，保证发布后即时生效。
func Handler() http.Handler {
	sub, err := fs.Sub(files, "dist")
	if err != nil {
		panic("adminembed: 读取内嵌 dist 失败: " + err.Error())
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
			} else if strings.HasPrefix(upath, "/assets/") {
				w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
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
