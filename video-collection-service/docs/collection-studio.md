# 通用采集规则工作台

后台入口 `/collection-rules`。旧 MacCMS JSON / XML / RSS 节点继续使用 `/sources`。两类规则共享采集源存储、全局自动调度和运行日志。

## 配置流程

1. 选择来源：JSON 接口、静态网页、数据库、Excel / CSV。
2. 配置连接与提取：接口请求、JSON 列表路径；网页列表/详情/下一页 CSS；数据库 SELECT；文件工作表及表头行。
3. 配置字段：来源路径/列名/CSS → 目标字段，展开行设置默认值、去 HTML、RE2 正则替换、去空白、必填。
4. 测试预览：最多 10 条，原始值和清洗结果可切换，逐条展示校验失败原因，不写入内容库。修改配置后预览自动失效。
5. 保存或保存并运行，在“查看结果”中浏览入库记录，在“运行日志”查看执行情况。开启规则自动调度后还需在“定时调度”启用全局计划。

## 来源能力

| 来源 | 已实现 |
| --- | --- |
| JSON 接口 | GET / POST、静态请求体、Headers、Query 参数、点分路径与数字数组下标、URL 页码参数 |
| 网页 | 静态 HTML、列表条目 CSS、同主机详情链接、下一页 CSS、循环链接检测、text/html/属性提取、href/src 相对 URL 补全 |
| 数据库 | PostgreSQL、MySQL、SQLite、SQL Server；单条 SELECT 包装为子查询并加记录上限 |
| 文件 | Excel `.xlsx`、UTF-8 CSV、工作表选择、表头行选择、列名映射、跳过空行 |

JSON 路径例如 `data.items`、`images.0.url`；根数组使用 `$`。这不是完整 JSONPath，不支持通配符或过滤表达式。网页字段 `$url` 表示当前列表页或详情页地址，详情选择器以每个列表条目为范围，字段选择器以详情页为范围；无详情配置时以列表条目为范围。

数据库规则只保存连接串的**环境变量名**，如 `IMPORT_DATABASE_DSN`。后端启动前设置实际值；不要把密码作为规则字段保存。SQL Server 必须使用只有 SELECT 权限的账号；PostgreSQL / MySQL 额外使用只读事务，SQLite 启用 query_only。SQL 的语法过滤是防误操作措施，不能替代数据库账号权限。SQL 不能包含分号、注释、写操作或 SELECT INTO；需符合对应引擎的子查询语法。

| 驱动 | 连接串格式（占位示例） |
| --- | --- |
| postgres | `postgres://reader:password@host:5432/database?sslmode=require` |
| mysql | `reader:password@tcp(host:3306)/database` |
| sqlite | `file:/absolute/path/source.db?mode=ro` |
| sqlserver | `sqlserver://reader:password@host:1433?database=database` |

上传文件放在 `data/collection-imports`，可用 `COLLECTION_UPLOAD_DIR` 覆盖；规则保存随机文件 token，客户端不能指定服务器文件路径。文件应与数据库一起备份；数据库备份不会包含原始上传文件。上传和删除规则不会自动删除文件，管理员可按保留策略清理不再引用的文件。

## 内容与去重

- **通用数据**：任意合法目标字段保存到 `collection_records`，便于以后新增内容模型。
- **文章**：`title`、`content` 必填；可选 `summary`、`cover`、`category`。写入现有 `content_entries` 的资讯草稿，使用第一个启用管理员作为作者，可通过资讯管理 API 审核发布。文章和来源记录在同一事务提交。重采只更新草稿，已发布/隐藏内容保持不变。
- **视频**：`title` 必填；可选 `play_url`、`cover`、`content`、`category`、`year`、`actor`、`director`、`area`、`remarks`。复用现有视频库按片名聚合策略，`play_url` 生成单条正片播放线路。多线路/多剧集继续使用专用视频协议节点。

来源 ID + 内容类型 + 映射后的唯一字段值共同去重，可选更新或跳过；唯一字段不能为空。无效记录跳过并记录日志。来源读取或入库失败会中止任务，保留已成功记录并报告错误；修正规则后可重跑去重。删除规则保留已经导入的内容和来源记录。

规则以 `type: pipeline`、`filter.pipeline.version: 1` 保存到现有 sources 表的 filter_rules JSON（SQLite / PostgreSQL 均支持），无须破坏旧配置。输入适配器输出 `Sample`，统一做字段处理，再由目标适配器入库；增加来源或内容类型时在这些边界扩展。

## 接口

所有接口要求管理员 Cookie 或 Bearer 认证，响应使用现有 `{code,data,msg}` 格式。

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| GET / POST / DELETE | `/api/admin/sources` | 获取、保存、删除规则 |
| POST | `/api/admin/collection/upload` | multipart 字段 `file`，返回 `{token,name}` |
| POST | `/api/admin/collection/preview` | 提交完整 SourceConfig，返回 `{raw,values,errors}[]` |
| POST | `/api/admin/sources/collect` | `{source_id,hours:0}`，异步运行 |
| GET | `/api/admin/collection/records?source_id=...&page=1&page_size=20` | 分页结果及 total |

完整配置结构见 OpenAPI `PipelineRule` / `SourceConfig`，及 `config/pipeline.go`。

## 执行边界

每次最多 10,000 条、100 页；HTTP 每次响应最多 8 MB，超时 1–60 秒，重试 0–3 次；上传最多 20 MB，Excel 解压上限 100 MB。预览总时限 25 秒，任务总时限 10 分钟。规则修改不改变已经启动的任务快照。同一进程内同一规则禁止并发重复运行。

当前为有上限的批量读取 + 去重，不提供持久游标/断点续采，不把旧视频 `h=24` 参数用于通用来源。尚未包括：浏览器 JS 渲染、可视化点选网页元素、XPath、登录流程录制、OAuth 刷新、游标式接口分页、分布式任务队列、火车头私有规则格式导入、旧 `.xls` 二进制格式。

## 验证

自动测试覆盖接口分页/请求头/预览上限、网页详情/相对链接/翻页循环、CSV 与 Excel、SQLite 只读导入、非法规则、管理员权限、预览无入库副作用、配置持久化、文章去重与发布保护、调度入库及视频目标。外部 PostgreSQL / MySQL / SQL Server 导入需要使用部署环境的只读账号做连通性验收。
