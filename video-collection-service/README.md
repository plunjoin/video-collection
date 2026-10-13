# video-collection-service — 统一服务（RESTful API + 管理后台）

由原 `video-collection-api` 与 `video-collection-admin` 合并而成的单体统一服务：

- **一个 Go 二进制同时交付两类能力**：对客户端/程序提供 RESTful JSON API，对运营提供管理后台；
- **管理后台由 Go 直接托管**：Vue3 管理后台构建产物通过 `go:embed` 打进二进制，服务在 `/admin` 直接提供 SPA（history 路由回退、静态资源长缓存），不再需要 Nginx 容器；
- **radix 重构缓存与会话层**：引入 [`mediocregopher/radix/v4`](https://github.com/mediocregopher/radix) Redis 客户端，登录会话与公开读接口缓存均可切换至 Redis；**未配置 Redis 时全链路自动降级**（内存会话 + 直连数据库），零依赖可用；
- **Gemini 风格管理界面**：侧边导航采用细栏图标 + 药丸选中态 + 底部个人信息卡的浅色简洁设计，交互组件采用 `reka-ui`（Radix Vue 的后继项目）无样式原语 + 本地 `r-*` 设计系统，已彻底移除 Element Plus。

```
浏览器 ──► /admin/* ──► Go 服务 ──► go:embed 内嵌 SPA (web/admin/dist)
客户端 ──► /api/*  ──► Go 服务 ──► PostgreSQL / SQLite
                       │
                       ├─► radix(Redis)：会话存储、公开读缓存（可选）
                       └─► 采集调度 / MacCMS / RSS / M3U8 清洗
```

## 目录结构

```
video-collection-service/
├── main.go                  # 统一入口：存储→radix→API→管理后台 SPA
├── config/                  # 采集规则与模板 YAML
├── pkg/
│   ├── api/                 # RESTful 接口（含缓存包装 serveCached/adminWrite）
│   ├── auth/                # 鉴权与会话（内存/Redis 双实现 SessionStore）
│   ├── cache/               # radix 封装：命名空间 + 代份失效模型
│   ├── ingest/ maccms/ m3u8cleaner/ rss/ scheduler/ store/ theme/ player/ openapi/
├── web/
│   └── admin/               # Vue3 管理后台（Gemini 风格）
│       ├── embed.go         # go:embed all:dist —— SPA 托管处理器
│       ├── src/             # 前端源码
│       └── dist/            # 构建产物（打入二进制）
├── players/ themes/ data/   # 运行时目录
├── Dockerfile               # node 构建前端 + go 构建服务的合并镜像
└── .env.example
```

## 快速开始

### 1. 构建管理后台（一次性，改动前端后重跑）

```bash
cd web/admin
pnpm install --frozen-lockfile
pnpm build          # 输出至 web/admin/dist
```

### 2. 编译并运行服务

```bash
cd ../..             # 回到 video-collection-service
go build -o video-collection-service .
./video-collection-service  # 默认 80 端口，PORT=8080 可改
```

| 入口 | 地址 |
| :--- | :--- |
| **根路径（默认）** | `http://localhost:8080/` → 自动跳转 `/admin` |
| **管理后台（Go 托管）** | `http://localhost:8080/admin` |
| 服务状态（程序访问） | `/status` |
| OpenAPI 交互文档 | `/docs` |
| OpenAPI 规范 JSON | `/openapi.json` |
| 视频检索 API | `/api/videos` |
| RSS 订阅 | `/rss.xml` |
| 健康检查 | `/healthz` |

前端开发模式（热更新）也可独立运行：`cd web/admin && pnpm dev`（默认 3000 端口，`/api` 代理到 `API_PROXY_TARGET`，默认 `http://localhost:8080`）。

## radix 重构说明

### 分布式会话（pkg/auth）

`SessionManager` 背后是 `SessionStore` 抽象：

- `MemorySessionStore`（默认）：进程内 map，零依赖；
- `RedisSessionStore`（设置 `REDIS_ADDR` 后启用）：会话以 JSON 存入 Redis 并带 TTL，**支持多副本部署与服务重启免登录**；Redis 故障时自动回退内存存储，不影响登录。

### 公开读缓存（pkg/cache）

采用**命名空间 + 代份（generation）**失效模型，避免 SCAN+DEL 大键扫描：

- 读：`GET vc:ns:<ns>:g<gen>:<key>`，未命中回源数据库后回写；
- 写：管理端写操作（保存/删除视频、采集、改配置等）后 `INCR vc:gen:<ns>`，该命名空间全部缓存立即失效，旧键由 TTL 自然回收；
- 覆盖命名空间与 TTL：视频列表/详情/分类/站点配置 120s，排行榜/最近更新 60s，播放器 120s；
- Redis 不可用时 `serveCached` 自动降级为直连数据库，行为与合并前完全一致。

### 环境变量

| 变量 | 说明 | 默认 |
| :--- | :--- | :--- |
| `PORT` | 监听端口 | `80` |
| `REDIS_ADDR` | Redis 地址，**不设置则禁用缓存与外置会话** | 空 |
| `REDIS_PASSWORD` | Redis 密码 | 空 |
| `REDIS_DB` | Redis 库索引 | `0` |
| `REDIS_PREFIX` | 键前缀（多套服务共用一个 Redis 时区分） | `vc` |
| `DB_DRIVER` / `DB_DSN` / `DB_HOST` … | 数据库配置（同原 API） | `postgres` |

## 部署

单容器即可运行「门户后端 + 管理后台」，见根目录 `compose.yaml` 与 [`deploy/README.md`](../deploy/README.md)：

```bash
docker compose --env-file deploy/.env up -d --build
# 门户      http://127.0.0.1:4321
# 管理后台  http://127.0.0.1:8080/admin
```

> 原 `video-collection-api`、`video-collection-admin` 已全量合并进本目录并删除，仓库中不再保留旧目录。

---

## 接口模块索引

管理端写操作会自动失效对应缓存；以下端点均可用 `/docs`（Swagger UI）在线调试，`/openapi.json` 可导入 Postman / Apifox。

| 模块 | 核心端点 | 描述 |
| :--- | :--- | :--- |
| **Auth** | `POST /api/login`<br>`POST /api/register`<br>`POST /api/logout`<br>`GET /api/me` | 用户登录、注册、注销与当前用户查询 |
| **Videos** | `GET /api/videos`<br>`GET /api/video`<br>`POST /api/video/hit`<br>`GET /api/rankings`<br>`GET /api/latest` | 视频列表检索、详情、播放热度累加、排行榜与最新更新（均已接入 Redis 读缓存） |
| **Categories** | `GET /api/categories` | 获取系统视频分类列表 |
| **User** | `GET/POST /api/user/history`<br>`POST /api/user/history/sync`<br>`GET /api/user/favorites` | 播放进度云端同步、历史记录管理与追剧收藏 |
| **Site** | `GET /api/site/config`<br>`POST /api/feedback` | 公开站点信息、用户求片与报错反馈提交 |
| **News** | `GET /api/news`<br>`GET/POST/DELETE /api/admin/news` | 资讯列表、详情、草稿、发布、分类、搜索与置顶 |
| **Comments** | `GET/POST/DELETE /api/comments`<br>`POST/DELETE /api/comments/likes`<br>`GET/DELETE /api/admin/comments` | 通用评论、多级回复、评论点赞、通知及管理；关联影视/资讯/社区，可扩展 |
| **Community** | `GET/POST/DELETE /api/community/posts`<br>`GET/POST/DELETE /api/community/comments`<br>`POST/DELETE /api/community/likes` | 发帖、评论、点赞；管理端 `/api/admin/community/*` |
| **Notifications** | `GET/DELETE /api/user/notifications`<br>`GET /api/user/notifications/unread-count`<br>`POST /api/user/notifications/read`<br>`POST /api/admin/notifications` | 互动通知、系统通知、未读统计、已读管理与定向/广播发送 |
| **Admin - Sources** | `GET/POST/DELETE /api/admin/sources`<br>`POST /api/admin/sources/test`<br>`POST /api/admin/sources/collect`<br>`POST /api/admin/sources/collect-all` | 采集源维护、连通性测试与手动采集任务触发 |
| **Admin - Videos** | `DELETE /api/admin/videos`<br>`POST /api/admin/videos/save`<br>`POST /api/admin/videos/batch-delete` | 视频编辑、单条删除与批量清理 |
| **Admin - Users** | `GET/POST/DELETE /api/admin/users` | 用户账号分页列表、权限分配与状态修改 |
| **Admin - Stats & Logs** | `GET /api/admin/stats`<br>`GET /api/admin/logs` | 系统仪表盘统计指标与操作审计日志流水 |
| **Analytics - 埋点** | `POST /api/track` | 轻量埋点上报（page_view / page_leave 停留时长 / rec_click / ad_click / search / favorite / play） |
| **Analytics - 搜索建议** | `GET /api/search/suggest` | 输入自动补全（作品名匹配）与真实搜索热词（近7天） |
| **Analytics - 个性化推荐** | `GET /api/recommend/for-you` | 基于播放历史与追剧收藏的类型亲和度加权推荐，需登录 |
| **Analytics - 广告位** | `GET /api/ads`<br>`GET/POST/DELETE /api/admin/ads` | 按位置（banner / home_recommend / detail）拉取广告；后台维护物料、排期与上下架 |
| **Analytics - 留存看板** | `GET /api/admin/retention` | 近14天新增访客留存、今日新增与回访，以及功能渗透率 |
| **Admin - Database** | `GET /api/admin/db/info`<br>`GET /api/admin/db/tables`<br>`GET /api/admin/db/table`<br>`POST /api/admin/db/backup`<br>`GET/DELETE /api/admin/db/backups`<br>`POST /api/admin/db/restore`<br>`POST /api/admin/db/cleanup`<br>`POST /api/admin/db/sql` | 数据库引擎信息、表统计与数据浏览、备份恢复、清理维护与 SQL 执行器 |

## 管理后台模块

Gemini 风格侧边导航 → 路由 → 后端接口对照：

| 模块 | 路由 | 主要接口 |
| :--- | :--- | :--- |
| 仪表盘 | `/dashboard` | `/api/admin/stats` 统计卡片、活跃采集点即时触发、分类分布 |
| 视频仓库 | `/videos` | `/api/videos` 检索；`/api/admin/videos/save`、`batch-delete` 编辑与批量删除 |
| 采集节点 | `/sources` | `/api/admin/sources` 增删改查、连通性测试、单源/全网采集 |
| 采集规则 | `/collection-rules` | 通用采集规则工作台（网页 / 数据库 / Excel / CSV） |
| 定时调度 | `/scheduler` | `/api/admin/scheduler/auto` 自动轮询周期与开关 |
| 资讯管理 | `/news` | `/api/admin/news` 草稿、发布、置顶、搜索 |
| 社区管理 | `/community` | `/api/admin/community/posts`、`comments` |
| 内容审核 | `/reviews` | `/api/admin/reviews` 运营提交内容审核 |
| 求片反馈 | `/feedbacks` | `/api/admin/feedbacks`、`reply` 状态与回复 |
| 广告位 | `/ads` | `/api/admin/ads` 物料、排期、上下架 |
| 成长运营 | `/growth` | `/api/admin/retention` 留存与功能渗透率看板 |
| 消息通知 | `/notifications` | `/api/admin/notifications` 定向/广播发送 |
| 用户账号 | `/users` | `/api/admin/users` 角色授权、密码重置 |
| 客户端主题 | `/themes` | `/api/admin/themes` 切换与 ZIP 上传 |
| 播放器 | `/players` | `/api/admin/players` 切换、配置、上传 |
| 数据库 | `/database` | `/api/admin/db/*` 浏览、备份恢复、清理、SQL |
| 系统配置 | `/settings` | `/api/admin/site/config` 站点信息与 SEO |
| 运行日志 | `/logs` | `/api/admin/logs` 实时日志流 |

角色权限：`super_admin` / `admin` / `observer`（只读）/ `operator`（运营，需审核后发布），与旧版一致。
