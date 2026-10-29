//go:build dev

// 开发态接线：go run -tags dev . 启用 webfront DevServer（esbuild 按需转译 + HMR）。
// 仅 dev 构建引入 esbuild/fsnotify/websocket/goja，默认生产构建不含这些依赖。
//
// 相对 dev.ServeDeps 的增强：esbuild 把 CJS 依赖打成 ESM 时只产出 export default，
// 浏览器对具名导入（import { useState } from 'react'）的静态绑定会直接报错。
// 这里用 goja 实际执行一遍依赖产物、枚举真实导出名，生成具名导出 shim
// （/@deps/<pkg>.js → shim，/@raw/<pkg> → 原始 ESM bundle）。
package main

import (
	"fmt"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"unicode"

	"github.com/dop251/goja"
	"github.com/evanw/esbuild/pkg/api"

	"github.com/plunjoin/webfront/compiler"

	"video-collection-service/pkg/devserver"
	"video-collection-service/pkg/store"
)

const portalRoot = "web/portal"

func newPortalHandler(_ store.Store) http.Handler {
	absRoot, err := filepath.Abs(portalRoot)
	if err != nil {
		panic("portaldev: 解析 portal 根目录失败: " + err.Error())
	}
	ds, err := devserver.NewDevServer(portalRoot)
	if err != nil {
		panic("portaldev: webfront DevServer 初始化失败: " + err.Error())
	}
	devMux := ds.Handler()
	deps := &depShimmer{root: absRoot, modulesDir: "node_modules", raws: map[string][]byte{}, shims: map[string]string{}}

	// dist 之外的落盘静态资源（brand/icons/players/js/manifest 等）在 dev 下直接取 public/
	const pubDir = portalRoot + "/public"
	pubFS := http.FileServer(http.Dir(pubDir))

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cleanPath := path.Clean("/" + r.URL.Path)

		if rel := strings.TrimPrefix(cleanPath, "/"); rel != "" {
			if st, err := os.Stat(filepath.Join(pubDir, filepath.FromSlash(rel))); err == nil && !st.IsDir() {
				pubFS.ServeHTTP(w, r)
				return
			}
		}

		// 源码是无扩展名相对导入（'./App'、'../lib/api'），dev.ServeSrc 按精确路径
		// 读文件；先解析出真实存在的文件再放行，避免浏览器 404。
		if rel := strings.TrimPrefix(cleanPath, "/src/"); rel != cleanPath && rel != "" && !strings.HasSuffix(rel, "/") {
			for _, ext := range []string{"", ".tsx", ".ts", ".jsx", ".js", ".mjs", ".css", ".vue"} {
				candidate := rel + ext
				if _, err := os.Stat(filepath.Join(portalRoot, "src", filepath.FromSlash(candidate))); err == nil {
					r.URL.Path = "/src/" + candidate
					break
				}
			}
		}

		// 依赖请求改走具名导出 shim（importmap 指向 /@deps/...）
		switch {
		case strings.HasPrefix(cleanPath, "/@deps/"):
			deps.serve(w, r, false)
		case strings.HasPrefix(cleanPath, "/@raw/"):
			deps.serve(w, r, true)
		default:
			devMux.ServeHTTP(w, r)
		}
	})
}

// depShimmer 按需构建依赖的 ESM bundle 并生成具名导出 shim，结果进程内缓存。
type depShimmer struct {
	root       string
	modulesDir string
	mu         sync.Mutex
	raws       map[string][]byte
	shims      map[string]string
}

func (d *depShimmer) serve(w http.ResponseWriter, r *http.Request, raw bool) {
	spec := strings.TrimPrefix(r.URL.Path, "/@deps/")
	if raw {
		spec = strings.TrimPrefix(r.URL.Path, "/@raw/")
	}
	spec = strings.TrimSuffix(spec, ".js")
	if spec == "" {
		http.Error(w, "missing dep specifier", http.StatusBadRequest)
		return
	}

	d.mu.Lock()
	rawBytes, okRaw := d.raws[spec]
	shim, okShim := d.shims[spec]
	if !okRaw || !okShim {
		d.mu.Unlock()
		var err error
		rawBytes, shim, err = d.build(spec)
		if err != nil {
			http.Error(w, "bundle dep "+spec+": "+err.Error(), http.StatusInternalServerError)
			return
		}
		d.mu.Lock()
		d.raws[spec] = rawBytes
		d.shims[spec] = shim
	}
	d.mu.Unlock()

	w.Header().Set("Content-Type", "application/javascript; charset=utf-8")
	if raw {
		_, _ = w.Write(rawBytes)
		return
	}
	_, _ = w.Write([]byte(shim))
}

func (d *depShimmer) build(spec string) ([]byte, string, error) {
	// 先打成 CJS：ESM 打包会把 CJS 依赖的具名导出压扁成 export default，
	// 无法事后恢复；CJS bundle 在运行期 module.exports 上保有完整导出面。
	cjsRes := api.Build(api.BuildOptions{
		EntryPoints:   []string{spec},
		Bundle:        true,
		Format:        api.FormatCommonJS,
		Platform:      api.PlatformBrowser,
		AbsWorkingDir: d.root,
		Plugins:       compiler.StorePlugins(d.root, d.modulesDir),
		Define:        map[string]string{"process.env.NODE_ENV": "\"development\""},
		Write:         false,
	})
	if len(cjsRes.Errors) > 0 {
		return nil, "", fmt.Errorf("%+v", cjsRes.Errors)
	}
	cjsCode := cjsRes.OutputFiles[0].Contents

	// goja 实际执行 CJS bundle，枚举真实导出名
	names, err := exportNames(cjsCode)

	// CJS -> ESM 作为浏览器加载的 raw bundle。
	// 共享依赖（react）必须外置走 importmap 复用同一实例，否则 react-dom 内嵌
	// 一份 React、页面组件再加载一份，运行期报 Invalid hook call。
	// 外置插件要放在 StoreResolver 之前，否则 react 先被解析成 store 文件路径，
	// External 列表就匹配不到了。
	esmRes := api.Build(api.BuildOptions{
		EntryPoints:   []string{spec},
		Bundle:        true,
		Format:        api.FormatESModule,
		Platform:      api.PlatformBrowser,
		AbsWorkingDir: d.root,
		Plugins:       append([]api.Plugin{externalizeReactPlugin(spec)}, compiler.StorePlugins(d.root, d.modulesDir)...),
		Define:        map[string]string{"process.env.NODE_ENV": "\"development\""},
		Write:         false,
	})
	if len(esmRes.Errors) > 0 {
		return nil, "", fmt.Errorf("esm bundle: %+v", esmRes.Errors)
	}
	raw := esmRes.OutputFiles[0].Contents

	// 外置的 react 在产物里是运行期 __require("react")，浏览器没有 require。
	// 在模块顶部注入浏览器版 require：react 请求转给 shim 命名空间（与页面组件
	// 同一实例，保证 hooks 可用）。
	if !(spec == "react" || strings.HasPrefix(spec, "react/")) {
		raw = append([]byte(browserRequireShim), raw...)
	}

	shim := renderShim("/@raw/"+spec, names)
	if err != nil {
		// 枚举失败时降级为纯 default 导出（保持可用，具名导入再单独暴露问题）
		fmt.Printf("[portaldev] warn: 枚举 %s 导出名失败，降级 default-only: %v\n", spec, err)
	}
	return raw, shim, nil
}

// browserRequireShim 注入到外置了 react 的 raw bundle 顶部：
// 把运行期 __require("react") 路由到 shim 模块命名空间。
const browserRequireShim = `import * as __wf_react from "/@deps/react.js";
const require = (x) => (x === "react" || x.startsWith("react/")
  ? __wf_react
  : (() => { throw new Error("portaldev: unsupported external require: " + x); })());
`

// externalizeReactPlugin 把 react（及子路径）标记为 external，供 importmap 解析；
// 构建 react 自身时不外置。返回空结果即放弃处理，交给后续插件解析。
func externalizeReactPlugin(spec string) api.Plugin {
	external := !(spec == "react" || strings.HasPrefix(spec, "react/"))
	return api.Plugin{
		Name: "portaldev-externalize-react",
		Setup: func(build api.PluginBuild) {
			build.OnResolve(api.OnResolveOptions{Filter: `^react(/.*)?$`},
				func(args api.OnResolveArgs) (api.OnResolveResult, error) {
					if external && (args.Path == "react" || strings.HasPrefix(args.Path, "react/")) {
						return api.OnResolveResult{External: true}, nil
					}
					return api.OnResolveResult{}, nil
				})
		},
	}
}

// exportNames 在 goja 里执行 CJS bundle，取 module.exports 的键。
func exportNames(cjsCode []byte) ([]string, error) {
	vm := goja.New()
	script := "(function(){ var module = { exports: {} }; var exports = module.exports;\n" +
		string(cjsCode) +
		"\n; return Object.getOwnPropertyNames(module.exports); })()"
	v, err := vm.RunString(script)
	if err != nil {
		return nil, err
	}
	var names []string
	if err := vm.ExportTo(v, &names); err != nil {
		return nil, err
	}
	return names, nil
}

func renderShim(rawURL string, names []string) string {
	var b strings.Builder
	b.WriteString(`import D from "` + rawURL + `";` + "\n")
	b.WriteString("export default D;\n")
	for _, n := range names {
		if n == "__esModule" || n == "default" || !isIdent(n) {
			continue
		}
		b.WriteString("export const " + n + ` = D[` + strconv.Quote(n) + `];` + "\n")
	}
	return b.String()
}

func isIdent(s string) bool {
	if s == "" {
		return false
	}
	for i, r := range s {
		if r == '_' || r == '$' || unicode.IsLetter(r) {
			continue
		}
		if i > 0 && unicode.IsDigit(r) {
			continue
		}
		return false
	}
	return true
}
