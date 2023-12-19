# 通用评论、回复与点赞

评论以 `target_type + target_id` 关联内容。内置类型为 `video`（影视）、`news`（资讯）、`post`（社区帖子）。通过服务端注册可接入新类型，无需为每种内容创建评论表或新增评论路由。未注册类型返回400，避免伪造内容关联。

## 接口

| 方法与端点 | 用途 |
| --- | --- |
| `GET /api/comments` | 公开评论列表；传 `id` 获取单条详情 |
| `POST /api/comments` | 登录后发表评论或回复 |
| `DELETE /api/comments?id=123` | 删除自己的评论或回复 |
| `POST /api/comments/likes` | 登录后点赞评论或回复 |
| `DELETE /api/comments/likes?comment_id=123` | 取消自己的点赞 |
| `GET /api/admin/comments` | 管理员查询，包括隐藏帖与草稿资讯的已有评论 |
| `DELETE /api/admin/comments?id=123` | 管理员删除任意评论或回复 |

沿用 `Authorization: Bearer <token>` 或 `agg_auth_token` Cookie 鉴权。匿名用户可查询公开评论，不能评论、点赞或删除；禁用账号无法操作。普通用户只能删除自己的评论，内容作者也不能删除他人的评论。

公开查询、创建、回复与点赞都会校验关联内容存在且可见。草稿资讯、隐藏帖子或已删除影视返回404；管理员通过公开端点操作也遵守此规则。作者可在目标隐藏后删除自己的评论。

## 创建评论与回复

```http
POST /api/comments
Authorization: Bearer <token>
Content-Type: application/json

{"target_type":"video","target_id":100,"content":"这段剧情很精彩！"}
```

回复同一内容下的评论时增加 `parent_id`：

```json
{"target_type":"video","target_id":100,"parent_id":123,"content":"我也喜欢这一段。"}
```

`content` 去除首尾空白后必须为1–2000字，作为纯文本存储，前端须转义显示。`parent_id` 省略或0表示顶层评论，正整数表示直接回复某条评论；支持继续回复已有回复。父评论必须未删除且属于完全相同的 `target_type + target_id`，禁止跨影视、跨资讯或跨社区帖子回复。

作者从会话读取，`root_id` 在服务端计算。请求不能指定 `user_id`、`root_id`、点赞数等字段；未知JSON字段返回400。请求体上限1 MiB。创建成功返回 `{ "code": 1, "data": <评论对象>, "msg": "评论成功" }`；同样的创建请求重复提交会创建新记录。

## 查询和回复层级

```http
GET /api/comments?target_type=video&target_id=100&page=1&page_size=20
GET /api/comments?target_type=video&target_id=100&parent_id=123
GET /api/comments?target_type=video&target_id=100&root_id=123
GET /api/comments?id=456
```

- 默认列表只返回顶层评论。
- `parent_id` 查询某条评论的直接回复。
- `root_id` 查询顶层评论下的所有后代回复，不包含根评论本身，以扁平数组返回；可按 `parent_id` 还原层级。它必须是同一内容的顶层评论ID。
- `parent_id` 和 `root_id` 不能同时为正整数；两者可省略或为0。
- `id` 查询单条详情，不应用其他列表条件，适合从通知定位评论。

分页默认 `page=1&page_size=20`，页码最大1000000，每页最多100条，按评论ID正序。响应为 `{ "code":1, "data":[], "total":0, "page":1, "page_size":20 }`。带登录态查询时返回当前用户的 `liked`；匿名查询为false。

评论对象：

```json
{
  "id":456,
  "target_type":"video",
  "target_id":100,
  "parent_id":123,
  "root_id":123,
  "user_id":2,
  "author_name":"用户昵称",
  "author_avatar":"",
  "content":"我也喜欢这一段。",
  "is_deleted":false,
  "like_count":1,
  "reply_count":0,
  "liked":true,
  "created_at":"2026-09-29T08:00:00Z"
}
```

顶层评论自身的 `parent_id`、`root_id` 都为0；所有后代的 `root_id` 指向同一顶层评论。`reply_count` 只统计未删除的直接回复。社区评论额外返回 `post_id`，供旧客户端兼容。资讯/帖子详情的 `comment_count` 统计该内容下全部未删除评论和回复。

## 点赞与删除

点赞请求：

```http
POST /api/comments/likes
Authorization: Bearer <token>
Content-Type: application/json

{"comment_id":456}
```

返回 `{"code":1,"data":{"liked":true,"like_count":1}}`。同一用户重复点赞只保留一条记录和一次通知，取消点赞也幂等；取消后重新点赞会产生新的通知。评论和回复使用同一接口，已删除评论无法再点赞或被回复。

删除评论会清空正文和点赞，设置 `is_deleted=true`，保留父子关系及已有回复。通用列表与详情继续返回空占位，客户端应显示“评论已删除”；列表 `total` 包含这些占位。可以读取已删除父评论的现有回复，但不能向该占位添加新回复。重复删除返回404。

删除关联的影视、资讯或社区帖子时，在同一事务中清理该内容的全部评论、回复与评论点赞。历史通知保留，删除评论时会清空相关通知的正文摘录。点击已被整体删除的目标/评论应处理404。

## 站内通知

复用 `/api/user/notifications`、未读计数与已读/删除接口：

| 事件 | `type` | 收件人 |
| --- | --- | --- |
| 顶层评论 | `comment` | 内容作者；影视没有对应作者，因此不发送此通知 |
| 回复评论/回复 | `comment` | 直接被回复者及内容作者，按用户去重 |
| 点赞评论/回复 | `like` | 被点赞评论的作者 |

所有事件都排除操作人自己和已禁用/删除的收件人。评论、回复或点赞与通知在同一事务中写入，通知写入失败时整个互动操作回滚。

通知新增 `comment_id` 和 `parent_comment_id`，同时保留原内容的 `target_type`、`target_id`。客户端可先打开对应内容，再通过 `GET /api/comments?id=<comment_id>` 定位具体评论。回复通知的 `parent_comment_id>0`，评论点赞也带被点赞评论的父ID；结合 `type` 区分。系统通知、帖子点赞及迁移前的历史通知保持两个新字段为0。未读统计、批量已读和删除仍严格按当前用户隔离。

## 兼容迁移与新类型扩展

SQLite/PostgreSQL 启动时自动执行事务迁移，将旧 `community_comments` 中有效帖子评论转入 `comments`，保留评论ID、作者、正文、创建时间。PostgreSQL 同时调整序列。`content_migrations` 记录版本，重启不会重复迁移或恢复已删除数据。

原 `/api/community/comments` 和 `/api/admin/community/comments` 继续可用，共用新评论数据与ID：旧列表为全部未删除评论/回复的扁平分页，旧创建只创建帖子顶层评论，旧删除仅接受帖子评论ID。新接入应使用通用端点。

未来内容模块在服务初始化阶段调用 `store.Store.RegisterCommentTarget`：

```go
err := dbStore.RegisterCommentTarget("topic", func(
    ctx context.Context, tx *sql.Tx, id int, write, admin bool,
) (int, error) {
    query := "SELECT author_id, status FROM topics WHERE id=$1"
    if write {
        query = "UPDATE topics SET id=id WHERE id=$1 RETURNING author_id,status"
    }
    var owner int
    var status string
    if err := tx.QueryRowContext(ctx, query, id).Scan(&owner, &status); err != nil {
        return 0, err // sql.ErrNoRows 会转换为404
    }
    if !admin && status != "published" {
        return 0, store.ErrContentNotFound
    }
    return owner, nil // 返回0表示该内容没有可通知的作者
})
```

注册名格式为 `^[a-z][a-z0-9_]{0,49}$`，不能覆盖内置类型或重复注册。校验器必须使用传入事务检查存在性和可见性，写入时必须先锁关联内容；该模块的隐藏和删除也必须遵守相同的加锁顺序。目标删除事务在锁定目标之后调用 `store.DeleteTargetComments(ctx, tx, "topic", id)` 清理评论，避免留下孤立评论。注册与SQL仅由可信服务端代码执行，客户端不能动态注册内容类型。

## 验证

`go test ./...` 覆盖三类关联、跨目标回复拦截、多级回复分页、隐藏/草稿保护、评论点赞幂等与通知去重、删除占位、通知隔离、事务回滚、旧数据迁移、影片删除清理及新类型注册。

设置 `TEST_POSTGRES_DSN` 后，`go test ./pkg/store -run TestPostgresContentStore -v` 在独立临时schema中验证相同的SQL、评论/回复/点赞流程、通知及迁移。未设置时该测试明确跳过。
