# bllii 用户门户（React + webfront）

`video-collection-service/web/portal` 是前台门户的**纯前端工程**：React 18 + TypeScript，由 [webfront](https://github.com/plunjoin/webfront) 的 wf CLI 构建，产物经 `web/embed.go`（webui 包）以 `go:embed` 打进统一服务二进制，由 Go 直接托管 `/`（SSR + SPA，单二进制零 Node 运行时）。

> 本目录不含任何 Go 文件；Go 侧托管逻辑统一在 [`web/embed.go`](../embed.go)。

## 页面与路由

| 路由 | 页面 | 说明 |
| :--- | :--- | :--- |
| `/` | `HomePage` | 首页：轮播、金刚区、热播、资讯、个性化推荐 |
| `/category` | `CategoryPage` | 番剧库分类索引 |
| `/latest`（`/timeline`） | `LatestPage` | 新番更新时间表 |
| `/rank` | `RankPage` | 人气排行榜 |
| `/anime/:id`（`/detail/:id`） | `AnimeDetailPage` | 详情展台、选集、简介 |
| `/play/:id`（`/play?id=`） | `PlayPage` | HLS/MP4 播放器、多线路 |
| `/follow` | `FollowPage` | 追番列表 |
| `/news`、`/news/:id` | `NewsPage` / `NewsDetailPage` | 资讯列表与详情（含评论） |
| `/community`、`/community/:id` | `CommunityPage` / `CommunityDetailPage` | 同好社区（发帖、点赞、评论） |
| `/notifications` | `NotificationsPage` | 站内消息通知 |
| `/points` | `PointsPage` | 同好成长站（签到、装扮、心愿、积分） |
| `/login` | `LoginPage` | 登录 / 注册 |
| `/search` | `SearchPage` | 搜索与自动补全 |
| `/movie` | — | 服务端 302 重定向到 `/category` |

Go 侧为首页、详情、播放、分类、排行、时间表注入首屏数据（SSR 注水）；其余页面在浏览器端通过同源 `/api/*` 取数。

## 构建与开发

依赖统一由上一级 [web 工作区](../)管理（pnpm workspace，hoisted 单份 `web/node_modules`），本目录**不需要单独安装依赖**。

```bash
# 从仓库根或 service 目录执行
cd video-collection-service/web
pnpm install            # 首次或依赖变更时

# 生产构建（esbuild：SSR bundle + 分包 client）
cd portal && ../../wf.exe build .     # Windows；macOS/Linux 用 wf
# 产物：portal/dist（ssr.js、assets/client.js、assets/chunks/*、index.html）

# 开发模式（免打包：esbuild 按需转译 + HMR）
cd video-collection-service
go run -tags dev .      # 门户挂 webfront DevServer，与 /api 同进程同源
```

改完前端后需要**重新编译 Go 二进制**才会进入生产形态（`go:embed` 是编译期烧入）；`go run .` 也会在编译时重新内嵌当前 dist。

## 品牌与静态资源

- `public/brand/`：标志与品牌资产，生产构建时整体拷贝进 dist，由服务托管 `/brand/*`（管理后台也复用这套资产）。
- `public/players/`：video.js 播放器皮肤与脚本。
- 品牌图标更新后执行 `node scripts/sync-brand.mjs`，同步 `bllii-brand-kit` 预览、本目录 brand 资源与两份播放器（Web / API）中的图标精灵。

## 目录结构

```
portal/
├── dist/               # wf build 产物（go:embed 目标，勿手改）
├── public/             # 原样拷贝的静态资源（brand / players / js / icons）
├── scripts/            # 品牌同步等构建辅助脚本
├── src/
│   ├── components/     # 业务组件（Comments、MemberIdentity 等）
│   ├── layouts/        # Layout（导航 + 页脚 + 全局壳）
│   ├── lib/            # 数据层：api / auth / comments / notifications / growth-station ...
│   ├── pages/          # 路由页面（App.tsx 手工路由表）
│   ├── styles/         # 样式（bundle.css 聚合 @import，供生产打包）
│   ├── App.tsx         # 路由表与 404 兜底
│   ├── entry-client.tsx # 生产水合入口（读取 __WF_DATA__）
│   ├── entry-server.tsx # SSR 渲染入口（render(url, props)）
│   └── main.tsx        # dev 专用入口（webfront DevServer 约定）
└── package.json        # 工作区成员清单（react / react-dom / scheduler）
```
