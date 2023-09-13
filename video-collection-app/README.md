# Bllii - 二次元番剧聚合客户端 (Flutter 版)

本项目是基于 **Flutter 3 + Material 3** 打造的现代化二次元影视与番剧流媒体客户端，高精度对标与复刻 `video-collection-web` (Bllii) 的沉浸式视觉设计、配色体系与接口规范。

---

## 🎨 视觉与功能特性 (100% 对齐 Web 端)

| 核心模块 | Flutter 实现 | Web 端对应组件 | 特性说明 |
| :--- | :--- | :--- | :--- |
| **顶部品牌与搜索** | `SearchBarWidget` | `Navbar.astro` | Bllii 标志性蓝紫渐变徽标，胶囊搜索栏，即时关键词检索 |
| **主视觉轮播展台** | `HeroBannerWidget` | `HeroBanner.astro` | 16:9 沉浸海报大图、多维题材标签、评分角标、立即观看与一键追番 |
| **金刚区快捷入口** | `QuickNavWidget` | `QuickNav.astro` | 新番时刻、排行榜、全部分类、我的追番、观看历史 5大彩色渐变圆钮 |
| **正在热播** | `HomeScreen` + `AnimePosterCard` | `CurrentlyAiring.astro` | 3列海报卡片网格，右上角集数角标，底部渐变评分浮层 |
| **精选推荐** | `HomeScreen` 横滑推荐 | `FeaturedRecommend.astro` | 宽屏横向滑动卡片流，快速探索高质量番剧 |
| **排行榜单** | `RankScreen` + `LeaderboardCard` | `Leaderboard.astro` | 总热度榜/日漫榜/国漫榜切换，Top 1/2/3 金银铜牌专属徽章 |
| **新番时间表** | `TimelineScreen` | `timeline.astro` / `latest.astro` | 今日新番更新、昨日放送、更早连载状态时间线 |
| **多维筛选库** | `CategoryScreen` | `category.astro` | 分类类型（国漫/日漫/欧美）、题材、年份、排序组合过滤 |
| **番剧详情页** | `AnimeDetailScreen` | `AnimeHero.astro` + `detail.astro` | 沉浸式高斯模糊背景、剧情展开/收起、主演声优介绍、相关推荐 |
| **选集与播放器** | `PlayerScreen` + `EpisodeSelectorWidget` | `EpisodeSelector.astro` + 播放器 | 多线路切换、正反序排列、手势控制（快进/退10s）、全屏影院模式 |
| **个人追番档案** | `ProfileScreen` | `follow.astro` / 本地存储 | 本地持久化追番列表、观看足迹（记忆上次看至哪一集）、服务端动态配置 |

---

## 🔌 接口集成与容灾机制

1. **深度直连 Go 聚合后端 (`video-collection-api`)**：
   - 默认接入 `http://localhost:80`
   - 支持在「我的 -> API配置」中动态修改为局域网 IP（例如真机调试时的 `http://192.168.x.x:80`）并一键测试连通性。
2. **离线与断网容灾保障**：
   - 当后端服务未启动或网络环境受限时，客户端内置了高精度的离线番剧数据集（涵盖《葬送的芙莉莲》、《斗破苍穹》、《凡人修仙传》、《间谍过家家》、《鬼灭之刃》等），确保 App 任何情况下都能 100% 完整流畅预览与体验。

---

## 🚀 运行与构建指南

### 1. 运行 Windows 桌面端
```bash
cd video-collection-app
flutter run -d windows
```

### 2. 运行 Chrome / Edge 网页版
```bash
flutter run -d chrome
# 或
flutter run -d edge
```

### 3. 构建发布版本
```bash
# 构建 Windows 可执行程序
flutter build windows

# 构建 Web 发布包
flutter build web

# 构建 Android APK
flutter build apk
```
