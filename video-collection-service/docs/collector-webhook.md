# 通用采集 Webhook

外部采集器（本机 `acg-news` 或其它推送方）默认通过 Webhook 把资讯推进 **现有资讯管理** 流程。也可在规则工坊为绑定源选择已注册的业务类型，写入视频、通用记录或自定义业务表，参见 [业务类型](business-types.md)。以下链路与字段说明展示默认文章模式。

## 默认文章写入链路

```
POST /api/webhooks/collector
  → 解析 source_id（头 / 查询参数）
  → 读取使魔节点配置（密钥、启用、过期）
  → HMAC 验签（原始 body）
  → SaveCollectionRecord(target=article, source_id=<collector>)
  → content_entries (kind=news；status 取自业务类型字段默认值，默认 published)
  → 管理端「资讯管理」/ GET /api/admin/news 、公开 GET /api/news（仅 published）
```

复用表：

| 表 | 作用 |
| --- | --- |
| `collection_records` | 采集溯源（`source_id` + `target=article` + `record_key`） |
| `content_entries` | 资讯正文（`kind=news`），与后台资讯管理同一套 |

字段映射（Values → 资讯）：

| 资讯字段 | 来源 |
| --- | --- |
| `title` | `title_zh`，否则 `title_original` |
| `content` | `summary_zh`，否则 `text_zh`；都空时合成「来源 / 原文 URL / title_original」可读正文 |
| `summary` | `summary_zh`（空时由正文截断生成） |
| `cover` | `images[]` 中第一条远程 `http(s)` URL（忽略 `local_path`） |
| `category` | `category` |
| `source_url` | `url`（原文链接，写入 `content_entries.source_url`） |
| `source_name` | `source_name`，否则 `source_label`，否则 `source` |
| `published_at` | `published_at`（原文发布时间，原样字符串） |
| `status` | 省略时用业务类型 `article.status` 字段默认值（内置为 `published`）；payload 可显式传 `draft`/`published`。同 key 再推会更新已发布稿（标题/摘要/正文/封面/分类/来源/发布时间/状态） |

管理后台「资讯管理」列表与编辑弹窗会展示来源、原文链接与发布时间；完整溯源仍在 `collection_records.payload`。

幂等键：`record_key = source + ":" + id`（无 `source` 时仅用 `id`）。`source_id`（采集器身份）默认 `acg-news`，可用查询参数 `?collector=` 或请求头 `X-ACG-Collector-Id` / `X-Collector-Id` 指定，便于多采集器共用同一接口。

## 端点

`POST /api/webhooks/collector`

### 请求

- Body：JSON **数组**（与 acg-news `push_webhook.py` 一致）
- Headers（acg-news 兼容）：
  - `Content-Type: application/json; charset=utf-8`
  - `X-ACG-Signature: sha256=<hex(HMAC_SHA256(secret, raw_body))>`
  - `X-ACG-Timestamp`（可选，不参与签名）
  - `X-ACG-Batch-Id`（可选）
- 也可使用通用头：`X-Collector-Signature`、`X-Collector-Id`、`X-Collector-Batch-Id`

### 密钥与开关（推荐：使魔节点管理）

与其它采集源的 token / `custom_params` 一样，在后台 **使魔节点管理** 配置：

1. 新增或编辑节点，协议选 **Webhook 推送**（`api` 填 `webhook://collector`）
2. 填写 **Webhook 密钥**（可点「生成」），可选 **密钥过期**（RFC3339）
3. **启用** 节点后开始接收；关闭节点 → 推送方收到 **403**「采集源已关闭」
4. 密钥过期 → **401**「Webhook 密钥已过期」
5. 把同一密钥交给推送方；推送 URL = `https://你的域名/api/webhooks/collector`

`custom_params` 字段：

| 键 | 说明 |
| --- | --- |
| `webhook_secret` | HMAC 密钥（优先于环境变量） |
| `webhook_secret_expires_at` | 可选过期时间 |

**临时接收**：启用节点 + 设置密钥 + 可选过期时间；到点自动拒收，或随时关闭节点 / 清空密钥。

验签密钥解析顺序：

1. 对应 `source_id` 的节点 `custom_params.webhook_secret`（且节点已启用、未过期）
2. 环境变量 `COLLECTOR_WEBHOOK_SECRET`，否则 `ACG_WEBHOOK_SECRET`（兼容旧部署；节点仍须启用）
3. 都没有 → **503**

签名错误 → **401**。

### 环境变量（仅兜底）

| 变量 | 说明 |
| --- | --- |
| `COLLECTOR_WEBHOOK_SECRET` | 节点未配置 `webhook_secret` 时的兜底密钥 |
| `ACG_WEBHOOK_SECRET` | 兼容 acg-news；仅当未设置 `COLLECTOR_WEBHOOK_SECRET` 时使用 |

日常请用后台配置，不必每次改环境变量。

### 成功响应

```json
{"ok":true,"received":2,"inserted":1,"updated":1,"source_id":"acg-news"}
```

## 本机对接 acg-news

1. 启动 `video-collection-service`（例如 `PORT=8080`，SQLite 或 Postgres）。
2. 在使魔节点管理中启用 `acg-news`（或新建 Webhook 节点），生成并保存密钥；或临时用环境变量兜底：

```bash
export ACG_WEBHOOK_SECRET='一串足够长的随机字符串'
# 服务端也可设 COLLECTOR_WEBHOOK_SECRET，与上面相同即可
```

3. 配置推送 URL：

```bash
export ACG_WEBHOOK_URL='http://127.0.0.1:8080/api/webhooks/collector'
# 或写入 acg-news config.json → webhook.url
```

4. 推送：

```bash
cd /path/to/acg-news
.venv/bin/python push_webhook.py --dry-run   # 预览
.venv/bin/python push_webhook.py             # 正式推送
```

5. 在管理后台「资讯管理」查看草稿，或：

```bash
# 采集溯源
curl -s 'http://127.0.0.1:8080/api/admin/collection/records?source_id=acg-news' -H "Authorization: Bearer <admin>"
# 资讯列表（管理员可见 draft）
curl -s 'http://127.0.0.1:8080/api/admin/news' -H "Authorization: Bearer <admin>"
```

`config/collector_rules.yaml` 中已登记 `id: acg-news`、`type: webhook`、`enabled: false` 的来源条目；首次推送时若不存在也会自动补登记（**不**自动生成密钥，需在后台配置密钥并启用）。
