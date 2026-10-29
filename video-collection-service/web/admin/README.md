# bllii 管理后台（Vue 3 + Vite）

`video-collection-service/web/admin` 是管理后台的**纯前端工程**：Vue 3 + TypeScript + Vite 6 + Reka UI（Radix Vue）+ ECharts，构建产物经 `web/embed.go`（webui 包）以 `go:embed` 打进统一服务二进制，由 Go 直接托管 `/admin`（SPA history 路由，单二进制交付）。

> 本目录不含任何 Go 文件；Go 侧托管逻辑统一在 [`web/embed.go`](../embed.go)。

## 构建与开发

依赖统一由上一级 [web 工作区](../)管理（pnpm workspace，hoisted 单份 `web/node_modules`），本目录**不需要单独安装依赖**。

```bash
cd video-collection-service/web
pnpm install              # 首次或依赖变更时（整个工作区一次装齐）

# 生产构建（vue-tsc 类型检查 + vite 打包）
cd admin && pnpm build    # 产物：admin/dist

# 开发模式（热更新）
pnpm dev                  # 默认 3000 端口，/api 代理到 API_PROXY_TARGET（默认 http://localhost:8080）
```

改完前端后需要**重新编译 Go 二进制**才会进入生产形态（`go:embed` 是编译期烧入）。

## 主题（Bllii 品牌体系）

后台与门户共用 **Bllii** 视觉：蓝 `#4B9FFF`、紫 `#9A83FF`、粉 `#FF89C7`、深墨 `#353B58`。

- 设计令牌集中在 [`src/styles/index.scss`](src/styles/index.scss) 的 `:root`（亮色）与 `html.dark`（暗色）两段，页面样式一律引用令牌，不要在视图里写死颜色。
- 标志复用门户托管的品牌资产：`/brand/bllii-symbol.svg`（彩标）、`/brand/bllii-symbol-white.svg`（白标，侧栏渐变底）。注意模板中用 `:src` 绑定（字符串路径），不要写静态 `src="/brand/..."` —— Vite 会把绝对路径当模块解析导致构建失败。
- Favicon 同样指向 `/brand/bllii-symbol.svg`。

## 目录结构

```
admin/
├── dist/               # vite build 产物（go:embed 目标，勿手改）
├── src/
│   ├── api/            # 接口封装（axios）
│   ├── components/     # 通用组件
│   ├── layout/         # 侧栏 / 顶栏工作台壳
│   ├── router/         # vue-router 路由
│   ├── store/          # pinia 状态
│   ├── styles/         # index.scss 设计令牌 + radix-base.css
│   ├── utils/          # 工具函数
│   └── views/          # 页面（登录、仪表盘、资源库、业务配置...）
├── index.html
├── vite.config.ts
└── package.json        # 工作区成员清单（vue / pinia / echarts / vite ...）
```
