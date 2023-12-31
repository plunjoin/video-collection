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
pnpm preview
```

---

## 🔌 接口集成说明 (`src/lib/api.ts`)

项目在 `src/lib/api.ts` 中封装了对 `video-collection-api` 的所有数据接口调用：
- `GET /api/videos`：获取影片分页与分类列表（用于首页“正在热播”）
- `GET /api/rankings`：获取全站热度与番剧榜单（用于首页“排行榜”）
- `GET /api/video?id={id}`：获取影片详细信息、线路及多剧集播放链接
- `GET /api/categories`：获取系统分类树
- `POST /api/video/hit?id={id}`：视频播放量打点统计

> **容灾与体验优化**：若后端服务暂未启动或处于离线状态，客户端已内置高精度的回退数据集，保证页面样式、交互与所有视觉元素均 100% 完整呈现。
