# RAG 知识库与向量检索

本服务在现有 **Wiki 关系图谱**（`/api/wiki/graph`）与采集入库流水线之上，增加可本地离线运行的 **分块 + 嵌入 + 相似度检索** 能力，为后续 LLM RAG 对话预留上下文接口。

## 架构关系

| 能力 | 路径 / 包 | 说明 |
|------|-----------|------|
| 结构化图谱 | `GET /api/wiki/graph?id=&depth=` | 节点/边拓扑，适合可视化与精确关系遍历 |
| 语义检索 | `GET/POST /api/admin/rag/search` | 返回 top-k 文本块 + 相似度 + 来源元数据，适合拼进 LLM prompt |
| 索引存储 | 表 `rag_chunks`（SQLite BLOB 向量） | `source_type`、`source_id`、`subject_id`、`chunk_index`、`text`、`metadata` |
| 分块逻辑 | `pkg/rag` | Wiki 摘要/属性卡/别名、关系上下文；已发布 `news`/`post` 正文 |

Wiki 词条变更、关系变更、`sync-video`、采集 `article` 入库后会 **异步增量索引**；也可随时 **全量重建**。

## 环境变量（嵌入）

| 变量 | 默认 | 说明 |
|------|------|------|
| `RAG_EMBEDDING_PROVIDER` | `fake` | `fake` 为确定性本地向量；设为 `openai` 且配置 Key 时走 OpenAI 兼容 Embeddings API |
| `RAG_EMBEDDING_DIM` | `384` | 假向量维度；OpenAI 时通常与模型输出一致 |
| `OPENAI_API_KEY` | 空 | 未设置时即使 `provider=openai` 也会回退 `fake` |
| `OPENAI_EMBEDDING_MODEL` | `text-embedding-3-small` | 嵌入模型名 |
| `OPENAI_BASE_URL` | OpenAI 官方 | 可指向兼容网关 |

无需付费云向量库；检索在应用层对 `rag_chunks` 做余弦相似度（适合中小规模）。后续可替换为 pgvector 实现。

## 管理员 API

需管理员 Bearer Token（与 Wiki 管理接口相同）。

### 全量重建索引

```bash
curl -s -X POST "http://localhost/api/admin/rag/rebuild" \
  -H "Authorization: Bearer <ADMIN_TOKEN>" \
  -H "Content-Type: application/json"
```

响应示例字段：`chunks_indexed`、`embedder`。

### 语义检索

GET：

```bash
curl -s "http://localhost/api/admin/rag/search?q=假面骑士空我&top_k=5&source_type=wiki_subject" \
  -H "Authorization: Bearer <ADMIN_TOKEN>"
```

POST：

```bash
curl -s -X POST "http://localhost/api/admin/rag/search" \
  -H "Authorization: Bearer <ADMIN_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"query":"皮套演员","top_k":8,"source_type":""}'
```

`data.results[]` 每项包含：`text`、`similarity`、`source_type`、`source_id`、`subject_id`、`metadata`。  
当 `subject_id > 0` 时，可再结合 `GET /api/wiki/graph?id=<subject_id>` 拉取关系子图 enrich 上下文。

### `source_type` 取值

- `wiki_subject` — 词条摘要/属性/别名
- `wiki_relation` — 以词条为中心的关系描述块
- `news` / `post` — 已发布资讯与社区帖

## 开发与测试

```bash
cd video-collection-service
go test ./pkg/rag/... ./pkg/api/... -run 'RAG|Wiki' -count=1
```

## 与 LLM 集成（后续）

1. 用户提问 → `POST /api/admin/rag/search`（或未来公开只读检索接口）取 top-k `text`。
2. 对 `subject_id` 调用 `/api/wiki/graph` 补充结构化邻居。
3. 将块文本与图谱摘要拼入 system/user prompt，调用外部 LLM。

现有 Wiki CRUD 与图谱 API **未改动契约**，仅增加索引钩子与管理端 RAG 接口。
