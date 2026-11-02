FROM node:22-bookworm-slim AS build
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@10.11.0 --activate
COPY video-collection-web/package.json video-collection-web/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY video-collection-web/ ./
RUN pnpm build

FROM node:22-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production HOST=0.0.0.0 PORT=4321
COPY --from=build --chown=node:node /app/dist ./dist
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/package.json ./package.json
USER node
EXPOSE 4321
CMD ["node", "dist/server/entry.mjs"]
