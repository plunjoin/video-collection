# video-collection

影视 / 番剧智能采集聚合平台（前后端分离）。后端提供统一 RESTful API，前台门户、管理后台与跨端客户端各自独立仓库目录，共享同一套数据与接口。

品牌面向 **Bllii / bllii** 浅色蓝紫粉体系，素材见 `bllii-brand-kit`。

---

## 仓库结构

| 目录 | 说明 | 技术栈 |
|------|------|--------|
| [`video-collection-api`](./video-collection-api) | 纯后端 API：采集、检索、鉴权、调度、OpenAPI | Go |
| [`video-collection-admin`](./video-collection-admin) | 管理后台：采集点、片库、用户、主题、播放器等 | Vite 6 + Vue 3 + Element Plus |
| [`video-collection-web`](./video-collection-web) | 用户门户：首页、分类、详情、播放 | Astro 5 + Tailwind |
| [`video-collection-app`](./video-collection-app) | 跨端客户端（对齐 Web 视觉与接口） | Flutter |
| `bllii-brand-kit` | 品牌素材包 | — |
| `tools` | 品牌资源同步等脚本 | Python |

各子项目还有独立 README，细节以子目录文档为准。

---

## 架构关系

```text
                    ┌─────────────────────┐
                    │ video-collection-api │
                    │   Go REST + OpenAPI  │
                    └──────────┬──────────┘
           ┌───────────────────┼───────────────────┐
           ▼                   ▼                   ▼
  video-collection-web  video-collection-admin  video-collection-app
     Astro 门户              Vue 后台               Flutter 客户端
```

- API 默认监听 `PORT`（未设置时为 `80`），文档：`/docs`、`/redoc`、`/openapi.json`
- Web / Admin / App 均对接同一后端；未配置 PostgreSQL 时 API 可降级到本地 SQLite

---

## 环境要求

按需安装（一键启动脚本会先检查，缺失时给出安装提示）：

- **Go**（api）
- **Node.js**（web、admin）；**pnpm** 缺失时脚本会尝试 `corepack` / `npm i -g pnpm`
- **Flutter SDK**（app，含目标平台工具链）
- 可选：**PostgreSQL**（生产库）；本地可直接用 SQLite

项目依赖（`node_modules` / `go mod` / `flutter pub`）在首次启动时由脚本自动拉取，一般无需手动安装。

---

## 一键启动

跨平台启动器：Windows 用 `run.ps1` / `run.cmd`，macOS / Linux 用 `run.sh`。参数相同。

**所有服务在当前这一个终端里并行运行**，日志带 `[api]` / `[admin]` / `[web]` / `[app]` 前缀；按 **Ctrl+C** 一次停掉全部。Windows 下脚本会自动 `chcp 65001` 并按 UTF-8 读取子进程输出，避免中文乱码。

启动前会：

1. 检查本机是否具备 go / node / pnpm / flutter（按所选目标）
2. 缺少运行时 → 打印安装方式并中止
3. 缺少项目依赖 → 自动 `go mod download` / `pnpm install` / `flutter pub get`
4. 在同一终端并行启动所选服务

### Windows

```powershell
.\run.ps1 help
.\run.ps1 admin web windows
.\run.ps1 api admin web android
.\run.ps1 all
.\run.ps1 all chrome
.\run.ps1 web
```

也可用 `.\run.cmd ...`。

### macOS / Linux

```bash
chmod +x run.sh          # 首次
./run.sh help
./run.sh admin web macos # macOS
./run.sh admin web linux # Linux
./run.sh api admin web android
./run.sh all
./run.sh all chrome
./run.sh web
```

App 未指定平台时默认：Windows → `windows`，macOS → `macos`，Linux → `linux`。

| 参数 | 含义 |
|------|------|
| `api` | Go 后端 `go run .` |
| `admin` | 管理后台 `pnpm dev` |
| `web` | Astro 门户 `pnpm start` |
| `app` | Flutter（未指定平台时用本机默认） |
| `all` | api + admin + web + app |
| `windows` / `android` / `ios` / `macos` / `linux` / `chrome` / `edge` / `web-server` | 启动 Flutter 对应平台 |

说明：`web` 指 Astro 门户；Flutter Web 请用 `chrome` / `edge` / `web-server`。
---

## 单独启动（可选）

```powershell
# API
cd video-collection-api
go run .

# Admin
cd video-collection-admin
pnpm dev

# Web
cd video-collection-web
pnpm start

# App（示例：Windows）
cd video-collection-app
flutter run -d windows
```

---

## 品牌与素材

Web / App 共用 `bllii-brand-kit` 视觉体系。更新素材后可在仓库根目录同步客户端资源与各平台图标：

```powershell
python tools/sync_brand_assets.py
```

改版说明见 [`BRAND_REDESIGN.md`](./BRAND_REDESIGN.md)。

---

## 文档索引

- [API](./video-collection-api/README.md) — 采集协议、存储、OpenAPI、部署
- [Admin](./video-collection-admin/README.md) — 后台模块与对接接口
- [App](./video-collection-app/README.md) — Flutter 运行与构建
- [品牌改版](./BRAND_REDESIGN.md)
