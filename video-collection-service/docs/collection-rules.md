# 可配置的视频采集规则

后台 `/sources` 使用规则模板配置视频源；`/collection-rules` 提供网页、JSON、数据库、Excel / CSV 的通用工作台。MacCMS 是视频规则模板之一。

## 模板与保存

`config/collection_templates.yaml` 是可编辑的模板目录。可追加任意数量模板，后端 `GET /api/admin/sources/templates` 与后台选择器会加载该文件。环境变量 `COLLECTION_TEMPLATES_PATH` 可以指定其他文件；显式指定的文件缺失或无效时返回错误，默认文件缺失则读取内嵌 YAML。

每个模板包含 `id`、`name`、`description`、`aliases` 和 `rule`。选择模板后，将规则副本保存在源的 `filter.collector`，运行时读取保存的副本。修改模板不会自动改变这些源。旧类型 `json` / `xml` / `rss` / `custom_json` 通过模板别名兼容，尚未保存规则副本的旧源会读取当前模板的请求定义；后台保存后转换为 `type=rule`。

## 自定义 REST JSON 示例

新增模板只需追加 YAML：

```yaml
- id: own-library
  name: 自有片库
  description: 自定义分页与嵌套字段
  aliases: [own_library]
  rule:
    version: 1
    format: custom_json
    method: GET
    query:
      page_number: "{page}"
      updated_hours: "{hours}"
      limit: "50"
    mapping:
      list_path: data.items
      page_path: data.page
      page_count_path: data.pages
      total_path: data.total
      id_path: identity.id
      name_path: metadata.title
      type_path: metadata.category
      pic_path: images.0.url
      play_url_path: stream.url
      play_from_path: stream.player
      content_path: metadata.description
```

支持的响应格式：`custom_json`、`maccms_json`、`maccms_xml`、`rss`。格式选择解析器，请求参数由规则定义。添加新的 JSON 数据源结构或请求参数只需更改规则；新的二进制或私有协议需要实现相应解析器。

`method` 支持 GET / POST，`body` 为静态请求体字符串；POST 默认发送 `Content-Type: application/json`，可用源的 `headers` 覆盖。分页目前在 URL Query 中变化，请求体不执行变量替换。

| 变量 | 值 |
| --- | --- |
| `{page}` | 当前页码，视频源从 1 开始 |
| `{hours}` | 增量小时数，全量时省略对应参数 |
| `{action}` | `detail` / `list` |
| `{type_id}` | 查询分类 ID，无值时省略 |
| `{keyword}` | 搜索词，无值时省略 |
| `{ids}` | 视频 ID 列表，无值时省略 |

源地址原有 Query 和 `custom_params` 先合并，规则中的同名参数最后生效。全量时删除包含 `{hours}` 的参数，避免源地址中残留旧的增量限制。未在规则中定义的 CMS 参数不会自动添加。

映射使用点分路径及数字数组下标，`$` 表示根数组；例如 `data.items`、`metadata.title`、`images.0.url`。显式指定的字段不存在时不会回退到猜测字段。列表路径错误会报错；正确的空数组代表空页，结束采集。

分页响应支持数字和数字字符串。`page_count_path` 指向总页数，缺省表示单页源；若来源只提供“下一页游标”，应先转换为页码接口再接入。可映射视频的 ID、标题、分类、封面、播放地址、播放器标识、更新备注、演员、导演、地区、年份、简介。MacCMS 格式解析器保留其完整分类和多线路能力。

## API 保存示例

管理员使用 `POST /api/admin/sources` 保存：

```json
{
  "id": "my-library",
  "name": "自有片库",
  "api": "https://api.example.com/videos",
  "type": "rule",
  "active": false,
  "collect_hours": 12,
  "page_limit": 100,
  "timeout_sec": 15,
  "retry_count": 0,
  "interval_ms": 300,
  "headers": {"Authorization": "Bearer YOUR_TOKEN"},
  "custom_params": {"limit": "50"},
  "filter": {
    "collector": {
      "version": 1,
      "format": "custom_json",
      "method": "GET",
      "query": {"page": "{page}", "updated_hours": "{hours}"},
      "mapping": {
        "list_path": "data.items",
        "page_count_path": "data.pages",
        "name_path": "title",
        "play_url_path": "stream_url"
      }
    },
    "require_play_urls": true,
    "ignore_name_keywords": ["预告"],
    "default_player": "m3u8"
  }
}
```

将同一份配置提交到 `POST /api/admin/sources/test` 可测试实际请求与样本解析，不写库。`POST /api/admin/sources/collect` 参数为 `{"source_id":"my-library","hours":12}`；`hours=0` 全量、`hours=-1` 使用源配置。所有接口均要求管理员权限。

`collect_hours=0` 会保留为全量配置；自动调度按每个源的配置运行。全量与增量都遵守 `page_limit`；旧视频源的 `page_limit=0` 表示不限页数，新建源默认 100 页。`retry_count=0` 表示一次请求、不重试；可重试 0–3 次。响应上限 8 MB，超时最高 60 秒。

分类映射和原有清洗规则继续保存在 `category_mappings` 与 `filter` 中；后台高级配置支持编辑。播放源 API Token 等凭据只配置在管理端和服务端，不应放入客户端页面。

## 能力边界

当前支持页码分页、静态请求体、规则保存、测试、入库、自动调度与去重。任务状态与日志在进程内存中；无持久断点、游标分页、分布式采集锁或浏览器 JS 渲染。网页、数据库和文件导入细节见 [通用工作台](collection-studio.md)。生产启动、备份和升级见 [部署文档](../../deploy/README.md)。
