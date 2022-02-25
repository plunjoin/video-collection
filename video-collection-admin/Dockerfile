FROM node:22-bookworm-slim AS build
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@10.11.0 --activate
COPY video-collection-admin/package.json video-collection-admin/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY video-collection-admin/ ./
RUN pnpm build

FROM nginx:1.28-alpine
COPY deploy/nginx-admin.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
