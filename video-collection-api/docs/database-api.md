---
AIGC:
  ContentProducer: '001191110102MAD55U9H0F10002'
  ContentPropagator: '001191110102MAD55U9H0F10002'
  Label: '1'
  ProduceID: 'd2988b66-f59a-427f-a6f2-08325d8cb8ed'
  PropagateID: 'd2988b66-f59a-427f-a6f2-08325d8cb8ed'
  ReservedCode1: '0b371ac9-8f24-4461-b0d2-8d7dba9f72f7'
  ReservedCode2: '0b371ac9-8f24-4461-b0d2-8d7dba9f72f7'
---

# 数据库管理接口

管理员专用的数据库运维模块：引擎信息、表统计、数据浏览、备份恢复、清理维护与执行管理 SQL。所有端点挂在 `/api/admin/db/*` 下，仅管理员可用；未登录或非管理员一律返回 401。

响应沿用 `{ "code": 1, "data": ..., "msg": ... }` 成功格式与 `{ "code": 0, "error": "..." }` 失败格式。登录态使用 `Authorization: Bearer <token>` 或 `agg_auth_token` Cookie。

本次提供后端接口；管理后台的「数据库管理」页面可据此接入。完整机器可读模型和参数位于 `/openapi.json`，交互文档位于 `/docs`。

## 端点与权限

| 端点 | 方法 | 权限及用途 |
| --- | --- | --- |
| `/api/admin/db/info` | GET | 数据库整体信息：引擎、版本、连接目标、体积、业务表数量、备份目录与服务器时间 |
| `/api/admin/db/tables` | GET | 全部业务表的行数、体积、字段数、索引数与表注释，按表名排序 |
| `/api/admin/db/table` | GET | 分页浏览指定表数据，支持按已有字段排序与全列模糊搜索 |
| `/api/admin/db/backup` | POST | 将全部（或指定）业务表导出为 JSON 备份文件 |
| `/api/admin/db/backups` | GET / DELETE | 备份文件列表；删除需 `confirm=1`，删除后不可恢复 |
| `/api/admin/db/restore` | POST | 从备份恢复数据；`dry_run=true` 预览，正式执行需 `confirm=true` |
| `/api/admin/db/cleanup` | POST | 执行数据清理维护动作，需 `confirm=true`，返回逐项影响行数 |
| `/api/admin/db/sql` | POST | 执行单条管理 SQL；写语句与 DDL 需 `confirm=true` |

业务表指库中全部用户表：PostgreSQL 为 `public` schema 下的普通表，SQLite 为除 `sqlite_%` 外的全部表。空列表返回 `[]`。

## 通用约定

- 方法不支持返回 405；参数缺失、非法、确认标志缺失或语句被拒绝执行返回 400；未登录或鉴权失败返回 401；内部存储错误返回 500，不暴露数据库细节。
- **危险操作二次确认**：删除备份、恢复数据、清理维护、写 SQL 均为不可逆或大规模写入操作，接口层要求显式确认标志。管理端应在弹窗确认后再携带对应参数发起正式请求。
- 备份为 JSON 格式（`format=video-collection-backup, version=1`），含来源引擎、创建时间与逐表的列定义和行数据。备份目录：PostgreSQL 为工作目录下 `data/backups`，SQLite 为数据文件同目录 `backups`。文件名含秒级时间与毫秒后缀，同秒多次备份不会相互覆盖。

## 库信息与表统计

`GET /api/admin/db/info` 返回当前引擎（PostgreSQL 为主，连接失败自动降级 SQLite 时为 sqlite）、数据库版本、连接目标、库整体体积、业务表数量、备份目录与服务器时间。

`GET /api/admin/db/tables` 每张表包含：

| 字段 | 说明 |
| --- | --- |
| `name` / `rows` | 表名与行数 |
| `approximate` | PostgreSQL 行数来自统计信息估算时为 true；新表或统计异常自动回退精确计数后为 false。SQLite 恒为精确计数 |
| `size_bytes` | 表占用字节数（SQLite 下为 0，库整体占用见 info） |
| `column_count` / `index_count` | 字段数与索引数 |
| `comment` | PostgreSQL 表注释 |

## 数据浏览

`GET /api/admin/db/table`：

| 参数 | 说明 |
| --- | --- |
| `table` | 必填，目标表名，必须是当前库中存在的业务表 |
| `page` / `page_size` | 页码默认 1；每页行数默认 100，超过 500 回落为 100 |
| `order_by` | 排序字段，必须是该表已有字段；缺省按第一列（通常为 id） |
| `order_desc` | `1`/`true`，或 `order_dir=desc` 时按降序 |
| `keyword` | 全列模糊搜索，`%` 与 `_` 按字面匹配，不作为通配符 |

响应 `data` 含 `columns`（字段名与类型）、`rows`（每行为 字段名→值 的对象）、`total`（命中总行数）与分页信息。`total` 为精确计数。

## 备份管理

创建备份（可选指定表，缺省全部业务表）：

```http
POST /api/admin/db/backup
Authorization: Bearer <管理员 token>
Content-Type: application/json

{"tables": ["videos", "users"]}
```

响应返回文件名、完整路径、体积、覆盖表数、导出总行数与创建时间。

列表按文件名倒序，仅读取文件头即可返回体积、创建时间、来源引擎与表/行数统计。删除使用 `DELETE /api/admin/db/backups?file=<文件名>&confirm=1`；文件名仅接受 `.json` 且禁止路径穿越。

## 恢复数据

`POST /api/admin/db/restore`，JSON 为 `{"file":"...","mode":"merge|replace","dry_run":false,"confirm":true}`。

- `dry_run=true`：仅返回预览（备份中各表行数、目标表是否存在），不写库，无需 confirm。
- 正式执行必须携带 `confirm=true`；缺失时返回 400，并提示先使用 dry_run 预览。
- `mode=merge`（默认）：逐行合并导入，主键冲突行跳过并在结果中计数。
- `mode=replace`：先清空目标表再整体导入。PostgreSQL 下清空为一次性 `TRUNCATE ... CASCADE`，会级联清空引用表，务必先确认依赖关系。

恢复写入显式主键后自动校正 PostgreSQL 序列（`setval`），避免恢复数据后新插入撞主键。行级导入失败在事务内通过保存点容错，计入 `skipped`，不中断其他行。PostgreSQL 的 JSONB 列（如 `videos.play_groups`）恢复时自动显式 cast。结果返回 `inserted` / `skipped` 与耗时。

## 数据清理维护

`POST /api/admin/db/cleanup`，JSON 为 `{"actions":["vacuum"],"confirm":true}`。动作逐项执行、互不中断，每项返回 `affected` 影响行数或 `error` 说明（如当前引擎无相关表）。

| 动作 | 说明 |
| --- | --- |
| `vacuum` | PostgreSQL 执行 `VACUUM (ANALYZE)`，SQLite 执行 `VACUUM` |
| `orphan_play_sources` | 清理 `play_sources` 中目标视频已不存在的线路记录（仅 SQLite；PostgreSQL 线路存储于 `videos.play_groups`，返回说明性 error） |
| `dup_play_sources` | 按 `(video_id, player_code, source_id)` 去重 `play_sources`，保留最大 id（仅 SQLite） |
| `orphan_comments` | 删除目标视频已不存在的影视评论 |
| `orphan_user_history` / `orphan_user_favorites` | 清理目标视频已不存在的播放历史 / 收藏 |
| `clear_user_history` | 清空全部用户播放历史 |
| `clear_feedbacks` | 清空全部用户反馈 |

未知动作名返回对应项的 error，不影响其他动作执行。

## SQL 执行器

`POST /api/admin/db/sql`，JSON 为 `{"sql":"SELECT ...","confirm":false}`。

- 仅接受**单条**语句，引号内的分号不计；多条语句返回 400。
- `SELECT / WITH / EXPLAIN / SHOW / PRAGMA / VALUES / DESCRIBE` 视为只读，直接执行，最多返回 1000 行，超出置 `truncated=true`。
- `INSERT / UPDATE / DELETE / REPLACE` 与其余语句（DDL）必须携带 `confirm=true`，缺失返回 400。
- 执行超时：只读 30 秒，写与 DDL 60 秒。
- 响应按类型返回：select 含 `columns` / `rows` / `row_count`；write 与 ddl 含 `affected` 影响行数。

## 存储差异与验证

PostgreSQL 与 SQLite 共用参数化查询与管理逻辑，关键差异：

- 表行数：PG 为统计估算（`approximate=true`，新表回退精确计数），SQLite 为精确 COUNT。
- 体积统计：PG 使用 `pg_database_size` 与表级体积；SQLite 以数据文件大小为准，表级体积为 0。
- 线路数据：SQLite 存于 `play_sources` 表；PG 存于 `videos.play_groups` JSONB，清理动作按引擎返回说明。

```powershell
go test ./...
```

新增测试使用临时 SQLite 数据库覆盖：鉴权与确认机制、表统计、浏览分页/排序/搜索、备份与恢复（merge/replace/预览）、清理动作、SQL 分类执行与单条语句校验。

可通过 `TEST_POSTGRES_DSN` 指定可创建临时库的测试数据库后运行 `go test ./pkg/store -run TestDBAdminPostgresIntegration -v`，验证 PostgreSQL 分支：JSONB 恢复、TRUNCATE CASCADE、序列校正、估算行数回退与占位符差异。未配置环境变量时明确跳过，不视为已通过 PostgreSQL 实测。

> AI生成