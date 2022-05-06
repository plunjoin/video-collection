# 部署与维护

本目录提供 API、PostgreSQL、Web SSR 和管理后台的 Docker Compose 部署。Flutter 客户端独立发布，构建步骤见 `video-collection-app/README.md`。

## Docker Compose

需要 Docker Engine / Docker Desktop（Linux 容器）和 Compose v2。以下命令在仓库根目录执行。

1. 复制环境示例并修改两处密码，数据库密码和管理员密码使用不同的随机字符串。

```bash
cp deploy/.env.example deploy/.env
# Windows PowerShell：Copy-Item deploy/.env.example deploy/.env
```

2. 验证配置并构建启动。

```bash
docker compose --env-file deploy/.env config --quiet
docker compose --env-file deploy/.env up -d --build
docker compose --env-file deploy/.env ps
docker compose --env-file deploy/.env logs --tail=100 api web admin
```

默认入口为 `http://127.0.0.1:4321`（门户）、`http://127.0.0.1:3000`（后台）。管理员用户名为 `admin`，密码为环境文件中的 `ADMIN_INITIAL_PASSWORD`。该变量仅对空数据库首次初始化有效，修改变量不会重置既有账号。

API 和数据库仅在 Compose 内部网络开放。Web 服务端使用 `INTERNAL_API_URL=http://api:8080`，浏览器使用同源 `/api`；后台 Nginx 将 `/api` 转发到 API。不要将容器名 `api` 配到浏览器的 `PUBLIC_API_URL`。端口可通过 `WEB_PORT`、`ADMIN_PORT` 修改。

默认绑定本机回环地址，适合宿主机上的 HTTPS 反向代理。局域网测试可将 `BIND_ADDRESS` 改为 `0.0.0.0` 后重新执行 `up -d`。生产入口配置见下面的 Nginx 示例。

## 域名与 HTTPS

将 `deploy/nginx-site.conf.example` 中的门户域名和后台域名换成实际域名，放入宿主机 Nginx 的站点配置。示例对应默认端口；修改 Compose 端口时同时修改 `proxy_pass`。

```bash
sudo nginx -t
sudo systemctl reload nginx
# 安装好 Certbot 与 Nginx 插件后，为两个域名申请证书及 HTTPS 重定向
sudo certbot --nginx -d video.example.com -d admin.example.com
```

后台 `http://127.0.0.1:3000/docs` 提供 API 文档，`/openapi.json` 可导入接口工具。Flutter 真机连接填写可访问的 HTTPS 门户域名，同源 `/api` 会转发到后端。播放列表仍由客户端直接读取，源站需满足客户端网络与跨域要求。

## 配置采集规则

进入后台“采集点”→“新增节点”，选择模板并填写接口地址。MacCMS JSON / XML、RSS / Atom 和通用 REST JSON 都是模板。

请求头、固定参数、请求方法、分页参数、响应字段、清洗及分类绑定都可以在后台保存。先测试样本，再按配置采集，最后开启全局调度。模板配置格式和接口说明见 [采集规则文档](../video-collection-api/docs/collection-rules.md)。网页、数据库、Excel / CSV 使用“采集规则工作台”。

`video-collection-api/config` 以只读挂载方式提供给容器。修改宿主机 `collection_templates.yaml` 后，刷新后台即可读取新模板；现有明确保存的规则副本不会自动改变。`collector_rules.yaml` 中的来源仅在业务库没有任何采集源时导入，日常修改请通过后台保存。

## 数据与备份

Compose 使用命名卷保存 PostgreSQL 数据、上传文件、应用备份、播放器及主题。应用备份位于 API 的 `/app/data/backups`，上传文件位于 `/app/data/collection-uploads`。规则本身保存到业务数据库；模板文件在仓库配置目录。

可在后台“数据库管理”创建和下载应用 JSON 备份。升级前同时备份数据库、模板和文件卷。例如用 `pg_dump` 生成 PostgreSQL 逻辑备份：

```bash
docker compose --env-file deploy/.env exec -T postgres pg_dump -U video -d videodb -Fc -f /tmp/videodb.dump
docker compose --env-file deploy/.env cp postgres:/tmp/videodb.dump ./videodb.dump
docker compose --env-file deploy/.env cp api:/app/data ./api-data-backup
docker compose --env-file deploy/.env cp api:/app/players ./api-players-backup
docker compose --env-file deploy/.env cp api:/app/themes ./api-themes-backup
```

Windows 也使用上述 `cp` 命令，避免通过旧版 PowerShell 的文本重定向保存二进制备份。

恢复数据库前先停止 Web、后台和 API，保留 PostgreSQL：

```bash
docker compose --env-file deploy/.env stop web admin api
docker compose --env-file deploy/.env cp ./videodb.dump postgres:/tmp/videodb.dump
docker compose --env-file deploy/.env exec -T postgres pg_restore -U video -d videodb --clean --if-exists --no-owner /tmp/videodb.dump
docker compose --env-file deploy/.env up -d
```

恢复命令会替换备份中对应的数据库对象，应先为当前状态做备份。文件卷另行从对应文件备份恢复。普通 `docker compose down` 保留命名卷；不要在保留数据的部署上使用 `down -v`。

## 更新与排障

更新源码后执行 `docker compose --env-file deploy/.env up -d --build`。回滚到旧版本前检查数据库结构兼容性，必要时同时恢复升级前备份。

- API 不健康：查看 API / PostgreSQL 日志和 `pg_isready`。生产配置启用了 `DB_REQUIRE_PRIMARY=true`，PostgreSQL 故障时 API 会退出并重启，避免将新数据写到另一套 SQLite 数据库。
- 检查 API 与数据库健康：`docker compose --env-file deploy/.env exec api wget -qO- http://127.0.0.1:8080/healthz`；健康返回 `{"status":"ok"}`，数据库不可用返回 HTTP 503。
- 后台刷新页面 404：使用提供的 Nginx SPA 配置，`try_files` 必须回退到 `index.html`。
- 上传 413 / 超时：应用限制为 20 MB；代理允许 25 MB，请求超时为 90 秒。
- 采集没有数据：先检查样本、列表路径和字段映射，再看调度日志；空数组会结束采集，错误映射会报错。
- 更新密码环境变量后无法登录：初始密码只在空数据库生效；既有密码在用户管理中修改。

目前会话、采集运行状态和日志位于单个 API 进程内存中。重启会清空会话和运行状态；已入库记录保留，重启后可重新采集。按单个 API 实例部署，暂不支持多个副本共享采集锁或会话。

## 不使用 Docker

安装 Go 1.26+、Node.js 22 LTS 和 pnpm；PostgreSQL 可独立部署。API 在 `video-collection-api` 内执行 `go build -o video-collection-api .`，运行时保持工作目录及 `config`、`players`、`themes`、`data` 可用。通过 `.env` 设置 `PORT=8080`、数据库地址、`DB_REQUIRE_PRIMARY=true` 和初始管理员密码。

Web 在其目录执行 `pnpm install --frozen-lockfile && pnpm build`，随后用 `HOST=0.0.0.0 PORT=4321 INTERNAL_API_URL=http://127.0.0.1:8080 node dist/server/entry.mjs` 启动。PowerShell 先分别设置 `$env:HOST`、`$env:PORT`、`$env:INTERNAL_API_URL`。

Admin 执行 `pnpm install --frozen-lockfile && pnpm build`，将 `dist` 交给 Nginx，并将 `deploy/nginx-admin.conf` 中的 `api:8080` 改为实际 API 地址。使用 systemd 等进程管理器运行 API / Web，工作目录必须对应子项目目录。

本次配置已通过 Compose 配置校验与本地 Go / 前端构建验证；当前开发环境 Docker 守护进程未运行，容器镜像构建和容器间联通仍需在部署主机执行上面的启动与健康检查。
