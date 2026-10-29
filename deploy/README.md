# 部署与维护

本目录提供统一服务的 Docker Compose 部署：单个 Go 容器同时托管 RESTful API、管理后台（/admin）与用户门户（/，webfront SSR/SPA，go:embed 内嵌）。Flutter 客户端独立发布，构建步骤见 `video-collection-app/README.md`。

自「video-collection-service」合并版起，原 API、管理后台、Web 门户三个容器已合并为一个 Go 服务：管理后台 SPA 与门户前端均经 `go:embed` 打进二进制，分别由服务直接托管在 `/admin` 与 `/`，不再需要 Nginx 与 Node 容器。

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
docker compose --env-file deploy/.env logs --tail=100 service
```

默认入口为 `http://127.0.0.1:8080/`（门户，webfront 托管）与 `http://127.0.0.1:8080/admin`（管理后台），端口由 `API_PORT` 控制。管理员用户名为 `admin`，密码为环境文件中的 `ADMIN_INITIAL_PASSWORD`。该变量仅对空数据库首次初始化有效，修改变量不会重置既有账号。

统一服务和数据库仅在 Compose 内部网络开放（8080 通过 `API_PORT` 映射到宿主机，供门户、/admin、/api、/docs 使用）。浏览器与门户同源取数，无需跨域配置。默认绑定本机回环地址，适合宿主机上的 HTTPS 反向代理；局域网测试可将 `BIND_ADDRESS` 改为 `0.0.0.0`。

默认绑定本机回环地址，适合宿主机上的 HTTPS 反向代理。局域网测试可将 `BIND_ADDRESS` 改为 `0.0.0.0` 后重新执行 `up -d`。生产入口配置见下面的 Nginx 示例。

## 域名与 HTTPS

将 `deploy/nginx-site.conf.example` 中的门户域名和后台域名换成实际域名，放入宿主机 Nginx 的站点配置。示例对应默认端口；修改 Compose 端口时同时修改 `proxy_pass`。

```bash
sudo nginx -t
sudo systemctl reload nginx
# 安装好 Certbot 与 Nginx 插件后，为两个域名申请证书及 HTTPS 重定向
sudo certbot --nginx -d video.example.com -d admin.example.com   # 后台与 API 同端口，admin 域名代理到统一服务的 /admin
```

后台 `http://127.0.0.1:8080/admin` 提供管理界面，`/docs` 提供 API 文档，`/openapi.json` 可导入接口工具。Flutter 真机连接填写可访问的 HTTPS 门户域名，同源 `/api` 会转发到后端。播放列表仍由客户端直接读取，源站需满足客户端网络与跨域要求。

## 配置采集规则

进入后台“采集点”→“新增节点”，选择模板并填写接口地址。网络视频 JSON / XML、RSS / Atom 和通用 REST JSON 都是模板。

请求头、固定参数、请求方法、分页参数、响应字段、清洗及分类绑定都可以在后台保存。先测试样本，再按配置采集，最后开启全局调度。模板配置格式和接口说明见 [采集规则文档](../video-collection-service/docs/collection-rules.md)。网页、数据库、Excel / CSV 使用“采集规则工作台”。

`video-collection-service/config` 以只读挂载方式提供给容器。修改宿主机 `collection_templates.yaml` 后，刷新后台即可读取新模板；现有明确保存的规则副本不会自动改变。`collector_rules.yaml` 中的来源仅在业务库没有任何采集源时导入，日常修改请通过后台保存。

## 账号、审核及积分功能升级

启动 API 自动创建审核、钱包流水、签到日活、求片和装扮相关表，无需手工执行 SQL。空库初始 `admin` 角色为 `super_admin`；旧库仅在首次迁移时将名为 `admin` 且原角色为 `admin` 的引导账号升级为超管，不会将所有管理员提升权限。如果旧库已删除/改名引导账号且没有超管，请部署维护人员在升级前确认并指定一个可信超管（数据库中更新其 role 为 `super_admin`），避免无法分配员工权限。

升级前完成完整数据库备份，启动后用超管检查“用户账号管理”“内容审核中心”“日活 / 积分 / 装扮”和“消息通知”。Web `/points`、App“我的 → 同好成长站 / 消息”为用户入口。默认规则、权限矩阵和使用流程见 [账号、审核与积分运营](../video-collection-service/docs/community-operations.md)。本地没有外部配置时初始密码仍为开发默认值；生产使用 `ADMIN_INITIAL_PASSWORD`。

成长站升级会自动创建任务、等级、心愿公开设置与助力表；已有安装也会执行本次迁移。默认任务只初始化一次，不覆盖后台修改；等级初始数据按缺失项补齐。历史求片仍为私密，只有本人主动公开的未完成心愿进入公共心愿墙。上线后检查任务奖励配置、用户任务领取及公开/收回心愿流程。


接入 Redis（compose 默认已包含，并注入 `REDIS_ADDR=redis:6379`）后，登录会话改由 radix 托管，多副本部署与重启免登录均可支持；未配置 `REDIS_ADDR` 时自动降级为进程内存会话。公开读接口（视频列表/详情、分类、排行榜、最近更新、站点配置、播放器）启用 Redis 缓存，管理端写操作后自动失效。审核、库存及积分均持久化，重启不会重复发奖。回滚服务前应先恢复升级前的完整备份，新角色无法由旧版正确识别。

## 数据与备份

Compose 使用命名卷保存 PostgreSQL 数据、上传文件、应用备份、播放器及主题。应用备份位于 API 的 `/app/data/backups`，上传文件位于 `/app/data/collection-uploads`。规则本身保存到业务数据库；模板文件在仓库配置目录。

可在后台“数据库管理”创建和下载应用 JSON 备份。升级前同时备份数据库、模板和文件卷。例如用 `pg_dump` 生成 PostgreSQL 逻辑备份：

```bash
docker compose --env-file deploy/.env exec -T postgres pg_dump -U video -d videodb -Fc -f /tmp/videodb.dump
docker compose --env-file deploy/.env cp postgres:/tmp/videodb.dump ./videodb.dump
docker compose --env-file deploy/.env cp service:/app/data ./api-data-backup
docker compose --env-file deploy/.env cp service:/app/players ./api-players-backup
docker compose --env-file deploy/.env cp service:/app/themes ./api-themes-backup
```

Windows 也使用上述 `cp` 命令，避免通过旧版 PowerShell 的文本重定向保存二进制备份。

恢复数据库前先停止 Web、后台和 API，保留 PostgreSQL：

```bash
docker compose --env-file deploy/.env stop service
docker compose --env-file deploy/.env cp ./videodb.dump postgres:/tmp/videodb.dump
docker compose --env-file deploy/.env exec -T postgres pg_restore -U video -d videodb --clean --if-exists --no-owner /tmp/videodb.dump
docker compose --env-file deploy/.env up -d
```

恢复命令会替换备份中对应的数据库对象，应先为当前状态做备份。文件卷另行从对应文件备份恢复。普通 `docker compose down` 保留命名卷；不要在保留数据的部署上使用 `down -v`。

## 更新与排障

更新源码后执行 `docker compose --env-file deploy/.env up -d --build`。回滚到旧版本前检查数据库结构兼容性，必要时同时恢复升级前备份。

- API 不健康：查看 API / PostgreSQL 日志和 `pg_isready`。生产配置启用了 `DB_REQUIRE_PRIMARY=true`，PostgreSQL 故障时 API 会退出并重启，避免将新数据写到另一套 SQLite 数据库。
- 检查服务与数据库健康：`docker compose --env-file deploy/.env exec service wget -qO- http://127.0.0.1:8080/healthz`；健康返回 `{"status":"ok"}`，数据库不可用返回 HTTP 503。
- 后台刷新页面 404：Go 托管 SPA 已内置 history 回退，若经过自建反代，请确认未拦截 `/admin/*` 的 fallback。
- 上传 413 / 超时：应用限制为 20 MB；代理允许 25 MB，请求超时为 90 秒。
- 采集没有数据：先检查样本、列表路径和字段映射，再看调度日志；空数组会结束采集，错误映射会报错。
- 更新密码环境变量后无法登录：初始密码只在空数据库生效；既有密码在用户管理中修改。

采集运行状态和审计日志位于进程内存（重启清空，已入库记录保留）。接入 Redis 后会话可跨副本共享；未接入时按单实例部署。

## 不使用 Docker

安装 Go 1.26+、Node.js 22 LTS 和 pnpm；PostgreSQL 可独立部署。在 `video-collection-service` 内先构建管理后台再编译服务：

```bash
cd video-collection-service/web/admin && pnpm install --frozen-lockfile && pnpm build
cd ../.. && go build -o video-collection-service .
```

管理后台 `dist` 由 `go:embed` 打进二进制，运行时保持工作目录及 `config`、`players`、`themes`、`data` 可用。通过 `.env` 设置 `PORT=8080`、数据库地址、`DB_REQUIRE_PRIMARY=true`、初始管理员密码，以及可选的 `REDIS_ADDR` 等缓存配置。

门户（web/portal）构建用仓库根 `wf build video-collection-service/web/portal`（纯 Go，零 Node；依赖由 `web/` 工作区提供）；构建产物经 `go:embed` 随服务分发，无需单独启动 Node 进程。

管理后台不再独立分发：构建 `web/admin` 后由统一服务托管 `/admin`。使用 systemd 等进程管理器运行服务与 Web，工作目录必须对应子项目目录。

本次配置已通过 Compose 配置校验与本地 Go / 前端构建验证；当前开发环境 Docker 守护进程未运行，容器镜像构建和容器间联通仍需在部署主机执行上面的启动与健康检查。
