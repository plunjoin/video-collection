# ============================================================================
// video-collection-service 合并镜像：Go 二进制 + go:embed 内嵌管理后台 SPA
//
// 相比旧的「api + admin(nginx)」双容方案：
//   - 管理后台由 Go 直接托管（/admin），去掉 nginx 容器与静态分发环节；
//   - Redis(radix) 作为可选依赖，提供分布式会话与公开读接口缓存。
// ============================================================================
FROM node:22-bookworm-slim AS web-build
WORKDIR /web
COPY video-collection-service/web/admin/package.json video-collection-service/web/admin/pnpm-lock.yaml ./
RUN corepack enable && corepack prepare pnpm@10.11.0 --activate \
    && pnpm install --frozen-lockfile
COPY video-collection-service/web/admin/ ./
RUN pnpm build

FROM golang:1.26-bookworm AS build
WORKDIR /src
# 构建上下文只带 video-collection-service/，没有 .git，Go 无法自动写入 VCS 信息。
# 这里显式注入版本号，启动日志与 /status 就能看出跑的是哪次构建。
ARG BUILD_VERSION=""
COPY video-collection-service/go.mod video-collection-service/go.sum ./
RUN go mod download
COPY video-collection-service/ ./
# 用容器内构建出的前端产物覆盖仓库占位 dist，保证 go:embed 打包最新后台
COPY --from=web-build /web/dist ./web/admin/dist
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
