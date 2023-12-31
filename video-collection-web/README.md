# Bllii - 客户端影视门户 (Astro 版)

本项目基于 **Astro 5 + Tailwind CSS**，高精度复刻了 Bllii 现代化二次元番剧客户端视觉风格，并与 Go 后端聚合服务 `video-collection-api` 进行了深度接口打通。

---

## 🎨 页面与模块实现对比

| 模块 | 对应页面/组件 | 说明 |
| :--- | :--- | :--- |
| **顶部全局导航** | `src/components/Navbar.astro` | Bllii 标志、胶囊搜索框、导航项高亮、个人信息头像与通知 |
| **首页主视觉轮播** | `src/components/HeroBanner.astro` | “在更大的世界 遇见更好的自己”、立即观看按钮、轮播切换及光影氛围 |
| **金刚区快捷入口** | `src/components/QuickNav.astro` | 新番时间表、排行榜、专属合集、追番列表、我的收藏 5大彩色圆形入口 |
| **正在热播** | `src/components/CurrentlyAiring.astro` | 6列海报卡片网格，右上角“更新”角标，剧集进度提示 |
| **精选推荐** | `src/components/FeaturedRecommend.astro` | 4列宽屏横卡海报，展示类型与标签（如治愈/青春/游戏改） |
| **排行榜** | `src/components/Leaderboard.astro` | 热播排行，金银铜数字角标 |
| **番剧详情展台** | `src/components/AnimeHero.astro` | 沉浸式海报背板、元数据标签、立即播放与追番按钮 |
| **选集与播放器** | `src/components/EpisodeSelector.astro`<br>`src/components/PlayerModal.astro` | 01~12集方形按钮网格，点击即弹出无缝内置 HLS/MP4 视频播放器 |
| **剧情简介** | `src/components/Synopsis.astro` | 展开/折叠剧情简介 |

---

## 🚀 启动与运行指南

### 1. 安装依赖
```bash
# 在 video-collection-web 目录下执行：
pnpm install
# 或使用 npm:
npm install
```

### 2. 启动开发服务器
```bash
pnpm dev
# 或 npm run dev
```
启动后访问：
- 首页：`http://localhost:4321/`
- 番剧详情页：`http://localhost:4321/anime/1` 或 `http://localhost:4321/detail`

### 3. 构建生产版本
```bash
pnpm build
pnpm start:prod
# 等同于 node ./dist/server/entry.mjs
```

在 `video-collection-web` 目录执行，默认访问 `http://localhost:4321/`。`pnpm preview` 可用于本地预览构建结果。

项目使用 Astro `output: 'server'` 和 Node standalone 适配器，页面在请求时渲染。部署时必须保留完整的 `dist` 目录（包括 `dist/server` 和 `dist/client`）以及生产依赖；`dist/client` 提供 CSS、JavaScript、图片和播放器等静态资源。

可通过环境变量设置监听地址和端口：

```powershell
# Windows PowerShell
$env:HOST = '0.0.0.0'
$env:PORT = '4321'
node ./dist/server/entry.mjs
```

```bash
# Linux / macOS
HOST=0.0.0.0 PORT=4321 node ./dist/server/entry.mjs
```

服务端取数和生产 Node 服务的 `/api/*` 代理共用 `INTERNAL_API_URL`，默认是 `http://localhost:80`（未设置时也兼容运行时的完整 `PUBLIC_API_URL`）。浏览器的 `PUBLIC_API_URL` 建议留空，登录、评论等业务接口统一使用同源 `/api`。本地启动 Node 服务即可转发接口，无需额外配置 Nginx；后端 API 需单独启动。

播放器直接向视频源请求 M3U8，广告切片过滤在浏览器执行，过滤后的点播列表通过本地 Blob 提供给播放器。多码率、音轨、密钥、初始化片段和切片地址均在客户端解析，不经过播放列表代理。视频源需允许跨域读取；请求或解析失败时回退原始地址，直播使用原始列表维持刷新。切集和关闭播放器会释放本地列表。

例如后端监听 `8080` 时，在启动 Node 前设置 `$env:INTERNAL_API_URL = 'http://localhost:8080'`。直接执行 Node 不会自动加载 `.env.production`，服务端地址应通过启动环境变量传入；修改浏览器的 `PUBLIC_API_URL` 则需要重新构建。

如果启动后页面 404，先直接访问 Node 启动日志中的地址。旧的静态构建需要 `dist/client/index.html` 才能提供首页；更新配置后请重新执行 `pnpm build` 并部署完整 `dist`。若 Node 地址能访问而域名返回 404，请检查反向代理是否将页面请求转发到实际监听端口。

---

## 🔌 接口集成说明 (`src/lib/api.ts`)

项目在 `src/lib/api.ts` 中封装了对 `video-collection-api` 的所有数据接口调用：
- `GET /api/videos`：获取影片分页与分类列表（用于首页“正在热播”）
- `GET /api/rankings`：获取全站热度与番剧榜单（用于首页“排行榜”）
- `GET /api/video?id={id}`：获取影片详细信息、线路及多剧集播放链接
- `GET /api/categories`：获取系统分类树
- `POST /api/video/hit?id={id}`：视频播放量打点统计

> **容灾与体验优化**：若后端服务暂未启动或处于离线状态，客户端已内置高精度的回退数据集，保证页面样式、交互与所有视觉元素均 100% 完整呈现。
