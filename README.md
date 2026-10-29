<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./bllii-brand-kit/png/bllii-horizontal-white.png">
  <img src="./bllii-brand-kit/png/bllii-horizontal.png" alt="Bllii" width="280">
</picture>

# Bllii · video-collection

**Bllii · 二次元番剧与网络采集聚合平台 (Bllii-Familiar 追番使魔)**

从数据采集、内容管理到多端浏览与播放，共享一套 RESTful API。

<p>
  <a href="https://go.dev/"><img src="https://img.shields.io/badge/Go-1.26-00ADD8?style=flat-square&amp;logo=go&amp;logoColor=white" alt="Go 1.26"></a>
  <a href="https://github.com/plunjoin/webfront"><img src="https://img.shields.io/badge/webfront-SSR%20%2F%20SPA-4B9FFF?style=flat-square" alt="webfront"></a>
  <a href="https://vuejs.org/"><img src="https://img.shields.io/badge/Vue-3-42B883?style=flat-square&amp;logo=vuedotjs&amp;logoColor=white" alt="Vue 3"></a>
  <a href="https://flutter.dev/"><img src="https://img.shields.io/badge/Flutter-Multi--Platform-02569B?style=flat-square&amp;logo=flutter&amp;logoColor=white" alt="Flutter 多平台客户端"></a>
  <a href="#系统架构"><img src="https://img.shields.io/badge/Storage-PostgreSQL%20%2F%20SQLite-4169E1?style=flat-square&amp;logo=postgresql&amp;logoColor=white" alt="PostgreSQL / SQLite"></a>
</p>

[功能概览](#功能概览) · [快速开始](#快速开始) · [配置指南](#配置指南) · [文档导航](#文档导航) · [品牌资产](#品牌资产)

<sub>More Stories, Together</sub>

</div>

> [!IMPORTANT]
> **本项目仅供个人学习与技术研究使用，不得用于任何商业用途。**
>
> 本仓库只包含源代码、配置示例与品牌素材，**不存储、不提供、不分发任何影视内容**，也不内置任何第三方资源站地址。采集配置中的数据源使用 `example.com` 占位，使用者应仅接入自己拥有版权或已获得合法授权的数据源，并遵守所在地法律法规与相关平台的服务条款。
>
> 因使用、修改或部署本项目产生的任何法律责任由使用者自行承担，与作者无关。若本项目内容侵犯了您的合法权益，请通过 [Issue](https://github.com/plunjoin/video-collection/issues) 联系，我们将及时处理。

## 功能概览

| 能力 | 主要功能 |
| :--- | :--- |
| **Bllii-Familiar 使魔采集** | 网络视频 JSON、XML、RSS / Atom、自定义 REST JSON；多源自动化增量与全量采集 |
| **使魔规则工坊** | 静态网页 CSS、JSON 接口、数据库、Excel / CSV；字段映射、清洗、样本预览与入库 |
| **内容浏览与播放** | 首页推荐、分类筛选、搜索、排行榜、新番时间表、详情、多线路选集与播放 |
| **用户与互动** | 登录注册、追番收藏、观看历史与进度同步；资讯、社区、通用评论及站内通知 API |
| **增长与粘性** | PWA 安装与离线浏览、个人搜索历史与自动补全、个性化首页推荐、次日/7日留存与功能渗透率看板、轻量埋点（停留/推荐/广告点击） |
| **广告位管理** | banner / 首页推荐位 / 详情页三类广告位，支持排期、上下架，客户端自动隐藏空广告位 |
| **后台管理** | 采集源、视频库、用户、调度、反馈、站点配置、主题、播放器、日志与数据库管理 |
| **接口与存储** | RESTful API、Cookie / Bearer 鉴权、OpenAPI、Swagger UI、Redoc、RSS 订阅；PostgreSQL / SQLite |

各端的具体实现与配置方式见[子项目文档](#文档导航)。数据库导入支持 PostgreSQL、MySQL、SQLite 和 SQL Server；**平台自身的业务存储使用 PostgreSQL 或 SQLite**。

## 系统架构

```mermaid
flowchart TB
    sources["已授权数据源<br/>JSON / XML / RSS / 网页 / 数据库 / 文件"]
    service["video-collection-service<br/>Go · RESTful API + 管理后台（go:embed）"]
    db[("PostgreSQL / SQLite")]
    redis[("Redis (radix)<br/>会话与缓存 · 可选")]
    web["Web 门户<br/>React 18 + webfront（Go 托管 SSR/SPA）"]
    app["跨端客户端<br/>Flutter + Material 3"]
    adminClient["浏览器管理后台<br/>Vue 3 · Reka UI (Radix Vue)（Go 托管）"]

    sources -->|采集与清洗| service
    service <-->|读写| db
    service <-.->|会话 / 读缓存| redis
    web <-->|REST API| service
    service -->|/admin 托管 SPA| adminClient
    app <-->|REST API| service

    classDef service fill:#eef6ff,stroke:#4b9fff,color:#353b58
    classDef client fill:#f5f1ff,stroke:#9a83ff,color:#353b58
    classDef storage fill:#fff0f7,stroke:#ff89c7,color:#353b58
    class api service
    class web,admin,app client
    class db storage
```

- **统一服务（video-collection-service）**：原 `video-collection-api` 与 `video-collection-admin` 已合并为一个 Go 服务——管理后台 SPA 通过 `go:embed` 内嵌，由服务直接托管 `/admin`，无需独立后台容器。
- **radix 缓存与会话**：接入 Redis（`mediocregopher/radix/v4`）后启用分布式会话与公开读接口缓存；未配置时自动降级为内存会话 + 直连数据库。
- **前后端分离**：门户与客户端独立运行，共用后端数据与接口。
- **本地开发轻量启动**：未配置数据库时服务以 SQLite 单文件模式运行（也可显式 `DB_DRIVER=sqlite`）；SQLite 同时承担基础配置存储（数据库连接、Redis、初始管理员账号密码等）。
- **接口文档随服务提供**：`/docs`、`/redoc`、`/openapi.json`。

## 仓库结构

| 目录 / 文件 | 职责 | 技术栈 / 用途 |
| :--- | :--- | :--- |
| [`video-collection-service/`](./video-collection-service/) | **统一服务**：RESTful API + Go 托管管理后台，含 radix 缓存/会话层 | Go 1.26 · radix v4 |
| [`video-collection-service/web/`](./video-collection-service/web/) | 前端工作区：`admin/` 管理后台 + `portal/` 用户门户，依赖统一由 pnpm workspace 管理，构建产物 go:embed 进服务 | Vue 3 · Vite 6 · React 18 · webfront |
| [`video-collection-app/`](./video-collection-app/) | 桌面、移动与 Web 客户端 | Flutter · Material 3 |
| [`bllii-brand-kit/`](./bllii-brand-kit/) | 标志、图标、品牌动画与预览 | SVG · PNG · GIF · MP4 |
| [`run.ps1`](./run.ps1) / [`run.sh`](./run.sh) | 多服务启动器 | Windows PowerShell / Bash |

## 快速开始

### 1. 准备环境

按需要运行的子项目安装工具；仅启动 Service 和 Web 时无需安装 Flutter。

| 工具 | 要求 | 用于 |
| :--- | :--- | :--- |
| [Go](https://go.dev/dl/) | 1.26.0 或更高，参见 [`go.mod`](./video-collection-service/go.mod) | 统一服务 |
| [Node.js](https://nodejs.org/) | 建议使用当前 LTS 版本 | 前端工作区（admin / portal） |
| [pnpm](https://pnpm.io/installation) | 启动器使用的前端包管理器 | 前端工作区（依赖统一装在 `video-collection-service/web/`） |
| [Go 内置 wf CLI](https://github.com/plunjoin/webfront) | 仓库根已提供 `wf.exe` / `wf.ps1` / `wf.cmd` | 门户构建（纯 Go，零 Node） |
| [Flutter SDK](https://docs.flutter.dev/get-started/install) | 需包含 Dart `^3.13.3`，参见 [`pubspec.yaml`](./video-collection-app/pubspec.yaml)；安装目标平台工具链 | App |
| [PostgreSQL](https://www.postgresql.org/download/) | 可选；本地可使用 SQLite | 服务存储 |

### 2. 获取项目

```bash
git clone https://github.com/plunjoin/video-collection.git
cd video-collection
```

### 3. 启动 API、后台与门户

**Windows · PowerShell**

```powershell
.\run.ps1 service web
```

**macOS / Linux · Bash**

```bash
chmod +x run.sh
./run.sh service web
```

`service` 为合并后的统一服务（API + 管理后台）；旧参数 `api` / `admin` 仍指向合并前的两个子项目，保留兼容。启动器会检查所选目标需要的运行时，并执行 `go mod download`，在缺少依赖时执行 `pnpm install` / `flutter pub get`。缺少 pnpm 时会尝试通过 Corepack 或 npm 安装；其他运行时缺失时会给出安装提示并退出。

> 前端依赖统一在 `video-collection-service/web/` 工作区（pnpm workspace）。首次构建前端：
> ```bash
> cd video-collection-service/web
> pnpm install                       # 单份 node_modules，admin / portal 共用
> cd admin && pnpm build             # 管理后台 → web/admin/dist
> cd ../portal && ../../wf.exe build .   # 门户 → web/portal/dist（或从仓库根 wf build）
> ```
> 之后由 `go:embed` 随二进制分发；仅改门户时重跑 wf build，仅改后台时重跑 pnpm build。

所有服务在**同一个终端并行运行**，日志带 `[api]`、`[admin]`、`[web]`、`[app]` 前缀，按 **Ctrl+C** 停止全部。Windows 启动器会设置 UTF-8 控制台编码。

### 4. 打开服务

以下地址按**默认配置**列出，实际端口以启动日志为准。

| 入口 | 本地地址 | 说明 |
| :--- | :--- | :--- |
| **Web 门户** | [localhost:8080/](http://localhost:8080/) | 用户浏览与播放入口（SSR + SPA，统一服务托管） |
| **管理后台** | [localhost:8080/admin](http://localhost:8080/admin) | 管理与采集配置入口（统一服务托管） |
| **服务状态（程序）** | [localhost:8080/status](http://localhost:8080/status) | 在线状态、缓存与接口索引（JSON） |
| **Swagger UI** | [localhost:8080/docs](http://localhost:8080/docs) | 在线查看与调试接口 |
| **Redoc** | [localhost:8080/redoc](http://localhost:8080/redoc) | 接口参考文档 |
| **OpenAPI JSON** | [localhost:8080/openapi.json](http://localhost:8080/openapi.json) | 导入 Postman / Apifox 等工具 |
| **RSS 订阅** | [localhost:8080/rss.xml](http://localhost:8080/rss.xml) | 聚合订阅输出 |

首次初始化数据库时会创建管理员账号：**`admin`**，密码可通过 `ADMIN_INITIAL_PASSWORD` 配置，未设置时为 `admin123`。生产部署步骤见 [部署与维护](./deploy/README.md)。

> [!TIP]
> 示例采集源使用占位地址。首次使用请在后台配置已授权的数据源，再执行采集；启动服务本身不会产生真实影视数据。

### 更多启动组合

下面以 Windows 为例；macOS / Linux 将 `.\run.ps1` 替换为 `./run.sh` 即可。

```powershell
# 查看参数说明
.\run.ps1 help

# 只启动门户
.\run.ps1 web

# API + 后台 + 门户 + Windows 客户端
.\run.ps1 api admin web windows

# API + 后台 + 门户 + Android 客户端
.\run.ps1 api admin web android

# 全部项目，App 使用当前系统默认桌面平台
.\run.ps1 all

# 全部项目，App 使用 Chrome
.\run.ps1 all chrome
```

| 参数 | 含义 |
| :--- | :--- |
| `api` / `admin` / `web` | `api`（等同 `service`）启动 Go 统一服务；`admin` 启动 Vue 后台开发服务器；`web` 启动门户（门户由统一服务内嵌托管，启动即服务本体），可组合使用 |
| `app` | 启动 Flutter 客户端；默认平台为 Windows → `windows`、macOS → `macos`、Linux → `linux` |
| `all` | 启动 API + Admin + Web + App |
| `windows` / `android` / `ios` / `macos` / `linux` / `chrome` / `edge` / `web-server` | 指定 Flutter 目标平台，同时启用 App；需具备对应工具链与可用设备 |

**`web` 表示门户，由统一服务内嵌托管（webfront 引擎），效果等同 `service`。** Flutter Web 使用 `chrome`、`edge` 或 `web-server`；iOS / macOS 构建需要 macOS 环境。

<details>
<summary><strong>手动安装依赖与单独启动</strong></summary>

各段命令均从仓库根目录开始，在独立终端执行。

**Service（API + 管理后台一体）**

```bash
cd video-collection-service
go mod download
go run .
```

启动后访问 `/` 即为门户、`/admin` 即为管理后台（前端已内嵌，无需单独启动前端）。前端改动后重建：

```bash
# 依赖统一装在 web 工作区（首次或依赖变更时）
cd video-collection-service/web && pnpm install

# 管理后台（Vue + Vite）
cd web/admin && pnpm build

# 门户（React + webfront，纯 Go 构建）
cd ../portal && ../../wf.exe build .

# 门户开发模式（esbuild 按需转译 + HMR，免打包）
cd video-collection-service && go run -tags dev .
```

**App · Windows 示例**

```bash
cd video-collection-app
flutter pub get
flutter run -d windows
```

</details>

## 配置指南

### API 与数据库

API 支持系统环境变量、工作目录下的 `.env` 和 YAML 配置，优先级为：

**系统 / 容器环境变量 > `.env` > `config/collector_rules.yaml` > 默认值**

复制 [`video-collection-service/.env.example`](./video-collection-service/.env.example) 为同目录下的 `.env`，按实际环境修改。

| 变量 | 用途 | 默认 / 注意事项 |
| :--- | :--- | :--- |
| `PORT` | API 监听端口 | 未设置时为 `80`；示例 `.env` 为 `8080` |
| `DB_DRIVER` | 业务数据库引擎 | `postgres` 或 `sqlite` |
| `DB_DSN` / `DATABASE_URL` | 数据库完整连接串 | 设置后优先于分项连接配置 |
| `DB_HOST`、`DB_PORT`、`DB_USER`、`DB_PASSWORD`、`DB_NAME`、`DB_SSLMODE` | PostgreSQL 分项连接配置 | 具体示例见服务 `.env.example` |
| `SQLITE_PATH` | SQLite 文件位置 | `data/collection.db` |
| `CONFIG_PATH` | 采集规则配置路径 | `config/collector_rules.yaml` |
| `WEBHOOK_ENCRYPTION_KEY` | Webhook 密钥信封加密主密钥 | 可选；缺省时由 `ADMIN_INITIAL_PASSWORD` 派生，见 [Webhook 文档](./video-collection-service/docs/webhook-api.md) |

> [!NOTE]
> **本地端口需要统一。** Admin 和 Web 的开发代理默认指向 `http://localhost:80`。直接复制 API 的 `.env.example` 会把 API 端口改为 `8080`，请将 `.env` 中的 `PORT` 改为 `80`，或同步调整各端连接配置。Linux / macOS 监听 `80` 可能需要额外权限，可使用 `8080` 并同步修改客户端地址。

### 各端连接地址

| 子项目 | 配置入口 | 本地默认行为 |
| :--- | :--- | :--- |
| **Admin** | 服务直接托管 `/admin`；[`vite.config.ts`](./video-collection-service/web/admin/vite.config.ts) → `server.proxy` | 独立开发时 `/api` 与 `/rss.xml` 代理到 `http://localhost:80` |
| **Portal** | 浏览器同源 `/api`，无独立配置 | 生产 SSR / SPA 由统一服务托管；开发模式 `go run -tags dev .` 同源取数 |
| **App** | 调试包可在设置中修改；正式包使用构建参数 `API_BASE_URL` | 调试时 Android 模拟器使用 `http://10.0.2.2:80`，其他平台默认 `http://127.0.0.1:80`。正式包执行 `flutter build ... --dart-define=API_BASE_URL=https://api.example.com`，不再显示服务端地址配置 |

门户的浏览器请求全部走同源 `/api`，无需跨域或独立环境变量；开发模式（`go run -tags dev .`）下门户与 API 同进程同源。调试真机访问 API 时，App 应在设置里填写宿主机局域网 IP，不能使用真机自己的 `localhost`。正式包只读取构建时的 `API_BASE_URL`。

生产环境的反向代理、数据库、构建与服务部署步骤见 [统一服务文档](./video-collection-service/README.md) 与 [部署与维护](./deploy/README.md)。

## 文档导航

| 文档 | 适用内容 |
| :--- | :--- |
| [生产部署与维护](./deploy/README.md) | Docker Compose、域名 HTTPS、数据持久化、备份恢复与升级 |
| [可配置采集规则](./video-collection-service/docs/collection-rules.md) | 模板目录、自定义请求、字段映射与分页 |
| [统一服务 API 使用与部署](./video-collection-service/README.md) | 采集协议、鉴权、存储、OpenAPI、radix 缓存、二进制构建与部署 |
| [管理后台](./video-collection-service/README.md) | Gemini 风格后台界面、模块、开发与构建 |
| [Web 门户](./video-collection-service/web/portal/README.md) | 页面组件、开发、构建与接口调用 |
| [Flutter 客户端](./video-collection-app/README.md) | 多端运行、API 配置与发布构建 |
| [通用采集规则工作台](./video-collection-service/docs/collection-studio.md) | 来源配置、字段映射、预览、入库与能力边界 |
| [内容与通知 API](./video-collection-service/docs/content-api.md) | 资讯、社区、站内通知与权限规则 |
| [通用评论 API](./video-collection-service/docs/comments-api.md) | 多级回复、点赞、通知与内容类型扩展 |
| [数据库管理 API](./video-collection-service/docs/database-api.md) | 数据浏览、备份恢复、维护与管理 SQL |
| [Webhook 回调采集 API](./video-collection-service/docs/webhook-api.md) | 回调端点、HMAC 验签、防重放、原始报文留痕与密钥管理 |
| [品牌资产说明](./bllii-brand-kit/README.md) | 标志、图标、动画与接入规范 |

## 品牌资产

Web 与 App 沿用 **Bllii / bllii** 视觉体系，以蓝、紫、粉为主色。品牌资产位于 [`bllii-brand-kit/`](./bllii-brand-kit/)，包含矢量标志、透明 PNG、App 图标、功能图标与品牌动画。

| 蓝 | 紫 | 粉 | 深墨 |
| :---: | :---: | :---: | :---: |
| `#4B9FFF` | `#9A83FF` | `#FF89C7` | `#353B58` |

更新功能图标 `bllii-brand-kit/svg/bllii-ui.svg` 后，在门户目录执行：

```bash
cd video-collection-service/web/portal
node scripts/sync-brand.mjs
```

该命令同步图标预览、Web 图标资源，以及 Web / API 两份播放器中的图标。完整资产与动画预览可在本地打开 [`bllii-brand-kit/index.html`](./bllii-brand-kit/index.html)，功能图标总览见 [`ui-icons.html`](./bllii-brand-kit/ui-icons.html)。

<details>
<summary><strong>查看品牌资产总览</strong></summary>

![Bllii 品牌资产总览](./bllii-brand-kit/brand-overview.png)

</details>

## 常见问题

<details>
<summary><strong>前端已启动，但接口请求失败</strong></summary>

先检查 Service 是否启动，再确认端口和连接地址一致。服务默认端口为 `80`，服务 `.env.example` 中为 `8080`；Admin 开发代理默认连接 `80`。门户与 API 同源同进程，无需跨域配置。

</details>

<details>
<summary><strong>启动时报 PostgreSQL 连接失败并退出</strong></summary>

系统不再把 SQLite 作为 PostgreSQL 故障时的数据兜底（避免两套库数据漂移）。请通过以下任一方式修正后重启：
1. 管理后台「基础配置」页面（`/admin/bootstrap`，接口 `GET|PUT /api/admin/bootstrap`）填写数据库连接并保存，支持「测试连通性」；
2. 环境变量：`DB_DSN` 或 `DB_HOST/DB_PORT/DB_USER/DB_PASSWORD/DB_NAME`；
3. 确需 SQLite 单文件模式时，将 `db.driver` 显式设为 `sqlite`。
容器中 `localhost` 指向容器自身，数据库地址应填写可达的数据库容器名或宿主机地址。
</details>

<details>
<summary><strong>App 无法连接本机 API</strong></summary>

Android 模拟器使用 `10.0.2.2` 访问宿主机；真机需与宿主机网络互通，并在「我的 → API 配置」中填写宿主机局域网 IP 和实际端口。检查宿主机防火墙是否允许该端口。

</details>

<details>
<summary><strong>Flutter 找不到目标设备</strong></summary>

运行 `flutter doctor` 检查工具链，再运行 `flutter devices` 确认目标设备可用。启动器的 `all` 包含 Flutter 客户端；只需要浏览器门户与后台时，使用 `api admin web`。

</details>

---

<div align="center">

**Bllii · More Stories, Together**

[快速开始](#快速开始) · [文档导航](#文档导航) · [反馈问题](https://github.com/plunjoin/video-collection/issues)

</div>
