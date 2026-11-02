# SEO/GEO Fixes Verification

本文档说明了 SEO/GEO 修复的实现细节和验证方法。

## 1. Sitemap 覆盖率扩展

### 问题
生产环境 `https://bllii.com/sitemap.xml` 仅包含约 24 个 URL / 18 个视频条目，但代码意图支持约 300 个动漫 URL。

### 修复
创建了新的 SEO 处理器 (`pkg/api/seo.go`)，实现了以下功能：

- **分页获取所有视频**：`getAllPublicVideos()` 方法通过分页循环获取所有公开视频，每页 100 条，最多 50 页（5000 条视频）
- **Sitemap Index**：提供 `/sitemap_index.xml` 索引多个 sitemap
- **主 Sitemap**：`/sitemap.xml` 包含：
  - 静态页面（首页、分类、排行、最新）
  - 所有视频详情页（`/anime/:id`）
  - 所有播放页（`/play/:id`）
- **视频专用 Sitemap**：`/sitemap_videos.xml` 专门针对视频内容，包含 Google Video 扩展元数据
  - 缩略图 URL
  - 视频标题和描述
  - 播放器位置
  - 发布日期
  - 家庭友好标记

### Google Video 扩展
所有视频 URL 都包含完整的 Google Video 扩展元数据：
```xml
<video:video>
  <video:thumbnail_loc>图片URL</video:thumbnail_loc>
  <video:title>视频标题</video:title>
  <video:description>视频描述</video:description>
  <video:player_loc>播放器URL</video:player_loc>
  <video:publication_date>发布时间</video:publication_date>
  <video:family_friendly>yes</video:family_friendly>
</video:video>
```

### 验证方法
1. 启动服务后访问 `/sitemap.xml`
2. 检查 URL 数量（应包含静态页面 + 所有视频详情页 + 所有播放页）
3. 验证 Google Video 扩展是否存在
4. 访问 `/sitemap_index.xml` 查看索引
5. 访问 `/sitemap_videos.xml` 查看纯视频 sitemap

## 2. `.well-known/llms.txt` 路由

### 问题
生产环境 `/.well-known/llms.txt` 返回 404。

### 修复
在 SEO 路由中添加了：
- `/llms.txt` 路由
- `/.well-known/llms.txt` 路由（两者提供相同内容）

内容包括：
- 平台简介
- 主要功能
- 主要页面链接
- API 文档链接
- 热门番剧示例
- 技术栈信息

### 验证方法
1. 访问 `/.well-known/llms.txt`
2. 访问 `/llms.txt`
3. 确认两者返回相同的文本内容
4. 检查内容是否包含站点信息和示例链接

## 3. 管理后台 noindex

### 问题
公开访问的管理后台 `john-admin.bllii.com` 没有 robots noindex 标记。

### 修复
**客户端元标签**（`web/admin/src/bootstrap.ts`）：
```javascript
const robots = document.createElement('meta')
robots.name = 'robots'
robots.content = 'noindex,nofollow'
document.head.appendChild(robots)
```

**服务端响应头**（`web/embed.go`）：
```go
w.Header().Set("X-Robots-Tag", "noindex,nofollow")
```

### 验证方法
1. 访问 `/admin` 或 `/admin/` 路径
2. 检查 HTML 中是否包含 `<meta name="robots" content="noindex,nofollow">`
3. 检查 HTTP 响应头是否包含 `X-Robots-Tag: noindex,nofollow`
4. 使用浏览器开发者工具查看网络请求的响应头

## 4. robots.txt GEO 允许列表

### 问题
需要保留现有的 GEO Allows（GPTBot / PerplexityBot / ClaudeBot / Applebot-Extended / CCBot）。

### 修复
创建了 `/robots.txt` 路由，内容包括：
- User-agent: * Allow: /
- Sitemap 引用（sitemap.xml 和 sitemap_videos.xml）
- GEO 允许列表：
  - GPTBot
  - PerplexityBot
  - ClaudeBot
  - Applebot-Extended
  - CCBot

### 验证方法
1. 访问 `/robots.txt`
2. 确认包含所有 GEO 爬虫的 Allow 指令
3. 确认 Sitemap 引用指向正确的 URL

## 5. www vs apex 问题

### 当前状态
代码中 `getSiteOrigin()` 返回 `https://bllii.com`（apex），这是规范的 URL。

### 注意事项
- 如果 `www.bllii.com` 的 404 问题是 DNS/Cloudflare 配置问题，不在此代码库范围内
- 所有 sitemap 和 llms.txt 中的 URL 都使用 apex 域名 `https://bllii.com`
- 如果需要处理 www 重定向，需要在 Nginx/Cloudflare 层面配置

### 建议
如果 www 子域名需要工作，有两种方案：
1. **首选**：在 Cloudflare/DNS 层配置 www → apex 301 重定向
2. **备选**：在代码中添加中间件处理 www 重定向（需要修改 main.go）

## 部署清单

- [x] pkg/api/seo.go - 新增 SEO 路由处理器
- [x] pkg/api/api.go - 注册 SEO 路由
- [x] web/admin/src/bootstrap.ts - 添加 robots meta 标签
- [x] web/embed.go - 添加 X-Robots-Tag 响应头

## 测试建议

### 本地测试
由于 Go 1.27 工具链尚未可用，建议：
1. 在有 Go 1.27+ 环境中构建
2. 或临时降低 go.mod 中的 Go 版本要求（如果可行）

### 生产测试
1. 部署后使用 Google Search Console 验证 sitemap
2. 使用 curl 测试各个端点：
   ```bash
   curl -I https://bllii.com/sitemap.xml
   curl -I https://bllii.com/.well-known/llms.txt
   curl -I https://john-admin.bllii.com/admin
   curl https://bllii.com/robots.txt
   ```
3. 使用 Google Rich Results Test 验证 Video 扩展
4. 在 robots.txt 测试工具中验证爬虫访问权限

## 关键实现细节

### Sitemap 生成逻辑
```go
// getAllPublicVideos 分页获取所有视频
func (srv *Server) getAllPublicVideos(ctx context.Context) ([]store.VideoRecord, error) {
    var allVideos []store.VideoRecord
    pageSize := 100
    page := 1
    
    for {
        videos, total, err := srv.store.QueryVideos(ctx, store.VideoQuery{
            Page:      page,
            PageSize:  pageSize,
            OrderBy:   "id",
            OrderDesc: true,
        })
        
        allVideos = append(allVideos, videos...)
        
        // 获取完所有数据或达到限制（50 页）
        if len(allVideos) >= total || len(videos) == 0 || page >= 50 {
            break
        }
        
        page++
    }
    
    return allVideos, nil
}
```

### 站点域名配置
当前硬编码为 `https://bllii.com`，如需更改可：
1. 从环境变量读取（推荐）
2. 从数据库配置读取
3. 从 Request.Host 推断（需要谨慎处理 www）

## 潜在改进

1. **Sitemap 分片**：如果视频数量超过 50,000 条，应实现 sitemap 分片
2. **缓存**：考虑缓存 sitemap 生成结果（1 小时）
3. **增量更新**：记录最后更新时间，只在内容变化时重新生成
4. **图片 CDN**：如果缩略图使用 CDN，确保 URL 包含完整域名
5. **站点配置**：从数据库或配置文件读取 SITE_URL 而不是硬编码
