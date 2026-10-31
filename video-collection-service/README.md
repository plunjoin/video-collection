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
                       └─► Bllii-Familiar 使魔调度 / 网络采集 / RSS / M3U8 清洗
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
│   ├── ingest/ collector/ m3u8cleaner/ rss/ scheduler/ store/ theme/ player/ openapi/
├── web/
│   └── admin/               # Vue3 管理后台（Gemini 风格）
│       ├── embed.go         # go:embed all:dist —— SPA 托管处理器
│       ├── src/             # 前端源码
│       └── dist/            # 构建产物（打入二进制）
├── players/ themes/ data/   # 运行时目录
├── Dockerfile               # wf 构建前端（纯 Go，零 Node）+ go 构建服务的合并镜像
└── .env.example
```

## 快速开始

### 1. 安装 wf CLI（一次性）

前端（管理后台 + 门户）统一由 [webfront](https://github.com/plunjoin/webfront) 的 wf CLI 构建，esbuild 内核、纯 Go 实现，**全程不需要 Node**：

```bash
go install github.com/plunjoin/webfront/cmd/wf@v0.1.0
```

### 2. 安装前端依赖并构建（改动前端后重跑）

```bash
cd video-collection-service

wf install -modules wf_modules .   # 首次或依赖变更（按 web/package-lock.json 锁定版本，产物在 web/wf_modules）

MSYS_NO_PATHCONV=1 wf build -mode spa -base /admin -modules ../wf_modules web/admin
# 管理后台（Vue 3）→ web/admin/dist（PowerShell/cmd 去掉 MSYS_NO_PATHCONV=1 前缀）

wf build -modules ../wf_modules web/portal
# 门户（React SSR）→ web/portal/dist
```

### 3. 编译并运行服务

```bash
cd ..                # 若在上面 web 目录中，回到 video-collection-service
go build -o video-collection-service .
./video-collection-service  # 默认 80 端口，PORT=8080 可改
```

| 入口 | 地址 |
| :--- | :--- |
| **门户（webfront 托管）** | `http://localhost:8080/`（SSR + SPA，根路径即门户） |
| **管理后台（Go 托管）** | `http://localhost:8080/admin` |
| 服务状态（程序访问） | `/status` |
| OpenAPI 交互文档 | `/docs` |
| OpenAPI 规范 JSON | `/openapi.json` |
| 视频检索 API | `/api/videos` |
| RSS 订阅 | `/rss.xml` |
| 健康检查 | `/healthz` |

前端开发模式：`go run -tags dev .`（webfront DevServer，esbuild 按需转译 + HMR，与 API 同进程同源）——门户与管理后台都在 dev 壳下从源码实时编译，改完源码保存即热更。生产构建用 `wf build`（见 [`web/admin/README.md`](web/admin/README.md)）。

## 基础配置（SQLite bootstrap）

SQLite 不再是 PostgreSQL 故障时的数据兜底库，而是**基础配置的存储位置**——数据库连接、Redis 连接、初始管理员账号密码、Webhook 加密主密钥等启动引导信息，全部持久化在本地 SQLite 文件（默认 `data/collection.db`）的 `bootstrap_config` 表中，可在管理后台「基础配置」页（`/admin/bootstrap`）维护。

| 配置项 | 键 | 说明 |
| :--- | :--- | :--- |
| 数据库驱动 | `db.driver` | `postgres` / `sqlite`（单文件模式，非兜底） |
| 数据库连接 | `db.dsn` 或 `db.host` / `db.port` / `db.user` / `db.password` / `db.name` / `db.sslmode` | PostgreSQL 连接信息，支持保存前「测试连通性」 |
| Redis | `redis.addr` / `redis.password` / `redis.db` / `redis.prefix` | 可选；未配置则内存会话 + 无缓存 |
| 初始管理员 | `admin.username` / `admin.password` | 仅在数据库无用户时首次初始化生效；未配置时随机生成并写回 |
| Webhook 主密钥 | `webhook.encryption_key` | 可选；未配置时由管理员初始密码派生 |

解析优先级：**环境变量 / 容器注入 > 基础配置（bootstrap SQLite）> `config/collector_rules.yaml` > 内置默认值**。

行为变化：

- PostgreSQL 连接失败时服务**直接退出**并给出修正指引（不再静默降级写另一套 SQLite 数据，避免数据漂移）；原 `DB_REQUIRE_PRIMARY` 开关随之废弃。
- 首次启动若检测到本地 SQLite 已有业务数据且未配置任何数据库，会一次性显式切换为 SQLite 单文件模式并把 `db.driver=sqlite` 写入基础配置（有记录、可审计，而非静默兜底）。
- `GET /api/admin/bootstrap` 返回掩码后的配置与每一项的生效来源；`PUT` 保存时敏感字段传 `********` 表示不修改；数据库/Redis 连接信息保存后需重启生效。

### 连接串格式（DB_DSN）

```
postgres://用户名:密码@主机:端口/库名?sslmode=disable
# 例：postgres://x21_admin:PASS@1panel-postgresql-hi3r:5432/videodb?sslmode=disable
```

主机名**不能带斜杠**。写成 `postgres://user:pw@//my-pg/:5432/videodb` 时，URL 解析后主机为空、库名变成 `/my-pg/:5432/videodb`，驱动会连到本机 `:5432`，甚至用这个非法库名去 `CREATE DATABASE`，最终表现为莫名的建表失败。

启动时会自动修正这类斜杠写法并打印 `[WARN]`，修正不了则直接拒绝启动并给出正确格式。容器部署请用**服务名/容器名**（如 `1panel-postgresql-hi3r`），不要用 `127.0.0.1`。

常见启动失败原因：

| 现象 | 原因 | 处理 |
| :--- | :--- | :--- |
| `dial tcp: lookup xxx: no such host` | 主机名不可解析 | 确认应用容器与数据库在同一 Docker 网络，用服务名/容器名 |
| `permission denied for schema public` | PostgreSQL 15+ 默认收回 `public` 建表权限 | 超管执行 `GRANT ALL ON SCHEMA public TO <用户>;` 或把库 owner 改为该用户 |
| `第 N 条语句执行失败: ...` | 建表脚本具体哪一条失败（会打印该语句） | 按提示修正；旧库升级时多为某列缺失导致的索引创建失败 |
| `database "xxx" does not exist` 且库名很怪 | DSN 写错，被当成库名 | 按上面的格式改正，并清理误建的库 |

### 确认线上跑的是哪份代码

启动横幅会打印构建标识，`/status` 接口的 `build` 字段同样可见：

```
==================================================================
   Bllii 可配置采集聚合平台 - 统一服务 (Go: RESTful API + 管理后台)
   构建标识: commit=1fc4d0b90e57  commitTime=2026-10-22T14:51:46Z  buildTime=2026-10-22 23:10:28
==================================================================
```

取值优先级：`ldflags` 注入的 `buildVersion` → Go 自动写入的 VCS 信息（在含 `.git` 的目录构建时才有）→ 二进制文件修改时间（容器内即镜像构建时间）。

**排查「改了代码线上却没变」**：先看这一行。

- `buildTime` 早于你最后一次提交 → 镜像没重建，`docker compose build --no-cache service && docker compose up -d service`；
- 提交了但日志里没有 `[WARN]`、DSN 也和 `.env` 里一模一样 → 跑的确实是旧二进制，同上；
- `buildTime` 是新的、行为仍旧 → 才是真的代码问题，按下面的错误信息继续查。

连接失败前还会打印 `[*] 连接目标: 主机:端口/库名`，可直接确认连的是哪个库。

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
# 门户      http://127.0.0.1:8080/（统一服务托管）
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
| **Analytics - 埋点** | `POST /api/track` | 轻量埋点上报（page_view / page_leave 停留时长 / rec_click / ad_click / search / favorite / play / impression / video_click / play_progress）；支持 `platform` 字段，缺省按 User-Agent 识别网站 / App（Flutter Dart UA） |
| **Analytics - 搜索建议** | `GET /api/search/suggest` | 输入自动补全（作品名匹配）与真实搜索热词（近7天） |
| **Analytics - 个性化推荐** | `GET /api/recommend/for-you` | 基于播放历史与追剧收藏的类型亲和度加权推荐，需登录 |
| **Analytics - 广告位** | `GET /api/ads`<br>`GET/POST/DELETE /api/admin/ads` | 按位置（banner / home_recommend / detail）拉取广告；后台维护物料、排期与上下架 |
| **Analytics - 留存看板** | `GET /api/admin/retention` | 近14天新增访客留存、今日新增与回访，以及功能渗透率 |
| **Analytics - 埋点总览** | `GET /api/admin/analytics/overview` | 网站 / App 的今日、昨日、累计 PV-UV、近30天趋势、平台分布、热门页面与事件分布 |
| **Admin - Database** | `GET /api/admin/db/info`<br>`GET /api/admin/db/tables`<br>`GET /api/admin/db/table`<br>`POST /api/admin/db/backup`<br>`GET/DELETE /api/admin/db/backups`<br>`POST /api/admin/db/restore`<br>`POST /api/admin/db/cleanup`<br>`POST /api/admin/db/sql`<br>`POST /api/admin/db/table/rows/delete`<br>`POST /api/admin/db/table/clear` | 数据库引擎信息、表统计与数据浏览、备份恢复、清理维护、SQL 执行器与超管删除/清空数据 |
| **Admin - Bootstrap** | `GET /api/admin/bootstrap`<br>`PUT /api/admin/bootstrap`<br>`POST /api/admin/bootstrap/test-db` | 基础配置读写：数据库连接、Redis、初始管理员、Webhook 主密钥；保存前可测试数据库连通性 |

## 管理后台模块

Liquid Glass 玻璃风侧边导航 → 路由 → 后端接口对照：

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
| 埋点信息预览 | `/analytics` | `/api/admin/analytics/overview` 网站 / App PV-UV 总览、30天趋势、平台分布、热门页面、事件分布 |
| 消息通知 | `/notifications` | `/api/admin/notifications` 定向/广播发送 |
| 用户账号 | `/users` | `/api/admin/users` 角色授权、密码重置 |
| 客户端主题 | `/themes` | `/api/admin/themes` 切换与 ZIP 上传 |
| 数据库 | `/database` | `/api/admin/db/*` 浏览、备份恢复、清理、SQL；超管可删除选中行与清空表 |
| 基础配置 | `/bootstrap` | `/api/admin/bootstrap` 数据库 / Redis / 初始管理员等启动引导信息 |
| 系统配置 | `/settings` | `/api/admin/site/config` 站点信息与 SEO |
| 运行日志 | `/logs` | `/api/admin/logs` 实时日志流 |

角色权限：`super_admin` / `admin` / `observer`（只读）/ `operator`（运营，需审核后发布），与旧版一致。
