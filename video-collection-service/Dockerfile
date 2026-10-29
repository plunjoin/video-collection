# ============================================================================
// video-collection-service 合并镜像：Go 二进制 + go:embed 内嵌管理后台 SPA 与前台门户
//
// 相比旧的「api + admin(nginx) + web(Node)」多容方案：
//   - 管理后台由 Go 直接托管（/admin），去掉 nginx 容器与静态分发环节；
//   - 前台门户由 webfront 引擎托管（/，SSR + SPA），wf 纯 Go 构建零 Node；
//   - 前端依赖统一在 web/ 工作区（pnpm workspace，hoisted 单份 node_modules）。
// ============================================================================
# 前端工作区：一次 pnpm install 同时满足 admin(Vite) 与 portal(esbuild) 的依赖解析
FROM node:22-bookworm-slim AS web-deps
WORKDIR /web
COPY video-collection-service/web/package.json web/pnpm-workspace.yaml web/.npmrc ./
COPY video-collection-service/web/admin/package.json ./admin/
COPY video-collection-service/web/portal/package.json ./portal/
RUN corepack enable && corepack prepare pnpm@10.11.0 --activate \
    && pnpm install --frozen-lockfile=false

# 管理后台（Vue 3 + Vite）构建
FROM web-deps AS admin-build
WORKDIR /web
COPY video-collection-service/web/admin/ ./admin/
RUN pnpm --filter video-collection-service-admin build

# 前台门户（React + webfront）：wf 纯 Go 构建，依赖解析复用工作区 node_modules
FROM golang:1.26-bookworm AS portal-build
WORKDIR /src
RUN go install github.com/plunjoin/webfront/cmd/wf@v0.0.1
COPY video-collection-service/web/portal/ ./web/portal/
COPY --from=web-deps /web/node_modules ./web/node_modules
RUN /go/bin/wf build ./web/portal

FROM golang:1.26-bookworm AS build
WORKDIR /src
# 构建上下文只带 video-collection-service/，没有 .git，Go 无法自动写入 VCS 信息。
# 这里显式注入版本号，启动日志与 /status 就能看出跑的是哪次构建。
ARG BUILD_VERSION=""
COPY video-collection-service/go.mod video-collection-service/go.sum ./
RUN go mod download
COPY video-collection-service/ ./
# 用容器内构建出的前端产物覆盖仓库占位 dist，保证 go:embed 打包最新后台与门户
COPY --from=admin-build /web/admin/dist ./web/admin/dist
COPY --from=portal-build /src/web/portal/dist ./web/portal/dist
RUN CGO_ENABLED=0 go build -trimpath \
    -ldflags="-s -w -X video-collection-service/config.buildVersion=${BUILD_VERSION}" \
    -o /out/service .

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates wget tzdata && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 10001 --create-home app
WORKDIR /app
COPY --from=build /out/service ./service
COPY --from=build /src/config ./config
COPY --from=build /src/players ./players
RUN mkdir -p data themes backups && chown -R app:app /app
USER app
ENV PORT=8080
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
CMD ["./service"]
