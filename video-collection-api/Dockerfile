FROM golang:1.26-bookworm AS build
WORKDIR /src
COPY video-collection-api/go.mod video-collection-api/go.sum ./
RUN go mod download
COPY video-collection-api/ ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/api .

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates wget tzdata && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 10001 --create-home app
WORKDIR /app
COPY --from=build /out/api ./api
COPY --from=build /src/config ./config
COPY --from=build /src/players ./players
RUN mkdir -p data themes backups && chown -R app:app /app
USER app
ENV PORT=8080
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
CMD ["./api"]
