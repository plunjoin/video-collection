# 资讯、社区与站内通知接口

所有接口返回 JSON，沿用 `{ "code": 1, ... }` 成功响应与 `{ "code": 0, "error": "..." }` 失败响应。登录态使用 `Authorization: Bearer <token>` 或 `agg_auth_token` Cookie；用户身份、作者和通知接收者以服务端会话为准。禁用账号无法操作。

本次提供后端接口；Web / App 的内容页面与后台管理页面可据此接入。完整机器可读模型和参数位于 `/openapi.json`，交互文档位于 `/docs`。

评论现已升级为[通用评论、回复与点赞接口](comments-api.md)，可关联影视、资讯、社区及未来内容类型。以下社区评论端点继续兼容，但新客户端应使用 `/api/comments`。

## 端点与权限

| 端点 | 方法 | 权限及用途 |
| --- | --- | --- |
| `/api/news` | GET | 公开资讯列表；带 `id` 时获取详情，仅显示 published |
| `/api/admin/news` | GET / POST / DELETE | 管理员查询、新建、完整编辑、删除资讯 |
| `/api/community/posts` | GET / POST / DELETE | 公开已发布帖子；登录后发帖、编辑和删除自己的帖子 |
| `/api/admin/community/posts` | GET / POST / DELETE | 管理员查询全部状态、新建、编辑、隐藏、置顶、删除帖子 |
| `/api/community/comments` | GET / POST / DELETE | 公开已发布帖评论；登录后评论或删除自己的评论 |
| `/api/admin/community/comments` | GET / DELETE | 管理员查看指定帖的评论（包括隐藏帖）并删除任意评论 |
| `/api/community/likes` | POST / DELETE | 登录用户点赞或取消点赞已发布帖子 |
| `/api/user/notifications` | GET / DELETE | 登录用户查询、删除自己的通知 |
| `/api/user/notifications/unread-count` | GET | 登录用户获取全部未读通知数量 |
| `/api/user/notifications/read` | POST | 登录用户批量或全部标记已读 |
| `/api/admin/notifications` | POST | 管理员定向或全站发送系统通知 |

公开端点始终遵守可见性规则，包括管理员通过公开端点访问时。草稿和隐藏内容只在管理员查询中显示；作者更新隐藏帖时可在保存响应中获取自己的修订结果，但不能自行恢复发布。

## 通用查询与响应

分页参数 `page` 默认为 1，范围 1–1000000；`page_size` 默认为 20，范围 1–100。无结果返回空数组 `[]`。非法分页、ID、状态、JSON 或未知请求体字段返回 400；不支持的方法返回 405 和 Allow 头；JSON 请求体最大 1 MiB，超限返回 413。

列表响应：

```json
{ "code": 1, "data": [], "total": 0, "page": 1, "page_size": 20 }
```

详情、保存与评论创建响应：

```json
{ "code": 1, "data": { "id": 1 } }
```

上例省略业务字段，完整字段见 OpenAPI。未登录、禁用账号、管理员端点鉴权失败返回 401；修改他人内容或普通用户提交管理字段返回 403；目标不存在、未公开或通知不属于本人返回 404。内部存储错误返回 500，不暴露数据库细节。

## 资讯和帖子

GET 支持 `keyword`（标题或正文包含匹配，最多200字）、`category`（精确匹配，最多50字）、`author_id`。标题搜索不区分 ASCII 大小写，`%`、`_` 按字面搜索。管理员查询还可传 `status`，省略时包含所有状态。

列表按置顶优先、创建时间倒序、ID倒序排列。传 `id` 时直接返回详情，不应用列表分页与筛选。资讯状态为 `draft / published`；帖子为 `published / hidden`。

POST 是完整保存：`id` 省略或0为新建，正整数为编辑；编辑必须提交标题和正文，省略摘要、封面、分类会清空对应字段。作者与创建时间在更新时保留。

| 字段 | 限制 |
| --- | --- |
| `title` | 必填，去除首尾空白后1–200字 |
| `content` | 必填，去除首尾空白后1–50000字 |
| `summary` | 可选，最多1000字 |
| `cover` | 可选，空字符串或 HTTP(S) 完整 URL，最多2048字节 |
| `category` | 可选，最多50字 |
| `status` | 仅管理员可传；资讯默认 draft，帖子默认 published |
| `pinned` | 仅管理员可传；默认 false |

管理员完整更新时，省略 `status`、`pinned` 同样使用上述默认值；管理端应回传当前状态和置顶值。普通用户的新帖直接发布，编辑时保留已有的隐藏和置顶状态。所有正文是纯文本；客户端必须转义显示，不能未经净化插入 HTML。

管理员发布资讯示例：

```http
POST /api/admin/news
Authorization: Bearer <管理员 token>
Content-Type: application/json

{
  "title": "秋季新番情报",
  "summary": "本周公开的新作信息",
  "content": "资讯正文……",
  "category": "新番",
  "status": "published",
  "pinned": true
}
```

帖子创建使用 `/api/community/posts` 和普通用户 token，提交 `title`、`content`、可选的 `category` 等字段即可。删除使用 `DELETE <对应端点>?id=123`。删除帖子同时清理其评论和点赞，历史通知保留；客户端点击已删除或已隐藏的通知目标时应处理404。

返回记录还包含 `kind`、`author_id`、`author_name`、`author_avatar`、`created_at`、`updated_at`、`like_count`、`comment_count`、`liked`。公开 GET 传登录态可获取该用户是否已点赞；匿名访问时 `liked=false`。

## 评论和点赞

- 评论列表：`GET /api/community/comments?post_id=123&page=1&page_size=20`，按评论ID正序。
- 评论创建：`POST /api/community/comments`，JSON 为 `{"post_id":123,"content":"评论正文"}`；正文为1–2000字。
- 删除评论：`DELETE /api/community/comments?id=456`，仅评论作者有权删除；管理员使用管理端点删除。删除清空正文与点赞，保留空占位和已有回复；旧列表不返回占位，新通用评论接口返回 `is_deleted=true`。
- 点赞：`POST /api/community/likes`，JSON 为 `{"post_id":123}`。
- 取消点赞：`DELETE /api/community/likes?post_id=123`。

点赞响应为 `{"code":1,"data":{"liked":true,"like_count":1}}`。点赞和取消点赞均幂等，重复点赞不会累加数量或重复生成通知。取消后再次点赞会产生一次新的点赞通知。

评论和点赞只接受已发布帖子。给他人的帖子评论或点赞时，互动记录和作者通知在同一数据库事务内写入；通知写入失败会回滚互动。给自己的帖子评论或点赞不会通知自己。每次评论请求都会创建新评论，客户端应防止重复提交。

## 站内通知

通知类型为 `system / comment / like`。列表支持 `type` 和 `unread_only=true`，响应在通用列表字段之外包含 `unread_count`。`total` 是筛选后的数量，`unread_count` 是本人全部未读数量，不受筛选、分页影响。通知按ID倒序，列表读取不会自动标记已读。

独立计数端点返回 `{"code":1,"data":{"unread_count":3}}`。通知对象包含 `id`、`user_id`、`actor_id`、`type`、`title`、`content`、`target_type`、`target_id`、`comment_id`、`parent_comment_id`、`is_read`、`read_at`、`created_at`。互动通知的目标类型支持 `video / news / post` 及服务端注册的新类型，系统通知目标为空。`comment_id` 用于定位评论或回复，`parent_comment_id` 为直接父评论；历史通知和帖子点赞通知的这两个字段为0。未读记录的 `read_at=null`。

标记已读：

```http
POST /api/user/notifications/read
Authorization: Bearer <用户 token>
Content-Type: application/json

{"ids":[101,102]}
```

也可提交 `{"all":true}` 标记本人全部当前未读通知。`ids` 与 `all=true` 二选一；ID必须为正整数，每批最多1000个，自动去重。指定任何不存在或不属于本人的ID都会返回404并回滚整批修改。重复已读操作不改变首次已读时间，返回的 `data.count` 是本次从未读变为已读的数量。删除使用 `DELETE /api/user/notifications?id=101`。

管理员发送通知：

```http
POST /api/admin/notifications
Authorization: Bearer <管理员 token>
Content-Type: application/json

{"user_ids":[2,3],"title":"维护通知","content":"今晚将进行短时维护。"}
```

`title` 为1–200字，`content` 为1–5000字。`user_ids` 最多1000个正整数且自动去重，任一用户不存在或禁用时整批回滚。全站发送使用 `{"broadcast":true,"title":"维护通知","content":"通知正文"}`，不能同时传入非空 `user_ids`。返回 `data.sent_count` 表示实际接收人数。

广播在发送时向现有正常用户（包括管理员）逐人落库，各人的已读和删除状态相互独立。之后新注册的用户不会收到历史广播。

## 存储与验证

SQLite 与 PostgreSQL 共用参数化查询和事务逻辑；初始化自动创建 `content_entries`、`comments`、`comment_likes`、`community_likes`、`user_notifications` 及索引。旧 `community_comments` 数据一次性迁移到 `comments`，保留ID和创建时间；迁移标记防止已删除数据在重启后重新出现。

```powershell
go test ./...
```

新增测试使用临时 SQLite 数据库，覆盖鉴权、发布/隐藏、分页与搜索、作者权限、评论和点赞通知、重复与并发点赞、事务回滚、通知隔离及数据库重启持久化。

可通过 `TEST_POSTGRES_DSN` 指定可创建 schema 的测试数据库后运行 `go test ./pkg/store -run TestPostgresContentStore -v`，验证共享 SQL 在 PostgreSQL 上的行为。该测试使用独立临时 schema，结束后清理；未配置环境变量时明确跳过，不视为已通过 PostgreSQL 实测。
