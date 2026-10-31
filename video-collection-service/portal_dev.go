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
	"encoding/json"
	"fmt"
	"regexp"
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
	"github.com/plunjoin/webfront/dev"

	"video-collection-service/pkg/store"
)

const portalRoot = "web/portal"

func newPortalHandler(_ store.Store) http.Handler {
	absRoot, err := filepath.Abs(portalRoot)
	if err != nil {
		panic("portaldev: 解析 portal 根目录失败: " + err.Error())
	}
	ds, err := dev.NewDevServer(portalRoot)
	if err != nil {
		panic("portaldev: webfront DevServer 初始化失败: " + err.Error())
	}
	devMux := ds.Handler()
	// 依赖目录：优先 web/wf_modules 版本化 store（wf install 产物，位于 portal 上级），
	// 回退 node_modules。StorePlugins 按"相对 rootDir 或绝对路径"解析，这里给绝对路径。
	modulesDir := "node_modules"
	if _, err := os.Stat(filepath.Join(absRoot, "wf_modules", ".store", "manifest.json")); err == nil {
		modulesDir = "wf_modules"
	} else if _, err := os.Stat(filepath.Join(absRoot, "..", "wf_modules", ".store", "manifest.json")); err == nil {
		modulesDir = filepath.Join(absRoot, "..", "wf_modules")
	}
	deps := &depShimmer{root: absRoot, modulesDir: modulesDir, external: []string{"react"}, raws: map[string][]byte{}, shims: map[string]string{}}

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
		// 读文件；先解析出真实存在的文件再放行，避免浏览器 404。精确路径命中
		// 目录时不放行（ReadFile 会失败），继续解析（含目录的 index.*）。
		if rel := strings.TrimPrefix(cleanPath, "/src/"); rel != cleanPath && rel != "" && !strings.HasSuffix(rel, "/") {
			needResolve := true
			if st, err := os.Stat(filepath.Join(portalRoot, "src", filepath.FromSlash(rel))); err == nil && !st.IsDir() {
				needResolve = false
			}
			if needResolve {
				candidates := []string{".tsx", ".ts", ".jsx", ".js", ".mjs", ".css", ".vue"}
				for _, idx := range []string{"index.tsx", "index.ts", "index.js", "index.vue"} {
					candidates = append(candidates, "/"+idx)
				}
				for _, ext := range candidates {
					candidate := rel + ext
					if st, err := os.Stat(filepath.Join(portalRoot, "src", filepath.FromSlash(candidate))); err == nil && !st.IsDir() {
						r.URL.Path = "/src/" + candidate
						break
					}
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
// base 是挂载前缀（门户为 ""，/admin 下为 "/admin"）：shim 与注入脚本的
// /@raw、/@deps 引用必须带上它，否则子路径挂载时会串到根路径的服务。
// external 是必须保持单例的包（门户 react、admin vue）：这些包若被打进
// 各依赖的 bundle，页面里会出现多份框架运行时，provide/inject 与响应式
// 实例全部断裂；外置后由 importmap 解析到同一份 shim。
type depShimmer struct {
	root       string
	modulesDir string
	base       string
	external   []string
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

// devDefine 依赖打包的编译期替换：NODE_ENV 之外补 Vue 特性标志——@vue/runtime-core
// 产物以裸全局引用它们，webfront 的 wf build 走 src/bootstrap.ts 运行期注入，
// dev 打包进浏览器前就必须内联，否则 goja 枚举导出与浏览器执行都会 ReferenceError。
var devDefine = map[string]string{
	"process.env.NODE_ENV":                       "\"development\"",
	"__VUE_OPTIONS_API__":                        "true",
	"__VUE_PROD_DEVTOOLS__":                      "false",
	"__VUE_PROD_HYDRATION_MISMATCH_DETAILS__":    "false",
}

func (d *depShimmer) build(spec string) ([]byte, string, error) {
	// 依赖包的 CSS 子路径（如 nprogress/nprogress.css）：不能按 JS 打包（CSS 文本
	// 会被浏览器当 JS 语法报错），转为"导入即注入 <style>"的 ESM 模块。
	if strings.HasSuffix(spec, ".css") {
		code, err := d.buildCss(spec)
		if err != nil {
			return nil, "", err
		}
		return []byte(code), code, nil
	}

	// 先打成 CJS：ESM 打包会把 CJS 依赖的具名导出压扁成 export default，
	// 无法事后恢复；CJS bundle 在运行期 module.exports 上保有完整导出面。
	cjsRes := api.Build(api.BuildOptions{
		EntryPoints:   []string{spec},
		Bundle:        true,
		Format:        api.FormatCommonJS,
		Platform:      api.PlatformBrowser,
		AbsWorkingDir: d.root,
		Plugins:       compiler.StorePlugins(d.root, d.modulesDir),
		Define:        devDefine,
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
		Plugins:       append([]api.Plugin{externalizePlugin(spec, d.external)}, compiler.StorePlugins(d.root, d.modulesDir)...),
		Define:        devDefine,
		Write:         false,
	})
	if len(esmRes.Errors) > 0 {
		return nil, "", fmt.Errorf("esm bundle: %+v", esmRes.Errors)
	}
	raw := esmRes.OutputFiles[0].Contents

	// 外置的共享包在产物里若是运行期 __require(...)（CJS 互操作残留），浏览器没有
	// require；按 external 列表注入路由到各自 shim 的 require。纯 ESM 依赖没有
	// __require 残留，不注入（避免强拉不需要的包）。
	if !d.isSelf(spec) && len(d.external) > 0 && hasExternalRequireCall(raw) {
		raw = append([]byte(d.requireShim(spec)), raw...)
	}

	shim := renderShim(d.base+"/@raw/"+spec, names)
	if err != nil {
		// 枚举失败时降级为纯 default 导出（保持可用，具名导入再单独暴露问题）
		fmt.Printf("[portaldev] warn: 枚举 %s 导出名失败，降级 default-only: %v\n", spec, err)
	}
	return raw, shim, nil
}

// buildCss 从版本化 store 里读依赖包的 CSS 文件并转为注入模块。
func (d *depShimmer) buildCss(spec string) (string, error) {
	var pkg, sub string
	if strings.HasPrefix(spec, "@") {
		parts := strings.SplitN(spec, "/", 3)
		pkg, sub = parts[0]+"/"+parts[1], strings.Join(parts[2:], "/")
	} else {
		parts := strings.SplitN(spec, "/", 2)
		pkg, sub = parts[0], strings.Join(parts[1:], "/")
	}
	dir := compiler.StorePackageDir(d.root, d.modulesDir, pkg)
	if dir == "" {
		return "", fmt.Errorf("package %s not in store manifest", pkg)
	}
	b, err := os.ReadFile(filepath.Join(dir, filepath.FromSlash(sub)))
	if err != nil {
		return "", err
	}
	res := api.Transform(string(b), api.TransformOptions{Loader: api.LoaderCSS})
	if len(res.Errors) > 0 {
		return "", fmt.Errorf("%+v", res.Errors)
	}
	cssJSON, _ := json.Marshal(string(res.Code))
	return "const s=document.createElement('style');s.textContent=" + string(cssJSON) + ";document.head.appendChild(s);export default s.textContent;", nil
}

// isSelf 报告 spec 是否就是某个单例包自身（自身构建时不外置、不注入 require）。
func (d *depShimmer) isSelf(spec string) bool {
	for _, p := range d.external {
		if spec == p || strings.HasPrefix(spec, p+"/") {
			return true
		}
	}
	return false
}

// requireShim 生成把 __require("<pkg>") 路由到对应 shim 命名空间的注入脚本。
func (d *depShimmer) requireShim(spec string) string {
	var b strings.Builder
	for _, p := range d.external {
		if spec == p || strings.HasPrefix(spec, p+"/") {
			continue
		}
		fmt.Fprintf(&b, `import * as __wf_ext_%s from "%s/@deps/%s.js";`+"\n", jsIdent(p), d.base, p)
	}
	b.WriteString("const require = (x) => {\n")
	for _, p := range d.external {
		if spec == p || strings.HasPrefix(spec, p+"/") {
			continue
		}
		fmt.Fprintf(&b, "  if (x === %q || x.startsWith(%q)) return __wf_ext_%s;\n", p, p+"/", jsIdent(p))
	}
	b.WriteString("  throw new Error(\"portaldev: unsupported external require: \" + x);\n};\n")
	return b.String()
}

// hasExternalRequireCall 检测产物里是否有真正的外置 require 调用（带实参），
// esbuild 的 __commonJS 帮助函数本身叫 function __require()，不能误判。
var externalRequireCallRe = regexp.MustCompile(`__require\d*\("[^"]*"\)`)

func hasExternalRequireCall(raw []byte) bool {
	return externalRequireCallRe.Match(raw)
}

// jsIdent 把包名转成安全的 JS 标识符（@lucide/vue → lucide_vue）。
func jsIdent(pkg string) string {
	r := strings.NewReplacer("@", "", "/", "_", "-", "_", ".", "_")
	return r.Replace(pkg)
}

// externalizePlugin 把 external 列表中的包（及子路径）标记为 external，由
// importmap 解析到单例 shim；构建这些包自身时不外置。返回空结果即放弃处理，
// 交给后续插件解析。
func externalizePlugin(spec string, external []string) api.Plugin {
	return api.Plugin{
		Name: "portaldev-externalize-singletons",
		Setup: func(build api.PluginBuild) {
			for _, p := range external {
				pkg := p
				build.OnResolve(api.OnResolveOptions{Filter: "^" + regexp.QuoteMeta(pkg) + "(/.*)?$"},
					func(args api.OnResolveArgs) (api.OnResolveResult, error) {
						if (args.Path == pkg || strings.HasPrefix(args.Path, pkg+"/")) && !isSelfSpec(spec, pkg) {
							return api.OnResolveResult{External: true}, nil
						}
						return api.OnResolveResult{}, nil
					})
			}
		},
	}
}

func isSelfSpec(spec, pkg string) bool {
	return spec == pkg || strings.HasPrefix(spec, pkg+"/")
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

// renderShim 生成具名导出 shim。shim 挂在 /@deps/<spec>.js，import 它的模块
// 可能是 import D from（default）也可能是 import { named } from：
//   - CJS 依赖：esbuild 的 ESM 产物只有 export default module.exports；
//   - 原生 ESM 依赖（vue、@lucide/vue 等）：只有具名导出，没有 default。
// 命名空间合并后两种形态都能取到具名导出，default 按存在与否回退。
func renderShim(rawURL string, names []string) string {
	var b strings.Builder
	b.WriteString(`import * as __wf_ns from "` + rawURL + `";` + "\n")
	b.WriteString(`const __wf_default = __wf_ns.default !== undefined ? __wf_ns.default : __wf_ns;` + "\n")
	b.WriteString(`const __wf_exp = Object.assign({}, __wf_ns, (__wf_ns.default !== undefined && (__wf_ns.default instanceof Object)) ? __wf_ns.default : {});` + "\n")
	b.WriteString(`export default __wf_default;` + "\n")
	for _, n := range names {
		if n == "__esModule" || n == "default" || !isIdent(n) {
			continue
		}
		b.WriteString("export const " + n + ` = __wf_exp[` + strconv.Quote(n) + `];` + "\n")
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
