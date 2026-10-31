//go:build dev

// 管理后台 dev 接线：go run -tags dev . 时 /admin 也挂 webfront DevServer（HMR），
// 与门户同一进程同一端口。生产构建（无 dev tag）走 admin_prod.go 的内嵌产物。
//
// 上游 dev 包生成的 HTML 与广播用的是根绝对路径（/src/...、/@deps/...、/__wf_hmr），
// 挂到 /admin 子路径下需要两个方向的适配：
//   - 入向：StripPrefix 后按根路径形式路由到 devMux / depShimmer；
//   - 出向：HTML 响应把上述路径统一改写为 /admin 前缀（含客户端 import(m.path)
//     的前缀注入，广播的 path 本身仍是根相对形式）。
package main

import (
	"bufio"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/evanw/esbuild/pkg/api"
	"github.com/plunjoin/webfront/compiler"
	"github.com/plunjoin/webfront/dev"
)

const adminRoot = "web/admin"

// devAdminBase 管理后台 dev 挂载前缀；HTML 改写与入向剥离都依赖它。
const devAdminBase = "/admin"

func newAdminHandler() http.Handler {
	absRoot, err := filepath.Abs(adminRoot)
	if err != nil {
		panic("admindev: 解析 admin 根目录失败: " + err.Error())
	}
	ds, err := dev.NewDevServer(adminRoot)
	if err != nil {
		panic("admindev: webfront DevServer 初始化失败: " + err.Error())
	}
	devMux := ds.Handler()

	// 依赖 store：与门户共享 web/wf_modules（位于 admin 上级），回退 node_modules。
	modulesDir := "node_modules"
	if _, err := os.Stat(filepath.Join(absRoot, "wf_modules", ".store", "manifest.json")); err == nil {
		modulesDir = "wf_modules"
	} else if _, err := os.Stat(filepath.Join(absRoot, "..", "wf_modules", ".store", "manifest.json")); err == nil {
		modulesDir = filepath.Join(absRoot, "..", "wf_modules")
	}
	deps := &depShimmer{root: absRoot, modulesDir: modulesDir, base: devAdminBase, external: []string{"vue"}, raws: map[string][]byte{}, shims: map[string]string{}}

	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := path.Clean("/" + r.URL.Path)
		switch {
		case strings.HasPrefix(p, "/@deps/"):
			deps.serve(w, r, false)
			return
		case strings.HasPrefix(p, "/@raw/"):
			deps.serve(w, r, true)
			return
		}

		// .vue 编译需要读 @vue/compiler-sfc（版本化 store）：上游 dev 包的内部
		// modulesDir 只在工程根下探测，admin 的 store 在上级 web/wf_modules，
		// 这里用正确路径接管 .vue，其余类型（纯 esbuild 转译，不碰依赖）仍走上游。
		if strings.HasPrefix(p, "/src/") && strings.HasSuffix(p, ".vue") {
			serveAdminVue(w, absRoot, modulesDir, strings.TrimPrefix(p, "/src/"))
			return
		}

		// 源码是无扩展名相对导入（'./App'、'./router'、'../api/request'），serveSrc
		// 按精确路径读文件；先解析出真实存在的文件（含目录的 index.*）再放行，
		// 避免浏览器 404。精确路径命中目录时不放行（ReadFile 会失败），继续解析。
		if rel := strings.TrimPrefix(p, "/src/"); rel != "" && !strings.HasSuffix(rel, "/") {
			needResolve := true
			if st, err := os.Stat(filepath.Join(absRoot, "src", filepath.FromSlash(rel))); err == nil && !st.IsDir() {
				needResolve = false
			}
			if needResolve {
				candidates := []string{".ts", ".tsx", ".vue", ".js", ".jsx", ".mjs", ".css"}
				for _, idx := range []string{"index.ts", "index.tsx", "index.vue", "index.js"} {
					candidates = append(candidates, "/"+idx)
				}
				for _, ext := range candidates {
					cand := rel + ext
					if st, err := os.Stat(filepath.Join(absRoot, "src", filepath.FromSlash(cand))); err == nil && !st.IsDir() {
						r.URL.Path = "/src/" + cand
						break
					}
				}
			}
		}
		devMux.ServeHTTP(w, r)
	})

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r2 := r.Clone(r.Context())
		r2.URL.Path = strings.TrimPrefix(path.Clean("/"+r.URL.Path), devAdminBase)
		if r2.URL.Path == "" {
			r2.URL.Path = "/"
		}
		inner.ServeHTTP(&basePrefixWriter{ResponseWriter: w, base: devAdminBase}, r2)
	})
}

// serveAdminVue 编译单个 admin SFC（与上游 dev serveSrc 的 .vue 分支同构，
// 区别只在 modulesDir 指向 web/wf_modules 版本化 store）。
func serveAdminVue(w http.ResponseWriter, rootDir, modulesDir, rel string) {
	full := filepath.Join(rootDir, "src", filepath.FromSlash(rel))
	src, err := os.ReadFile(full)
	if err != nil {
		http.Error(w, "not found: "+rel, 404)
		return
	}
	res, err := compiler.CompileSFCResult(rootDir, modulesDir, string(src), full)
	if err != nil {
		http.Error(w, fmt.Sprintf("vue compile error: %v", err), http.StatusInternalServerError)
		return
	}
	tr := api.Transform(res.Code, api.TransformOptions{
		Loader:     compiler.SFCLoader(res.Lang),
		Format:     api.FormatESModule,
		Sourcefile: rel,
		Define:     devDefine,
	})
	if len(tr.Errors) > 0 {
		http.Error(w, fmt.Sprintf("vue ts transform error: %+v", tr.Errors), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/javascript; charset=utf-8")
	_, _ = w.Write(tr.Code)
}

// basePrefixWriter 把上游 dev 包产出的 HTML 中的根绝对路径改写为 /admin 前缀。
// 仅拦截 text/html 响应（dev 壳页面，单次 Write）；JS/CSS 的相对导入由浏览器
// 按模块 URL 上下文解析，无需处理。透传 Hijacker/Flusher 以兼容 WebSocket 升级。
type basePrefixWriter struct {
	http.ResponseWriter
	base string
}

func (b *basePrefixWriter) Write(p []byte) (int, error) {
	if strings.HasPrefix(b.Header().Get("Content-Type"), "text/html") {
		s := string(p)
		// 路径别名：admin 源码大量使用 @/（tsconfig paths），dev 下没有构建期
		// 别名解析，借 importmap 的前缀匹配把 @/ 指到 /admin/src/（后续无扩展名
		// 导入由入向的候选文件解析兜底）。
		s = strings.ReplaceAll(s, `"imports": {`,
			"\"imports\": {\n    \"@/\": \""+b.base+"/src/\",")
		s = strings.ReplaceAll(s, `"/@deps/`, `"`+b.base+`/@deps/`)
		s = strings.ReplaceAll(s, `"/@raw/`, `"`+b.base+`/@raw/`)
		s = strings.ReplaceAll(s, `"/src/`, `"`+b.base+`/src/`)
		s = strings.ReplaceAll(s, `'ws://' + location.host + '/__wf_hmr'`, `'ws://' + location.host + '`+b.base+`/__wf_hmr'`)
		// 广播的 m.path 是根相对形式（/src/...），客户端 import 前补挂载前缀
		s = strings.ReplaceAll(s, `import(m.path + '?t='`, `import(`+strconv.Quote(b.base)+` + m.path + '?t='`)
		p = []byte(s)
	}
	return b.ResponseWriter.Write(p)
}

// Hijack 透传给底层 ResponseWriter：/__wf_hmr 的 WebSocket 升级需要。
func (b *basePrefixWriter) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	h, ok := b.ResponseWriter.(http.Hijacker)
	if !ok {
		return nil, nil, errors.New("admindev: 底层 ResponseWriter 不支持 Hijack")
	}
	return h.Hijack()
}

func (b *basePrefixWriter) Flush() {
	if f, ok := b.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}
