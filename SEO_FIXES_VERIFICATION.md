# SEO/GEO 修复验证文档

本文档说明了 Bllii 统一服务（Go + React Portal）SEO/GEO 修复的实现细节和验证方法。

## 架构说明

**当前架构**（2026-10-29 起）：
- **统一 Go 服务**：`video-collection-service` 整合了 API、管理后台和公开门户
- **公开门户**：React 18 + webfront，内嵌在 Go 服务中，通过 `go:embed` 打包
- **管理后台**：Vue 3 SPA，同样内嵌在 Go 服务中
- **部署**：单一 Go 容器托管 API + `/admin` + `/`（公开门户）

**已废弃**：
- 独立的 Astro/Node.js web 容器（已在 commit c0056f5 中删除）
- `video-collection-web` 目录（已移除）

**本次修复针对**：当前统一服务架构

---

## 修复内容

### 1. ✅ Sitemap 覆盖率扩展 (Go Service)

**问题**：
生产环境可能仍在运行旧的 Astro 镜像，导致 `https://bllii.com/sitemap.xml` 只包含约 24 个 URL / 18 个视频条目。

**修复** (`pkg/api/seo.go` + `main.go`)：
- 在统一服务中实现 `/sitemap.xml` 路由
- 实现分页获取所有视频的逻辑
- 每页 100 条，最多 50 页（5000 条视频）
- 添加完整的 Google Video 扩展元数据

```go
// 分页获取所有视频
func (srv *Server) getAllPublicVideos(ctx context.Context) ([]store.VideoRecord, error) {
    var allVideos []store.VideoRecord
    pageSize := 100
    maxPages := 50

    for page := 1; page <= maxPages; page++ {
        videos, total, err := srv.store.QueryVideos(ctx, store.VideoQuery{
            Page:      page,
            PageSize:  pageSize,
            OrderBy:   "id",
            OrderDesc: true,
        })
        
        allVideos = append(allVideos, videos...)
        
        if len(allVideos) >= total || len(videos) == 0 {
            break
        }
    }
    
    return allVideos, nil
}
```

**Google Video 扩展**：
每个视频 URL 包含完整的 Google Video 扩展元数据：
- `<video:thumbnail_loc>` - 缩略图 URL
- `<video:title>` - 视频标题
- `<video:description>` - 视频描述
- `<video:player_loc>` - 播放器位置
- `<video:publication_date>` - 发布日期
- `<video:family_friendly>` - 家庭友好标记

### 2. ✅ `.well-known/llms.txt` 路由 (Go Service)

**问题**：
生产环境 `/.well-known/llms.txt` 返回 404。

**修复** (`pkg/api/seo.go` + `main.go`)：
- 实现 `/llms.txt` 路由
- 实现 `/.well-known/llms.txt` 路由（两者指向同一个处理器）
- 动态生成内容，包括：
  - 平台简介和核心频道
  - 热门番剧示例（前 5 个）
  - API 文档链接

### 3. ✅ robots.txt 保留 GEO 允许列表 (Go Service)

**修复** (`pkg/api/seo.go` + `main.go`)：
- 实现 `/robots.txt` 路由
- 包含完整的 GEO 允许列表：
  - GPTBot, PerplexityBot, ClaudeBot
  - Applebot-Extended, CCBot
- 添加 Sitemap 引用：`Sitemap: https://bllii.com/sitemap.xml`

### 4. ✅ 管理后台 noindex (Go Service)

**问题**：
公开访问的管理后台 `john-admin.bllii.com` 没有 robots noindex 标记。

**修复**：

**客户端元标签** (`web/admin/src/bootstrap.ts`)：
```javascript
const robots = document.createElement('meta')
robots.name = 'robots'
robots.content = 'noindex,nofollow'
document.head.appendChild(robots)
```

**服务端响应头** (`web/embed.go`)：
```go
w.Header().Set("X-Robots-Tag", "noindex,nofollow")
```

双层保护确保搜索引擎不会索引管理后台。

---

## 文件变更

### Go Service (video-collection-service)
- ✨ **新增** `pkg/api/seo.go` - SEO 路由处理器（sitemap、robots.txt、llms.txt）
- 🔧 **修改** `main.go` - 在 portal handler 之前注册 SEO 路由
- 🔧 **修改** `web/admin/src/bootstrap.ts` - 添加 robots meta 标签
- 🔧 **修改** `web/embed.go` - 添加 X-Robots-Tag 响应头

### 文档
- 📝 **更新** `SEO_FIXES_VERIFICATION.md` - 完整的验证方法和测试建议

---

## 路由注册顺序

**关键**：SEO 路由必须在 portal handler 之前注册，因为 portal handler 使用 `mux.HandleFunc("/", ...)` 捕获所有根路径请求。

```go
// main.go 中的注册顺序
mux.HandleFunc("/healthz", ...)         // 健康检查
openapi.RegisterRoutes(mux)             // OpenAPI 文档
mux.Handle("/rss.xml", rssHandler)      // RSS 订阅
apiServer.RegisterRoutes(mux)           // /api/* 路由

// 公开站点 SEO 路由（必须在 portal 之前）
mux.HandleFunc("/sitemap.xml", apiServer.HandleSitemap)
mux.HandleFunc("/robots.txt", apiServer.HandleRobotsTxt)
mux.HandleFunc("/llms.txt", apiServer.HandleLLMsTxt)
mux.HandleFunc("/.well-known/llms.txt", apiServer.HandleLLMsTxt)

// 管理后台
mux.Handle("/admin", adminHandler)
mux.Handle("/admin/", adminHandler)

// 公开门户（捕获所有其他路径）
mux.HandleFunc("/", portalHandler)
```

---

## 验证方法

### 本地测试

1. **启动统一服务**：
```bash
cd video-collection-service
go run .
```

2. **测试各个端点**：
```bash
# Sitemap（应包含大量视频）
curl http://localhost:80/sitemap.xml | grep -c "<url>"

# .well-known/llms.txt
curl http://localhost:80/.well-known/llms.txt

# llms.txt（应与上面相同）
curl http://localhost:80/llms.txt

# robots.txt（检查 GEO 允许列表）
curl http://localhost:80/robots.txt

# 管理后台 noindex
curl -I http://localhost:80/admin | grep -i "x-robots-tag"
curl http://localhost:80/admin | grep -i '<meta name="robots"'
```

### 生产测试（部署后）

```bash
# 测试公开站点 SEO 端点
curl -I https://bllii.com/sitemap.xml
curl -I https://bllii.com/.well-known/llms.txt
curl https://bllii.com/robots.txt

# 检查 sitemap 中的 URL 数量
curl https://bllii.com/sitemap.xml | grep -c "<url>"

# 测试管理后台 noindex
curl -I https://john-admin.bllii.com/admin | grep -i "x-robots-tag"
curl https://john-admin.bllii.com/admin | grep -i "robots"
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

---

## 关键实现细节

### Sitemap 分页逻辑

```go
// 从 pkg/api/seo.go
func (srv *Server) getAllPublicVideos(ctx context.Context) ([]store.VideoRecord, error) {
    var allVideos []store.VideoRecord
    pageSize := 100
    maxPages := 50 // 最多获取 5000 条视频

    for page := 1; page <= maxPages; page++ {
        videos, total, err := srv.store.QueryVideos(ctx, store.VideoQuery{
            Page:      page,
            PageSize:  pageSize,
            OrderBy:   "id",
            OrderDesc: true,
        })
        
        if err != nil {
            return nil, err
        }

        allVideos = append(allVideos, videos...)

        // 如果已经获取了所有视频，或者这一页没有数据，退出循环
        if len(allVideos) >= total || len(videos) == 0 {
            break
        }
    }

    return allVideos, nil
}
```

### 站点域名配置

当前硬编码为 `https://bllii.com`。如需更改：
- 添加环境变量 `SITE_URL`
- 或从数据库配置读取
- 或从 `Request.Host` 推断（需要谨慎处理）

---

## 部署清单

### Go Service (video-collection-service)
- [x] `pkg/api/seo.go` - SEO 路由处理器
- [x] `main.go` - 注册 SEO 路由
- [x] `web/admin/src/bootstrap.ts` - robots meta 标签
- [x] `web/embed.go` - X-Robots-Tag 响应头

---

## 潜在问题与解决方案

### 1. Sitemap 生成超时

**问题**：如果视频数量很大，分页获取可能超时。

**解决方案**：
- 调整 `maxPages` 限制（当前 50 页 = 5000 条）
- 实现后台任务生成 sitemap 并缓存
- 考虑实现 Sitemap Index + 分片 sitemap

### 2. 内存消耗

**问题**：大量视频数据可能导致内存问题。

**解决方案**：
- 当前限制 5000 条已足够大多数场景
- 如需更多，考虑流式生成 XML 而不是全部加载到内存

### 3. 旧镜像仍在运行

**问题**：生产环境可能仍在运行旧的 Astro 镜像。

**解决方案**：
- 部署新的统一服务镜像
- 验证 Nginx/Cloudflare 配置指向新服务
- 监控日志确认新路由被调用

---

## 后续改进建议

1. **Sitemap Index**：
   - 如果视频数量超过 5000，实现 sitemap 分片
   - `/sitemap_index.xml` 索引多个分片 sitemap

2. **缓存优化**：
   - 使用 Redis 缓存 sitemap 结果（1 小时）
   - 只在内容变化时重新生成

3. **增量更新**：
   - 记录最后更新时间
   - 只包含最近更新的视频

4. **监控和告警**：
   - 记录每次 sitemap 生成的视频数量
   - 如果数量突然下降，发送告警

5. **自动提交**：
   - 内容更新后自动 ping Google/Bing
   - 使用 Search Console API 自动提交

---

## 与旧 Astro 应用的区别

**重要**：本次修复针对当前的统一服务架构（Go + React Portal）。

- 旧的 Astro 应用（`video-collection-web`）已在 2026-10-29 删除
- compose.yaml 明确说明独立的 Astro/Node web 容器已废弃移除
- 新架构中，所有路由（API、管理后台、公开门户、SEO）都由单一 Go 服务处理
- 如果生产环境仍显示 Astro 风格的 sitemap，那是因为旧镜像仍在运行
- 部署本 PR 后，将使用新的统一服务处理所有请求

---

## 测试建议

在合并前：
1. 在测试环境构建并部署统一服务
2. 验证 sitemap 包含预期数量的 URL
3. 确认所有 SEO 路由正常工作
4. 检查管理后台的 noindex 标记
5. 使用 Google Search Console 验证 sitemap

部署后：
1. 确认生产环境使用新镜像
2. 监控 sitemap 访问日志
3. 验证搜索引擎能正常抓取
4. 检查索引覆盖率是否提升
