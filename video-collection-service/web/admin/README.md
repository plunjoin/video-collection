# bllii 管理后台（Vue 3 + webfront）

`video-collection-service/web/admin` 是管理后台的**纯前端工程**：Vue 3 + TypeScript + Reka UI（Radix Vue）+ ECharts，由 [webfront](https://github.com/plunjoin/webfront) 的 wf CLI 构建（esbuild 内核，纯 Go，零 Node 运行时），产物经 `web/embed.go`（webui 包）以 `go:embed` 打进统一服务二进制，由 Go 直接托管 `/admin`（SPA history 路由，单二进制交付）。

> 本目录不含任何 Go 文件；Go 侧托管逻辑统一在 [`web/embed.go`](../embed.go)。

## 构建与开发

依赖由 webfront 的版本化 store 管理（`web/wf_modules`，由 `web/package-lock.json` 锁定版本），本目录**不需要单独安装依赖**。前置条件只有一个：安装 Go 与 wf CLI。

```bash
# 0. 一次性安装 wf CLI（webfront 构建器）
go install github.com/plunjoin/webfront/cmd/wf@v0.1.0

# 1. 安装依赖（在 video-collection-service 根目录执行；首次或依赖变更时）
wf install -modules wf_modules .
```

- **开发模式（HMR）**：`go run -tags dev .` 时 `/admin` 也挂 webfront DevServer——改本目录源码保存即热更（与门户同一进程、同一端口），依赖共享 `web/wf_modules` store；dev 壳由 `src/main.ts` 直接从源码编译，无需构建。
- **生产构建**（esbuild：TS 转译 + Vue SFC 编译 + 分包）：

```bash
MSYS_NO_PATHCONV=1 wf build -mode spa -base /admin -modules ../wf_modules web/admin
# 产物：web/admin/dist（Git Bash 需 MSYS_NO_PATHCONV=1 防止 /admin 被路径转换；PowerShell/cmd 直接去掉该前缀）

# 打进服务二进制（go:embed 是编译期烧入，改完前端必须重新编译）
go build -o service.exe .
```

- **wf 约定**：构建入口 `src/entry-client.tsx`（先 `import './bootstrap'` 再 `import './main'`）；`src/bootstrap.ts` 负责注入 Vue 特性标志（`__VUE_OPTIONS_API__` 等，esbuild 不做 define 替换）与文档属性（wf 生成的 `index.html` 只含 `#root` 挂载点）；挂载点统一 `#root`。

改完前端后需要**重新编译 Go 二进制**才会进入生产形态（`go:embed` 是编译期烧入）。

## 主题（Bllii 品牌体系）

后台与门户共用 **Bllii** 视觉：蓝 `#4B9FFF`、紫 `#9A83FF`、粉 `#FF89C7`、深墨 `#353B58`。

- 设计令牌集中在 [`src/styles/index.css`](src/styles/index.css) 的 `:root`（亮色）与 `html.dark`（暗色）两段，页面样式一律引用令牌，不要在视图里写死颜色。
- 标志复用门户托管的品牌资产：`/brand/bllii-symbol.svg`（彩标）、`/brand/bllii-symbol-white.svg`（白标，侧栏渐变底）。模板中用 `:src` 绑定（字符串路径），不要写静态 `src="/brand/..."`，保持与门户一致的资产引用方式。
- Favicon 同样指向 `/brand/bllii-symbol.svg`（由 `src/bootstrap.ts` 注入 `<link rel="icon">`）。

## 目录结构

```
admin/
├── dist/               # wf build 产物（go:embed 目标，勿手改）
├── src/
│   ├── api/            # 接口封装（axios）
│   ├── components/     # 通用组件
│   ├── layout/         # 侧栏 / 顶栏工作台壳
│   ├── router/         # vue-router 路由（base 固定 /admin）
│   ├── store/          # pinia 状态
│   ├── styles/         # index.css 设计令牌 + radix-base.css
│   ├── utils/          # 工具函数
│   ├── views/          # 页面（登录、仪表盘、资源库、业务配置...）
│   ├── bootstrap.ts    # wf 构建引导：Vue 特性标志 + 文档属性（先于 main 执行）
│   ├── entry-client.tsx # wf 构建入口（bootstrap → main）
│   └── main.ts         # 应用装配（createApp + 挂载 #root）
├── package.json        # 依赖清单（wf install 按 web/package-lock.json 锁定版本）
└── tsconfig.json       # 编辑器 TS 支持（构建期转译由 esbuild 完成）
```
