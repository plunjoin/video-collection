# 通用采集 Webhook

外部采集器（本机 `acg-news` 或其它推送方）可通过 Webhook 把资讯推进 **现有资讯管理** 流程，不另建表。

## 写入链路

```
POST /api/webhooks/collector
  → HMAC 验签（原始 body）
  → SaveCollectionRecord(target=article, source_id=<collector>)
  → content_entries (kind=news, 默认 draft)
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
| `content` | `summary_zh`，否则 `text_zh`，否则标题 |
| `summary` | `summary_zh` |
| `cover` | `images[]` 中第一条远程 `http(s)` URL（忽略 `local_path`） |
| `category` | `category` |
| `status` | 固定 `draft`（与其它采集器一致；已发布条目不会被覆盖） |

幂等键：`record_key = source + ":" + id`（无 `source` 时仅用 `id`）。`source_id`（采集器身份）默认 `acg-news`，可用查询参数 `?collector=` 或请求头 `X-Collector-Id` 指定，便于多采集器共用同一接口。

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

### 环境变量

| 变量 | 说明 |
| --- | --- |
| `COLLECTOR_WEBHOOK_SECRET` | 优先使用的验签密钥 |
| `ACG_WEBHOOK_SECRET` | 兼容 acg-news；仅当未设置 `COLLECTOR_WEBHOOK_SECRET` 时使用 |

未配置任一密钥时返回 **503**。签名错误返回 **401**。

### 成功响应

```json
{"ok":true,"received":2,"inserted":1,"updated":1,"source_id":"acg-news"}
```

## 本机对接 acg-news

1. 启动 `video-collection-service`（例如 `PORT=8080`，SQLite 或 Postgres）。
2. 两边使用同一密钥：

```bash
export ACG_WEBHOOK_SECRET='一串足够长的随机字符串'
# 服务端也可设 COLLECTOR_WEBHOOK_SECRET，与上面相同即可
```

3. 配置推送 URL：

```bash
export ACG_WEBHOOK_URL='http://127.0.0.1:8080/api/webhooks/collector'
# 或写入 /workspace/acg-news/config.json → webhook.url
```

4. 推送：

```bash
cd /workspace/acg-news
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

`config/collector_rules.yaml` 中已登记 `id: acg-news`、`type: webhook`、`enabled: false` 的来源条目；首次推送时若不存在也会自动补登记。
