# 业务类型

管理员在「内容管理 → 业务类型」管理采集目标的 schema/config。数据浏览统一位于 Admin「资源库」：`video` 和 `article` 使用视频库、资讯页，`record` 显示在通用数据页，自定义表类型显示为动态业务数据页。系统内置 `record`（通用数据）、`article`（文章）、`video`（视频）；系统类型不可删除，系统字段的名称、类型和必填语义不可变。显示名称与说明可修改，系统类型可以添加自定义字段，这些扩展字段保存在采集记录 payload 中。

创建自定义类型时填写 slug、名称和可选初始字段。slug 为 2–48 位小写字母、数字、下划线，以字母开头，不允许系统类型名或 `biz_` 前缀。服务端派生物理表名 `biz_<slug>`，界面不接受任意表名。字段支持 text、integer、real、boolean、json、enum；名称与类型创建后不可修改，显示名称、默认值（`default`）和自定义字段的必填设置可修改。enum 必须提供非空字符串选项数组 `options`，例如 `["draft","published"]`；非空字段值须与某个选项完全一致。管理员可以修改 enum 的 options 与默认值，修改后作用于后续写入，不回填历史数据。非 enum 字段不保存 options。采集/Webhook/schema 保存时，若某字段缺省或为空且配置了默认值，则自动填入后再做必填与类型校验。

内置 `article.status` 为枚举 `draft|published`，默认值 `published`（系统字段不可删；可在业务类型管理里改默认值，例如改回 `draft` 恢复人工审阅）。

管理员可在创建字段或 PUT 更新字段时设置 `filterable`，控制 schema 行列表是否允许按该字段筛选。省略时 text、enum、integer、real、boolean 默认 true，json 默认 false。显式 false 会持久保存；json 始终不可筛选，尝试设置为 true 返回 400。增加字段会执行 ADD COLUMN；删除自定义字段会 DROP COLUMN，永久删除该列数据（原始采集 payload 仍保留）。新增必填规则作用于后续采集，不回填历史数据。

在「使魔规则工坊」的「内容类型」选择注册类型，按页面列出的字段配置映射和唯一标识，再预览、保存和运行。字段必填和数据类型在预览与写入时校验。自定义类型不强制 title，除非 schema 将它设为必填。自定义表的 record_key 对来源 ID 和外部 key 编码，保持不同采集源的同名 key 相互独立。业务行和 collection_records 在同一事务写入，采集结果的修改与删除同步到自定义业务表。

Webhook 源默认写文章，可在工坊选择业务类型后点「保存业务类型」。此操作保留推送源身份及其密钥、启用状态等配置。自定义类型可直接推送 schema 字段（如 `{"id":1,"score":7,"details":{"tag":"demo"}}`），保留 JSON、数字和布尔值，不强制提供标题。条目仍须有 id 作为外部去重标识。推送继续使用 `POST /api/webhooks/collector` 和现有 HMAC 验签。系统文章走 article → news：入库状态取字段默认值（默认直接 published），payload 可覆盖；同采集 key 再推会更新已发布稿。视频继续使用 UpsertVideo，包括播放分组解析。

仅无采集源绑定、无采集记录且物理表为空的自定义类型可删除；删除会移除空表和注册信息。先解除来源绑定并删除采集结果。系统类型不能删除。观察员只能查看；运营人员沿用现有资源页的访问限制。

管理 API：

- GET/POST `/api/admin/business-types`
- GET/PUT/DELETE `/api/admin/business-types/{slug}`（PUT 仅 name、description）
- POST `/api/admin/business-types/{slug}/fields`
- PUT/DELETE `/api/admin/business-types/{slug}/fields/{name}`（更新 label、required、filterable、options、default；名称和类型不可变）
- GET `/api/admin/business-types/{slug}/rows?page=&page_size=` 浏览 `record` 或自定义表行；`article`、`video` 使用专用页面
- DELETE `/api/admin/business-types/{slug}/rows?id=` 删除自定义表行；`record` 使用 `source_id` 与 `key` 参数

schema 行 API（使用现有管理员认证）：

- GET `/api/admin/schema/{slug}/rows?page=1&page_size=20`：列表，返回 `code`、`data`、`total`、`page`、`page_size`；每页最多 100 条。自定义表按 updated_at、id 倒序。
- GET `/api/admin/schema/{slug}/rows?id=123`：读取自定义表单行，返回 `data`；不存在返回 404。
- POST `/api/admin/schema/{slug}/rows/save`：以 JSON 对象提交 schema 字段，例如 `{"title":"示例","status":"live","meta":{"tag":"demo"}}`。省略 id 或 id=0 时创建，成功返回 `{"code":1,"msg":"保存成功","id":123}`；提供正整数 id 时更新该行，并保留原 source_id 与 key。更新时提交完整字段值，省略的可选字段会清空，缺少必填字段返回 400。
- DELETE `/api/admin/schema/{slug}/rows?id=123`：删除自定义表行及其采集记录。
- POST `/api/admin/schema/{slug}/rows/batch-delete`：提交 `{"ids":[123,124]}`，在同一事务删除业务行及采集记录；空数组或无效 id 返回 400，不存在的行返回 404，整批回滚。

创建时可选 `source_id`（默认 manual）和外部 `key`（默认自动生成）；相同 source_id、key 会更新已有行。schema 字段直接位于请求对象顶层，JSON 字段可提交对象或数组；未注册字段保留在 payload 中。保存沿用采集写入的 schema 校验，非法 enum、JSON 或缺少必填值返回 400。列表与单行读取返回系统列 id、record_key、source_id、payload、created_at、updated_at，以及 schema 字段；JSON 字段和 payload 解码为 JSON 值。

自定义表列表支持以下查询参数，多个条件以 AND 组合，查询值均使用 SQL 参数绑定：

- `source_id=manual`：系统来源列精确匹配。
- `{field}=value`：仅允许数据库元数据中 filterable=true 的 schema 字段；text、enum 精确匹配，integer、real 按数字匹配，boolean 使用 true 或 false。enum 筛选值也须属于 options。
- `{field}_min=value`、`{field}_max=value`：integer、real 的包含边界范围筛选。
- `created_at_min=value`、`created_at_max=value`、`updated_at_min=value`、`updated_at_max=value`：系统时间列的包含边界字符串比较，建议使用与存储一致的 UTC RFC3339 格式。这些参数不依赖 schema 字段或其 filterable 设置。
- `q=关键词`：在所有 filterable=true 的 text 字段上以 OR 组合 LIKE 匹配；使用 `%关键词%` 模式，关键词中的 `%`、`_` 也作为 LIKE 通配符。空 q 不限制结果，没有可搜索 text 字段时非空 q 返回空列表。

例如：`GET /api/admin/schema/demo_item/rows?status=live&q=示例&created_at_min=2026-01-01T00%3A00%3A00Z`。未知筛选键、不可筛选字段（包括所有 json 字段）、非法值或重复筛选参数返回 400。

`record` 类型支持列表，以及使用 `source_id`、`key` 读取或删除单条采集记录；其列表沿用原有分页行为，不应用上述自定义表筛选。`record` 不支持 save 或 batch-delete。`article`、`video` 在 schema 行 API 上返回 400，继续使用专用资讯、视频 API。现有 business-types 路由及其列表分页行为保持不变，`/api/admin/videos/save` 与 news API 保持不变。

RAG 仍按既有 source_type 索引 wiki 与 news/post。自定义业务表本阶段不自动进入 RAG；`upsertBusinessRow` 留有 TODO，后续需显式注册 source_type 与索引适配器。

验证：`TZ=Asia/Shanghai go test ./pkg/store/ ./pkg/ingest/ ./pkg/api/ ./pkg/scheduler/ -count=1`。现有 analytics 测试的日期使用进程时区，需与服务的北京时间业务日一致；ingest 的现有 live 测试需要网络。管理端执行 `MSYS_NO_PATHCONV=1 wf build -mode spa -base /admin -modules ../wf_modules web/admin`（PowerShell/cmd 去掉前缀；详见 `web/admin/README.md`）；生成的 dist 按仓库规则忽略，由 go:embed 在构建服务时读取。
