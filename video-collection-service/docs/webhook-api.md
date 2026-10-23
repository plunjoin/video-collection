# Webhook 回调采集 API

外部系统通过 HTTPS 回调把新增/更新的影片数据实时推送进平台，替代拉模式轮询。
每个回调端点（webhook）拥有独立密钥，平台侧完成 **验签 → 防重放 → 事件白名单 → 入库 → 原始报文留痕** 全链路。

交互式文档见服务的 `/docs`（Swagger UI）与 `/redoc`，规范 JSON 为 `/openapi.json`。

## 一、端点管理（管理员）

以下接口均需要管理员会话（Cookie `agg_auth_token` 或 `Authorization: Bearer <token>`）。

| 方法 | 路径 | 说明 |
| :--- | :--- | :--- |
| GET | `/api/admin/webhooks` | 端点列表（含密钥掩码 `secret_hint`） |
| POST | `/api/admin/webhooks` | 创建端点，**响应中的 `secret` 明文仅本次返回** |
| POST | `/api/admin/webhooks/secret?id=<id>` | 轮换密钥，旧密钥立即失效，新明文仅本次返回 |
| GET | `/api/admin/webhooks/deliveries?id=<id>&status=&keyword=&page=&page_size=` | 投递日志（含 `raw_body` 原始报文） |
| GET | `/api/admin/webhooks/stats?id=<id>` | 单端点统计（accepted / rejected / duplicate / error / ignored） |
| POST | `/api/admin/webhooks/deliveries/cleanup` | 清理投递日志：`days>0` 按保留天数，`days=0` 清空全部 |

创建参数：

```json
{
  "name": "标准影视内容源回调",
  "target": "video",
  "duplicate": "update",
  "events": ["video.upsert"],
  "source_id": "",
  "tolerance_sec": 300
}
```

| 字段 | 说明 |
| :--- | :--- |
| `target` | `video` 入库视频库；`record` 落入通用采集记录（采集工作台可再校正） |
| `duplicate` | `update` 覆盖更新（默认）；`skip` 已存在同名影片则跳过 |
| `events` | 事件白名单，空数组不限制；与报文中的 `event`/`type` 字段比对（忽略大小写） |
| `source_id` | 入视频库时归属的来源标识，默认 `webhook:<id>` |
| `tolerance_sec` | 时间戳容忍窗口（秒），`0` 表示不校验 |

密钥安全说明：

- 明文密钥只在 **创建** 与 **轮换** 两个响应中各返回一次，服务端不保存明文。
- 落库的是 AES-256-GCM 加密信封，加密主密钥按 `WEBHOOK_ENCRYPTION_KEY` > `ADMIN_INITIAL_PASSWORD` > 内置默认派生值 的优先级取得；更换主密钥后旧端点密钥需重新轮换才能验签。
- 任何读取接口只返回掩码（前 4 位 + `*`），投递日志不会记录密钥。

## 二、采集入口（公开，签名鉴权）

```
POST /api/admin 外的公开路径：POST /api/webhooks/{id}/ingest
```

无需登录会话，凭 **请求体 HMAC-SHA256 签名** 准入。上限 4 MB。

### 请求头

| 请求头 | 必填 | 说明 |
| :--- | :--- | :--- |
| `X-Webhook-Signature` | 是 | `sha256=<hex>`；也依次兼容 `X-Signature-256` / `X-Signature` / `X-Hub-Signature-256`（可省略 `sha256=` 前缀） |
| `X-Webhook-Timestamp` | 建议 | Unix 秒或 RFC3339；端点设置 `tolerance_sec>0` 时强校验，超出窗口拒绝（防重放） |

签名计算（对 **未解析的原始字节**）：

```
signature = HMAC_SHA256(secret, rawBody)   # hex 小写
X-Webhook-Signature: sha256=<signature>
```

### 载荷格式

兼容以下形态，字段兼容标准影视 JSON `vod_*` 键与短名（`name` / `pic` / `play_url` 等）：

```json
{ "event": "video.upsert", "data": { "list": [ { "vod_id": 123, "vod_name": "示例影片", "vod_pic": "https://cdn/p.jpg", "vod_play_from": "m3u8", "vod_play_url": "https://cdn/1.m3u8" } ] } }
```

也支持：`{"list":[...]}`、`{"data":[{...}]}`、`{"data":{...}}`、顶层数组 `[{...}]`、单条对象 `{...}`。

### 响应

| 状态码 | 场景 |
| :--- | :--- |
| 200 | 已入库（或事件被白名单忽略，`data.ignored=true`） |
| 401 | 签名校验失败 / 时间戳超出容忍窗口 |
| 400 | 请求体非法或解析不到视频条目 |
| 404 | 端点不存在或已停用（不泄露存在性） |
| 500 | 服务器内部错误 |

```json
{ "code": 1, "msg": "已接收 1 条视频数据", "data": { "imported": 1, "skipped": 0, "event": "video.upsert" } }
```

### 投递留痕

无论接受还是拒绝，每一次投递都会记录 `webhook_deliveries`：事件、状态、入库条数、错误原因、来源 IP 与 **完整原始报文**，用于审计、对账与重放；按 `days` 参数定期清理即可。

## 三、接入示例（curl）

```bash
SECRET="创建时返回的 64 位密钥"
BODY='{"event":"video.upsert","data":{"list":[{"vod_id":1,"vod_name":"示例影片","vod_play_from":"m3u8","vod_play_url":"https://cdn/1.m3u8"}]}}'
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $NF}')
curl -X POST "https://api.example.com/api/webhooks/wh_xxx/ingest" \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Signature: sha256=$SIG" \
  -H "X-Webhook-Timestamp: $(date +%s)" \
  -d "$BODY"
```

## 四、验证

```bash
cd video-collection-service
go test ./pkg/webhook/ ./pkg/api/ -run 'Webhook|Signature|Timestamp|Secret' -count=1
```

覆盖：签名正反向用例、时间戳窗口、事件白名单、去重策略、密钥轮换前后行为、投递留痕与清理、管理接口鉴权。
