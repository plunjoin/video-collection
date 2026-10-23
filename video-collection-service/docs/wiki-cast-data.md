# 采集数据对接 Wiki 演职员

视频入库后会 **自动同步** 到可编辑 Wiki（作品词条 + 演员/导演关系）。管理端仍可用 `POST /api/admin/wiki/sync-video` 手动重同步；重同步只回填空字段，不覆盖已有封面/简介。

## 端到端路径

1. **影视采集 / Webhook / 校正进视频库**  
   写入 `videos`：`picture`（封面）、`actor`、`director`（逗号/`/`/`、` 分隔人名）、`content` 等。  
   `UpsertVideo` 与「校正到视频」成功后会自动调用 `SyncVideoToWikiSubject`。

2. **作品 Wiki**  
   按片名建/绑 `type=work` 词条；空 `cover_image` ← `videos.picture`；空 `summary` ← `content`。

3. **人物 Wiki**  
   按演员/导演名建 stub 并建关系（`actor` / `director`）。  
   若 `collection_records` 中有同名影人记录且带 `avatar`/`cover`/`picture`/`profile_path` 与 `biography`/`summary`，则回填人物空封面/简介。

4. **影人单独采集**  
   工坊目标字段建议：`name`、`avatar`（或 `cover`）、`biography`、`role_type`。  
   管理台「转入 Wiki」或「批量校正」会按**词条名**合并：只填空，不覆盖管理员已编辑内容。

5. **前台**  
   视频已绑 `subject_id` 后，详情 API 返回 Wiki 演职员（含封面）；人物页读反向关系看关联作品。

## 字段对照

| 来源 | 字段 | Wiki |
| --- | --- | --- |
| 视频 | `picture` / 采集 `cover` / `vod_pic` | 作品 `cover_image`（空才写） |
| 视频 | `actor` / `director` | 人物名 + 关系 |
| 影人采集 | `avatar` / `cover` / `picture` / `profile_path` | 人物 `cover_image`（空才写） |
| 影人采集 | `biography` / `summary` / `overview` | 人物 `summary`（空才写） |

## 怎么用

- **新采集视频**：入库即自动出演职员；若同时采了同名影人封面，卡片会带图。  
- **只有人名、没有影人头像**：先出 stub，再采影人或后台改封面后，再点一次「同步到 Wiki」或等视频重采触发同步即可回填空封面。  
- **批量**：使魔结果「批量校正」→ 视频会进库并同步 Wiki；影人记录校正进 Wiki 后，再同步相关视频即可挂上封面。  
- **手动**：`POST /api/admin/wiki/sync-video`，body `{"video_id":123}`。

## 不会做的事

- 不覆盖 Wiki 里已有非空封面/简介（管理员编辑优先）。  
- 不把 TMDB/外部源当作唯一人物库；有什么采集数据就接什么。  
- ACG 多源（Bangumi 等）另开，不在本路径。
