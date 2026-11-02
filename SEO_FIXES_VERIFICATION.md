# SEO/GEO 修复验证文档

本文档说明了 Bllii 公开站点（Astro 应用）SEO/GEO 修复的实现细节和验证方法。

## 架构说明

Bllii 系统包含两个独立的 Web 应用：

1. **公开站点** (`video-collection-web`): Astro SSR 应用，服务于 `https://bllii.com`
   - 处理所有公开页面的 SEO 路由：`/sitemap.xml`, `/robots.txt`, `/llms.txt`
   - 本次修复的主要目标

2. **管理后台** (`video-collection-service/web/admin`): Vue 3 SPA，服务于 `https://john-admin.bllii.com`
   - 内嵌在 Go service 中
   - 本次添加了 noindex 保护

## 修复内容

### 1. ✅ Sitemap 覆盖率扩展 (Astro)

**问题**：
生产环境 `https://bllii.com/sitemap.xml` 仅包含约 24 个 URL / 18 个视频条目，原因是代码只获取第一页的 300 条数据。

**根本原因**：
```typescript
// 旧代码 - 只获取第一页
const res = await getVideos({ page: 1, pageSize: 300 });
```

**修复** (`video-collection-web/src/pages/sitemap.xml.ts`)：
- 实现分页循环获取所有视频
- 每页 100 条，最多 50 页（5000 条视频）
- 检查 `total` 和返回的数据量来判断是否还有更多数据
- 添加日志输出实际获取的视频数量

```typescript
// 新代码 - 分页获取所有视频
const pageSize = 100;
const maxPages = 50;
let page = 1;
let hasMore = true;

while (hasMore && page <= maxPages) {
  const res = await getVideos({ page, pageSize });
  // ... 处理数据
  if (videoPages.length >= total || res.list.length < pageSize) {
    hasMore = false;
  } else {
    page++;
  }
}
```

**Google Video 扩展**：
保留现有的 Google Video 扩展元数据：
- `<video:thumbnail_loc>` - 缩略图 URL
- `<video:title>` - 视频标题（使用 CDATA）
- `<video:description>` - 视频描述（使用 CDATA）
- `<video:player_loc>` - 播放器位置

### 2. ✅ `.well-known/llms.txt` 路由 (Astro)

**问题**：
生产环境 `/.well-known/llms.txt` 返回 404。

**修复**：
创建 `video-collection-web/src/pages/.well-known/llms.txt.ts`，重导出根路径的 `llms.txt`：

```typescript
// 重导出 llms.txt 内容到 .well-known/llms.txt
export { GET } from '../llms.txt';
```

现在两个路径都可用：
- `/llms.txt` - 原有路径
- `/.well-known/llms.txt` - 标准路径

### 3. ✅ 管理后台 noindex (Go Service)

**问题**：
公开访问的管理后台 `john-admin.bllii.com` 没有 robots noindex 标记。

**修复**：

**客户端元标签** (`video-collection-service/web/admin/src/bootstrap.ts`)：
```javascript
const robots = document.createElement('meta')
robots.name = 'robots'
robots.content = 'noindex,nofollow'
document.head.appendChild(robots)
```

**服务端响应头** (`video-collection-service/web/embed.go`)：
```go
// AdminHandler 添加 X-Robots-Tag
w.Header().Set("X-Robots-Tag", "noindex,nofollow")
```

双层保护确保搜索引擎不会索引管理后台。

### 4. ✅ robots.txt 保留 GEO 允许列表 (Astro)

**验证**：
现有的 `video-collection-web/src/pages/robots.txt.ts` 已包含完整的 GEO 允许列表：

```
# GEO / AI Search Bots (放行 AI 搜索引擎爬虫以优化 GEO 收录)
User-agent: GPTBot
Allow: /
User-agent: PerplexityBot
Allow: /
User-agent: ClaudeBot
Allow: /
User-agent: Applebot-Extended
Allow: /
User-agent: CCBot
Allow: /
```

无需修改。

### 5. ℹ️ www vs apex

**当前状态**：
- `getSiteOrigin()` 在 Astro 中动态获取站点域名
- 所有 sitemap 和 llms.txt 中的 URL 使用运行时域名
- 如果 www 子域名需要重定向，应在 Nginx/Cloudflare 层配置（不在此代码库范围内）

## 文件变更

### Astro 应用 (video-collection-web)
- 🔧 **修改** `src/pages/sitemap.xml.ts` - 分页获取所有视频
- ✨ **新增** `src/pages/.well-known/llms.txt.ts` - 重导出 llms.txt
- ✅ **保留** `src/pages/robots.txt.ts` - 已包含 GEO 允许列表
- ✅ **保留** `src/pages/llms.txt.ts` - 原有内容

### Go Service (video-collection-service)
- 🔧 **修改** `web/admin/src/bootstrap.ts` - 添加 robots meta 标签
- 🔧 **修改** `web/embed.go` - 添加 X-Robots-Tag 响应头

## 验证方法

### 本地测试 (Astro 应用)

1. **启动 Astro 开发服务器**：
```bash
cd video-collection-web
pnpm install
pnpm dev
```

2. **测试各个端点**：
```bash
# Sitemap (应包含大量视频)
curl http://localhost:4321/sitemap.xml | grep -c "<url>"

# .well-known/llms.txt
curl http://localhost:4321/.well-known/llms.txt

# llms.txt (应与上面相同)
curl http://localhost:4321/llms.txt

# robots.txt (检查 GEO 允许列表)
curl http://localhost:4321/robots.txt
```

### 生产测试 (部署后)

```bash
# 测试公开站点 SEO 端点
curl -I https://bllii.com/sitemap.xml
curl -I https://bllii.com/.well-known/llms.txt
curl https://bllii.com/robots.txt

# 测试管理后台 noindex
curl -I https://john-admin.bllii.com/admin
# 应包含: X-Robots-Tag: noindex,nofollow

# 检查 HTML meta 标签
curl https://john-admin.bllii.com/admin | grep -i "robots"
# 应包含: <meta name="robots" content="noindex,nofollow">
```

### Google Search Console 验证

1. **提交 sitemap**：
   - 访问 Google Search Console
   - 添加新的 sitemap URL: `https://bllii.com/sitemap.xml`
   - 等待 Google 抓取并验证

2. **检查索引覆盖率**：
   - 查看"索引">"Sitemap"报告
   - 验证提交的 URL 数量是否接近实际视频数量

3. **Rich Results Test**：
   - 使用 [Google Rich Results Test](https://search.google.com/test/rich-results)
   - 测试任意视频详情页 URL
   - 验证 Video 结构化数据是否被正确识别

## 关键实现细节

### Sitemap 分页逻辑

```typescript
// 从 video-collection-web/src/pages/sitemap.xml.ts
const pageSize = 100;
const maxPages = 50; // 最多获取 5000 条视频
let page = 1;
let hasMore = true;

while (hasMore && page <= maxPages) {
  const res = await getVideos({ page, pageSize });
  if (res && res.list && res.list.length > 0) {
    // 处理视频数据...
    videoPages.push(...videos);

    // 检查是否还有更多数据
    const total = res.total || 0;
    if (videoPages.length >= total || res.list.length < pageSize) {
      hasMore = false;
    } else {
      page++;
    }
  } else {
    hasMore = false;
  }
}

console.log(`[Sitemap] 成功获取 ${videoPages.length} 个视频页面`);
```

### API 响应结构假设

代码假设 `getVideos()` 返回：
```typescript
{
  list: VideoItem[],  // 视频列表
  total: number       // 总数量
}
```

如果实际 API 响应结构不同，需要相应调整：
- 如果没有 `total` 字段，只能依赖 `list.length < pageSize` 判断
- 如果字段名不同（如 `data`、`items`），需要修改代码

## 部署清单

### Astro 应用 (video-collection-web)
- [x] 修复 `src/pages/sitemap.xml.ts` - 分页获取所有视频
- [x] 添加 `src/pages/.well-known/llms.txt.ts` - 重导出路由
- [x] 验证 `src/pages/robots.txt.ts` - GEO 允许列表完整

### Go Service (video-collection-service)
- [x] `web/admin/src/bootstrap.ts` - robots meta 标签
- [x] `web/embed.go` - X-Robots-Tag 响应头

## 潜在问题与解决方案

### 1. Sitemap 生成超时

**问题**：如果视频数量很大，分页获取可能超时。

**解决方案**：
- 调整 `maxPages` 限制（当前 50 页 = 5000 条）
- 增加 Astro SSR 超时配置
- 考虑实现 Sitemap Index + 分片 sitemap

### 2. API 速率限制

**问题**：快速连续请求可能触发 API 速率限制。

**解决方案**：
- 在循环中添加延迟：`await new Promise(r => setTimeout(r, 100))`
- 缓存 sitemap 结果（当前已有 1 小时缓存）

### 3. 内存消耗

**问题**：大量视频数据可能导致内存问题。

**解决方案**：
- 当前限制 5000 条已足够大多数场景
- 如需更多，考虑流式生成 XML 而不是全部加载到内存

## 后续改进建议

1. **Sitemap Index**：
   - 如果视频数量超过 5000，实现 sitemap 分片
   - `/sitemap_index.xml` 索引多个分片 sitemap

2. **增量更新**：
   - 只在内容变化时重新生成 sitemap
   - 使用 Redis 缓存或文件系统缓存

3. **监控和告警**：
   - 记录每次 sitemap 生成的视频数量
   - 如果数量突然下降，发送告警

4. **自动提交**：
   - 内容更新后自动 ping Google/Bing
   - 使用 Search Console API 自动提交

## 与 Go Service SEO 路由的区别

**重要**：本次修复不依赖 Go service 中的 SEO 路由。

- Nginx 配置将 bllii.com 的流量路由到 Astro 应用（blliiweb）
- Go service 主要提供 API 和管理后台
- `/sitemap.xml`, `/robots.txt`, `/llms.txt` 在 bllii.com 上由 Astro 处理
- 管理后台的 noindex 由 Go service 提供

## 测试建议

在合并前：
1. 在测试环境部署 Astro 应用
2. 验证 sitemap 包含预期数量的 URL
3. 使用 Google Search Console 验证 sitemap
4. 检查管理后台的 noindex 标记
5. 确认 www 和 apex 域名都能正常访问（如果适用）
