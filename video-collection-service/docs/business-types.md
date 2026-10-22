# 业务类型

管理员在「内容管理 → 业务类型」管理采集目标。系统内置 `record`（通用数据）、`article`（文章）、`video`（视频）；系统类型不可删除，系统字段的名称、类型和必填语义不可变。显示名称与说明可修改，系统类型可以添加自定义字段，这些扩展字段保存在采集记录 payload 中。

创建自定义类型时填写 slug、名称和可选初始字段。slug 为 2–48 位小写字母、数字、下划线，以字母开头，不允许系统类型名或 `biz_` 前缀。服务端派生物理表名 `biz_<slug>`，界面不接受任意表名。字段支持 text、integer、real、boolean、json；名称与类型创建后不可修改，显示名称和自定义字段的必填设置可修改。增加字段会执行 ADD COLUMN；删除自定义字段会 DROP COLUMN，永久删除该列数据（原始采集 payload 仍保留）。新增必填规则作用于后续采集，不回填历史数据。

在「使魔规则工坊」的「内容类型」选择注册类型，按页面列出的字段配置映射和唯一标识，再预览、保存和运行。字段必填和数据类型在预览与写入时校验。自定义类型不强制 title，除非 schema 将它设为必填。自定义表的 record_key 对来源 ID 和外部 key 编码，保持不同采集源的同名 key 相互独立。业务行和 collection_records 在同一事务写入，采集结果的修改与删除同步到自定义业务表。

Webhook 源默认写文章，可在工坊选择业务类型后点「保存业务类型」。此操作保留推送源身份及其密钥、启用状态等配置。自定义类型可直接推送 schema 字段（如 `{"id":1,"score":7,"details":{"tag":"demo"}}`），保留 JSON、数字和布尔值，不强制提供标题。条目仍须有 id 作为外部去重标识。推送继续使用 `POST /api/webhooks/collector` 和现有 HMAC 验签。系统文章继续使用 article → news 草稿路径；视频继续使用 UpsertVideo，包括播放分组解析。

仅无采集源绑定、无采集记录且物理表为空的自定义类型可删除；删除会移除空表和注册信息。先解除来源绑定并删除采集结果。系统类型不能删除。观察员只能查看；运营人员沿用规则工坊的访问限制，不开放此页面。

管理 API：

- GET/POST `/api/admin/business-types`
- GET/PUT/DELETE `/api/admin/business-types/{slug}`（PUT 仅 name、description）
- POST `/api/admin/business-types/{slug}/fields`
- PUT/DELETE `/api/admin/business-types/{slug}/fields/{name}`（更新 label、required；名称和类型不可变）

RAG 仍按既有 source_type 索引 wiki 与 news/post。自定义业务表本阶段不自动进入 RAG；`upsertBusinessRow` 留有 TODO，后续需显式注册 source_type 与索引适配器。

验证：`TZ=Asia/Shanghai go test ./pkg/store/ ./pkg/ingest/ ./pkg/api/ ./pkg/scheduler/ -count=1`。现有 analytics 测试的日期使用进程时区，需与服务的北京时间业务日一致；ingest 的现有 live 测试需要网络。管理端执行 `cd web/admin && pnpm build`；生成的 dist 按仓库规则忽略，由 go:embed 在构建服务时读取。
