# Bllii - 二次元番剧聚合客户端 (Flutter 版)

本项目是基于 **Flutter 3 + Material 3** 打造的现代化二次元影视与番剧流媒体客户端，高精度对标与复刻 `video-collection-web` (Bllii) 的沉浸式视觉设计、配色体系与接口规范。

---

## 🎨 视觉与功能特性 (100% 对齐 Web 端)

| 核心模块 | Flutter 实现 | Web 端对应组件 | 特性说明 |
| :--- | :--- | :--- | :--- |
| **顶部品牌与搜索** | `SearchBarWidget` | `Navbar.astro` | Bllii 标志性蓝紫渐变徽标，胶囊搜索栏，即时关键词检索 |
| **主视觉轮播展台** | `HeroBannerWidget` | `HeroBanner.astro` | 16:9 沉浸海报大图、多维题材标签、立即观看与一键追番 |
| **金刚区快捷入口** | `QuickNavWidget` | `QuickNav.astro` | 新番时刻、排行榜、全部分类、我的追番、观看历史 5大彩色渐变圆钮 |
| **正在热播** | `HomeScreen` + `AnimePosterCard` | `CurrentlyAiring.astro` | 3列海报卡片网格，右上角集数角标 |
| **精选推荐** | `HomeScreen` 横滑推荐 | `FeaturedRecommend.astro` | 宽屏横向滑动卡片流，快速探索高质量番剧 |
| **排行榜单** | `RankScreen` + `LeaderboardCard` | `Leaderboard.astro` | 总热度榜/日漫榜/国漫榜切换，Top 1/2/3 金银铜牌专属徽章 |
| **新番时间表** | `TimelineScreen` | `timeline.astro` / `latest.astro` | 今日新番更新、昨日放送、更早连载状态时间线 |
| **多维筛选库** | `CategoryScreen` | `category.astro` | 分类类型（国漫/日漫/欧美）、题材、年份、排序组合过滤 |
| **番剧详情页** | `AnimeDetailScreen` | `AnimeHero.astro` + `detail.astro` | 沉浸式高斯模糊背景、剧情展开/收起、主演声优介绍、相关推荐 |
| **选集与播放器** | `PlayerScreen` + `EpisodeSelectorWidget` | `EpisodeSelector.astro` + 播放器 | 多线路切换、正反序排列、手势控制（快进/退10s）、全屏影院模式 |
| **个人追番档案** | `ProfileScreen` | `follow.astro` / 本地存储 | 本地持久化追番列表、观看足迹（记忆上次看至哪一集）、服务端动态配置 |

---

## 🔌 接口集成与容灾机制

播放器直连视频源，在客户端解析 M3U8 并过滤片头、中插、片尾及关键词命中的广告切片。多码率和音轨子列表递归处理，密钥与切片地址补全为源站绝对地址；原始隐式 IV 和字节偏移会显式保留。原生平台使用临时列表文件，Web 使用本地 Blob，切集和退出时释放。服务端不提供 M3U8 过滤或播放列表代理；过滤失败回退原始链接，直播保留原始列表刷新行为。Web 直连要求视频源允许跨域读取。

1. **深度直连 Go 聚合后端 (`video-collection-api`)**：
   - 默认接入 `http://localhost:80`
   - 支持在「我的 -> API配置」中动态修改为局域网 IP（例如真机调试时的 `http://192.168.x.x:80`）并一键测试连通性。
   - 所有内容均来自后端接口，客户端不内置任何演示数据；接口不可用时展示空状态。

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
