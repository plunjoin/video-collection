# ============================================================================
// video-collection-service 合并镜像：Go 二进制 + go:embed 内嵌管理后台 SPA 与前台门户
//
// 相比旧的「api + admin(nginx) + web(Node)」多容方案：
//   - 管理后台由 Go 直接托管（/admin），去掉 nginx 容器与静态分发环节；
//   - 前台门户由 webfront 引擎托管（/，SSR + SPA）；
//   - 双前端统一由 wf CLI 构建（esbuild 内核，纯 Go），镜像内没有 Node。
// ============================================================================
# 前端构建：wf install（按 web/package-lock.json 物料化版本化 store）+ wf build 双前端
FROM golang:1.26-bookworm AS web-build
WORKDIR /src
RUN go install github.com/plunjoin/webfront/cmd/wf@v0.1.0
COPY video-collection-service/web/package-lock.json video-collection-service/web/package.json ./web/
COPY video-collection-service/web/admin/ ./web/admin/
COPY video-collection-service/web/portal/ ./web/portal/
RUN wf install -modules wf_modules web \
    && wf build -mode spa -base /admin -modules ../wf_modules web/admin \
    && wf build -modules ../wf_modules web/portal

FROM golang:1.26-bookworm AS build
WORKDIR /src
# 构建上下文只带 video-collection-service/，没有 .git，Go 无法自动写入 VCS 信息。
# 这里显式注入版本号，启动日志与 /status 就能看出跑的是哪次构建。
ARG BUILD_VERSION=""
COPY video-collection-service/go.mod video-collection-service/go.sum ./
RUN go mod download
COPY video-collection-service/ ./
# 用容器内构建出的前端产物覆盖仓库占位 dist，保证 go:embed 打包最新后台与门户
COPY --from=web-build /src/web/admin/dist ./web/admin/dist
COPY --from=web-build /src/web/portal/dist ./web/portal/dist
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
