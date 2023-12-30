# 视频智能采集聚合平台 - 现代后台管理控制台 (Admin Pro)

基于 **Vite 6 + Vue 3 (Composition API / `<script setup>`) + TypeScript + Element Plus** 构建的企业级、现代化单页后台管理控制台，与 `video-collection-api` 纯后端 RESTful API 服务完成深度对接。

---

## 🌟 核心特性与架构设计

### 1. 现代化技术栈
- **核心框架**：Vue 3.5 + TypeScript 5.9，全面使用 `<script setup>` 组合式 API。
- **构建工具**：Vite 6，毫秒级热更新，极速构建打包。
- **UI 组件库**：Element Plus，支持暗色模式（Dark Mode）与明亮模式无缝热切换，全站集成中文语言包 (`zh-cn`)。
- **图标系统**：@element-plus/icons-vue 全局动态注册。
- **路由鉴权**：Vue Router 4，集成全生命周期路由守卫、NProgress 加载进度条、未登录强拦截与鉴权回跳。
- **状态管理**：Pinia 2，解耦管理用户认证状态、系统主题折叠配置、多标签页缓存等。
- **网络请求**：Axios 深度封装，统一请求/响应拦截器，自动注入 Bearer Token，标准错误捕获与 401 自动重定向。

### 2. 经典中后台交互体验
- **响应式侧边栏**：支持一键折叠/展开，平滑过渡动效，高亮当前活跃菜单。
- **多标签页 (TagsView)**：支持多页面平铺切换、鼠标右键/快捷关闭当前、关闭其他、关闭全部、刷新当前页。
- **全屏切换与主题切换**：支持全屏快捷沉浸式管理，内置深色/明亮双配色方案。
- **前台门户与 API 文档直达**：顶部导航快捷跳转客户端 Web 门户及 OpenAPI Swagger UI 调试文档。

---

## 📚 已对接的 Backend API 业务模块

| 模块名称 | 路由路径 | 对接接口与能力说明 |
| :--- | :--- | :--- |
| **管理员认证** | `/login` | `POST /api/login` 管理员身份鉴权，支持记住密码与一键填充测试凭据 |
| **系统仪表盘** | `/dashboard` | `GET /api/admin/stats` 统计卡片、活跃采集点即时触发、分类视频分布、系统环境概览 |
| **采集点管理** | `/sources` | `GET/POST/DELETE /api/admin/sources` 增删改查；`POST /api/admin/sources/test` 连通性探测；`POST /api/admin/sources/collect` 单源 24h 增量与全量采集；`POST /api/admin/sources/collect-all` 一键全网并发采集 |
| **视频仓库** | `/videos` | `GET /api/videos` 视频分页与关键词/分类检索；`GET /api/video` 聚合线路与集数详情查看；`POST /api/admin/videos/save` 编辑保存；`POST /api/admin/videos/batch-delete` 多选批量删除 |
| **定时采集调度** | `/scheduler` | `GET/POST /api/admin/scheduler/auto` 查看与设置自动轮询巡检周期与开启状态 |
| **求片与反馈** | `/feedbacks` | `GET/DELETE /api/admin/feedbacks`、`POST /api/admin/feedbacks/reply` 管理用户留言报错，更新处理状态与管理员跟进回复 |
| **用户账号管理** | `/users` | `GET/POST/DELETE /api/admin/users` 系统管理员及前台用户账号维护、角色授权、密码重置 |
| **客户端主题** | `/themes` | `GET /api/admin/themes` 列出主题；`POST /api/admin/themes/switch` 一键应用激活；`POST /api/admin/themes/upload` 上传 ZIP 导入第三方主题 |
| **播放器管理** | `/players` | `GET /api/admin/players`、`POST /api/admin/players/switch` 切换默认播放器；`POST /api/admin/players/config` 更新解析参数；`POST /api/admin/players/upload` 导入播放器扩展 |
| **系统配置** | `/settings` | `GET /api/site/config`、`POST /api/admin/site/config` 网站标题、滚动公告、SEO 关键词及描述、备案号等 |
| **运行审计日志** | `/logs` | `GET /api/admin/logs` 控制台风格实时日志流，支持 5s 自动刷新、日志级别与条数筛选 |

---

## 🚀 启动与构建指南

### 1. 安装项目依赖
```powershell
pnpm install
```

### 2. 启动本地开发服务 (带反向代理)
```powershell
pnpm run dev
```
启动后访问：`http://localhost:3000/`，默认管理员账号：`admin` / 密码：`admin123`。
> Vite 自动将 `/api` 开头的请求反向代理到本地 Go 后端服务 `http://localhost:80`。

### 3. 生产环境构建与打包
```powershell
pnpm run build
```
执行完毕后将在 `dist/` 目录下生成标准静态 SPA 生产资源，可直接部署至 Nginx 或嵌入任意静态服务器中。

## 通用采集规则工作台

后台菜单“采集规则工作台”（`/collection-rules`）提供来源选择、连接配置、字段映射与清洗、样本预览四步配置，支持网页、JSON 接口、多种数据库和 Excel / CSV。保存后接入现有调度与日志，可在结果面板查看导入记录。详细能力、部署变量及当前边界见 [采集工作台说明](../video-collection-api/docs/collection-studio.md)。
