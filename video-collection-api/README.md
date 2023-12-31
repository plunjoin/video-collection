---
AIGC:
  ContentProducer: '001191110102MAD55U9H0F10002'
  ContentPropagator: '001191110102MAD55U9H0F10002'
  Label: '1'
  ProduceID: '46d7b792-d969-49ba-a734-f94fe0fed7ff'
  PropagateID: '46d7b792-d969-49ba-a734-f94fe0fed7ff'
  ReservedCode1: 'b060db96-fc20-4425-81e5-687ccf3996a5'
  ReservedCode2: 'b060db96-fc20-4425-81e5-687ccf3996a5'
---

# 视频智能采集聚合平台 - RESTful 纯后端 API 服务 (Go版)

基于 Go 语言构建的高性能影视数据智能采集清洗、多协议聚合检索与用户服务纯后端 API 系统。
本项目已完成**前后端彻底分离**架构重构，移除了内部 HTML 模板引擎与前端嵌入式页面（前端后台独立于 `video-collection-admin`，客户端前端独立于 `video-collection-web`），专注于提供标准规范、高性能的 RESTful API 接口，并全面接入 **OpenAPI 3.0** 与 **Swagger UI / Redoc** 交互式文档中心。

播放时由 Web / Flutter 客户端直接请求视频源并执行 M3U8 广告过滤，服务端不代理播放列表，也不执行切片过滤。原 `/api/m3u8` 与 `/api/m3u8/clean` 接口已移除。

---

## 🌟 核心特性与架构

### 1. 纯后端 RESTful API 架构
- **完全解耦**：彻底移除静态 HTML、嵌入式模板与视图控制器，仅对外提供标准 JSON 数据接口。
- **全局统一响应规范**：接口统一以 `{ code: 1, data: ..., msg: ... }` 或 `{ code: 0, error: ... }` 格式输出，404 与异常统一由 JSON 处理，避免任何 HTML 穿透。
- **会话与鉴权**：支持基于 Cookie（`agg_auth_token`）与 HTTP Authorization 头（`Bearer <token>`）双重认证，普通用户权限与管理员权限分级管控。

### 2. OpenAPI 3.0 文档与交互式调试中心
- **交互式 Swagger UI**：访问 `/docs` 或 `/swagger`，在线浏览所有分类接口，支持直接填写参数在线调试并查看响应结构。
- **标准化 OpenAPI 规范 JSON**：`/openapi.json`（兼容 `/v3/api-docs`），可直接一键导入 Postman、Apifox、Knife4j 或 Swagger Editor。
- **优雅的 Redoc 视角**：访问 `/redoc`，提供清晰的三栏式现代 API 规范文档。

### 3. 多协议智能采集引擎
- **通用采集规则工作台**：网页 CSS、JSON 接口、PostgreSQL / MySQL / SQLite / SQL Server、Excel / CSV，统一字段映射、清洗、样本预览及文章/视频/通用数据入库，见[配置与接口说明](docs/collection-studio.md)。
- **MacCMS v10 JSON**：苹果CMS标准接口 (`/api.php/provide/vod/?ac=detail&out=json`)。
- **MacCMS / 飞飞CMS XML**：标准 XML 资源流。
- **RSS 2.0 / Atom**：外部订阅源接入。
- **通用自定义 REST JSON**：支持自定义路径字段映射。
- **增量与全量采集**：支持按小时增量同步 (`h=24`) 与全量补全 (`h=0`)。

### 4. 高可用双引擎存储 (PostgreSQL + SQLite)
- **原生 JSONB 存储**：影视剧的多线路与各集播放地址使用 PostgreSQL `JSONB` 格式存储并建立索引。
- **自动降级保障**：未连接外部数据库时自动平滑降级至本地 SQLite (`data/collection.db`)，零配置即可开箱即用。

### 5. RSS 2.0 聚合订阅服务
- 提供标准 Web RSS 2.0 订阅端点 (`/rss.xml`, `/rss`, `/feed.xml`, `/feed`)，兼容各类 RSS 阅读器与机器人。

---

## 🚀 启动与访问

### 快速启动
```powershell
go run main.go
```
或编译为二进制执行：
```powershell
go build -o video-collection-api.exe .
.\video-collection-api.exe
```

### 打包 Linux 版本
SQLite 驱动为纯 Go 实现（`modernc.org/sqlite`），无需 CGO，可在 Windows 上直接交叉编译为静态二进制：

```powershell
# amd64（常见 x86_64 服务器）
$env:CGO_ENABLED="0"; $env:GOOS="linux"; $env:GOARCH="amd64"
go build -trimpath -ldflags="-s -w" -o dist/video-collection-api-linux-amd64 .

# arm64（ARM 服务器 / 树莓派等），只需替换 GOARCH
$env:GOARCH="arm64"
go build -trimpath -ldflags="-s -w" -o dist/video-collection-api-linux-arm64 .

# 编译完成后清理环境变量，避免影响本机后续构建
Remove-Item Env:CGO_ENABLED, Env:GOOS, Env:GOARCH
```

Linux / macOS 下：
```bash
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o dist/video-collection-api-linux-amd64 .
```

部署时需将以下文件放在同一工作目录（程序按相对路径读取）：
```text
video-collection-api-linux-amd64
config/collector_rules.yaml
players/
data/            # SQLite 数据目录，未配置 PostgreSQL 时自动创建
```

### Linux 启动命令
必须先 `cd` 到程序所在目录再启动（配置、播放器、数据目录均按相对路径读取）。端口通过环境变量 `PORT` 指定，默认 `80`（监听 1024 以下端口需要 root 或 `setcap` 授权）。

```bash
cd /opt/video-collection-api
chmod +x video-collection-api-linux-amd64

# 前台运行（默认 80 端口）
sudo ./video-collection-api-linux-amd64

# 指定端口运行（非 root 推荐）
PORT=8080 ./video-collection-api-linux-amd64

# 后台运行，日志输出到 app.log
PORT=8080 nohup ./video-collection-api-linux-amd64 > app.log 2>&1 &

# 查看日志 / 停止服务
tail -f app.log
pkill -f video-collection-api-linux-amd64
```

非 root 用户也想监听 80 端口时，可给二进制授权：
```bash
sudo setcap 'cap_net_bind_service=+ep' ./video-collection-api-linux-amd64
```

### systemd 开机自启（推荐生产环境）
新建 `/etc/systemd/system/video-collection-api.service`：
```ini
[Unit]
Description=Video Collection API
After=network.target postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/video-collection-api
ExecStart=/opt/video-collection-api/video-collection-api-linux-amd64
Environment=PORT=8080
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now video-collection-api   # 启动并设置开机自启
sudo systemctl status video-collection-api         # 查看状态
sudo systemctl restart video-collection-api        # 重启
sudo journalctl -u video-collection-api -f         # 查看实时日志
```

### 环境变量配置（数据库等）
数据库连接可通过环境变量或工作目录下的 `.env` 文件配置，无需修改 YAML。优先级：**容器/系统环境变量 > `.env` > `config/collector_rules.yaml` > 默认值**。

```bash
cp .env.example .env   # 按需修改
```

| 变量 | 说明 | 默认值 |
| :--- | :--- | :--- |
| `PORT` | 监听端口 | `80` |
| `DB_DRIVER` | `postgres` / `sqlite` | `postgres` |
| `DB_DSN` / `DATABASE_URL` | 完整连接串，设置后忽略分项配置 | - |
| `DB_HOST` `DB_PORT` `DB_USER` `DB_PASSWORD` `DB_NAME` `DB_SSLMODE` | 分项配置，设置了 `DB_HOST` 才生效 | `5432` / `postgres` / 空 / `videodb` / `disable` |
| `SQLITE_PATH` | SQLite 数据文件路径 | `data/collection.db` |
| `CONFIG_PATH` | 采集规则 YAML 路径 | `config/collector_rules.yaml` |
| `ENV_FILE` | `.env` 文件路径（只能通过系统/容器环境变量设置） | `.env`（相对工作目录） |

> 注意：PostgreSQL 连接失败时会自动降级到 SQLite，启动日志出现 `正在平滑降级至本地 SQLite` 说明数据库配置没生效。

### Docker 部署
容器内的 `localhost` 指容器自身，`DB_HOST` 需填数据库容器名（同一 Docker 网络）或宿主机 IP（可用 `host.docker.internal` 并加 `--add-host=host.docker.internal:host-gateway`）。

```bash
docker run -d --name video-collection-api \
  --restart always \
  --env-file /opt/video-collection-api/.env \
  -p 8080:8080 \
  -v /opt/video-collection-api/config:/app/config \
  -v /opt/video-collection-api/data:/app/data \
  -w /app \
  your-image
```

`docker-compose.yml` 中使用：
```yaml
services:
  api:
    image: your-image
    env_file: .env
    ports:
      - "8080:8080"
    volumes:
      - ./config:/app/config
      - ./data:/app/data
    depends_on:
      - postgres
```

### 核心访问入口
| 服务说明 | 访问地址 |
| :--- | :--- |
| **OpenAPI 交互式文档 (Swagger UI)** | `http://localhost:80/docs` (或 `/swagger`) |
| **OpenAPI 规范 JSON 数据** | `http://localhost:80/openapi.json` |
| **Redoc 文档视角** | `http://localhost:80/redoc` |
| **服务状态 / API 网关首页** | `http://localhost:80/` |
| **视频分页检索与搜索 API** | `http://localhost:80/api/videos` |
| **分类列表 API** | `http://localhost:80/api/categories` |
| **RSS 2.0 聚合订阅** | `http://localhost:80/rss.xml` |

---

## 📚 接口模块分类索引

资讯、社区与站内通知的完整参数、权限规则及调用示例见 [内容与通知接口说明](docs/content-api.md)，也可在 `/docs` 在线调试。SQLite / PostgreSQL 启动时会自动创建这些模块的表和索引，无需手动执行 SQL。

影视、资讯和社区共用[通用评论接口](docs/comments-api.md)，支持多级回复、评论点赞及站内通知；旧社区评论数据自动迁移且保留原ID。新内容类型可通过服务端注册接入。

管理员可通过[数据库管理接口](docs/database-api.md)查看引擎信息与表统计、分页浏览表数据、执行 JSON 备份与恢复、清理维护及运行单条管理 SQL；删除备份、恢复、清理与写 SQL 均需携带二次确认参数。

| 模块 | 核心端点 | 描述 |
| :--- | :--- | :--- |
| **Auth** | `POST /api/login`<br>`POST /api/register`<br>`POST /api/logout`<br>`GET /api/me` | 用户登录、注册、注销与当前用户查询 |
| **Videos** | `GET /api/videos`<br>`GET /api/video`<br>`POST /api/video/hit`<br>`GET /api/rankings`<br>`GET /api/latest` | 视频列表检索、详情、播放热度累加、排行榜与最新更新 |
| **Categories** | `GET /api/categories` | 获取系统视频分类列表 |
| **User** | `GET /api/user/history`<br>`POST /api/user/history`<br>`POST /api/user/history/sync`<br>`GET /api/user/favorites` | 播放进度云端同步、历史记录管理与追剧收藏 |
| **Site** | `GET /api/site/config`<br>`POST /api/feedback` | 公开站点信息、用户求片与报错反馈提交 |
| **News** | `GET /api/news`<br>`GET/POST/DELETE /api/admin/news` | 资讯列表、详情、草稿、发布、分类、搜索与置顶 |
| **Comments** | `GET/POST/DELETE /api/comments`<br>`POST/DELETE /api/comments/likes`<br>`GET/DELETE /api/admin/comments` | 通用评论、多级回复、评论点赞、通知及管理；关联影视/资讯/社区，可扩展 |
| **Community** | `GET/POST/DELETE /api/community/posts`<br>`GET/POST/DELETE /api/community/comments`<br>`POST/DELETE /api/community/likes` | 发帖、评论、点赞；管理员通过 `/api/admin/community/posts` 和 `/api/admin/community/comments` 管理内容 |
| **Notifications** | `GET/DELETE /api/user/notifications`<br>`GET /api/user/notifications/unread-count`<br>`POST /api/user/notifications/read`<br>`POST /api/admin/notifications` | 互动通知、系统通知、未读统计、已读管理与定向/广播发送 |
| **Admin - Sources** | `GET/POST/DELETE /api/admin/sources`<br>`POST /api/admin/sources/collect`<br>`POST /api/admin/sources/collect-all` | 采集源维护、连通性测试与手动采集任务触发 |
| **Admin - Videos** | `DELETE /api/admin/videos`<br>`POST /api/admin/videos/save`<br>`POST /api/admin/videos/batch-delete` | 视频编辑、单条删除与批量清理 |
| **Admin - Users** | `GET/POST/DELETE /api/admin/users` | 用户账号分页列表、权限分配与状态修改 |
| **Admin - Stats & Logs** | `GET /api/admin/stats`<br>`GET /api/admin/logs` | 系统仪表盘统计指标与操作审计日志流水 |
| **Admin - Database** | `GET /api/admin/db/info`<br>`GET /api/admin/db/tables`<br>`GET /api/admin/db/table`<br>`POST /api/admin/db/backup`<br>`GET/DELETE /api/admin/db/backups`<br>`POST /api/admin/db/restore`<br>`POST /api/admin/db/cleanup`<br>`POST /api/admin/db/sql` | 数据库引擎信息、表统计与数据浏览、备份恢复、清理维护与 SQL 执行器 |

> AI生成

## 可配置采集与生产部署

视频采集支持可编辑的 YAML 模板目录及保存在数据库中的规则副本，MacCMS 作为其中一种模板。详见 [采集规则说明](docs/collection-rules.md)。Docker Compose、数据库持久化、HTTPS、备份恢复和升级见 [部署文档](../deploy/README.md)。
