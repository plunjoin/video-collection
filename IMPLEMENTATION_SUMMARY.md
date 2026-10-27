# 一起看(Watch Together)功能实现总结

## PR信息
- **PR链接**: https://github.com/plunjoin/video-collection/pull/6
- **分支**: cursor/watch-together-m1-m2-59f4
- **状态**: ✅ Ready for Review

## 已完成的工作

### ✅ 核心功能 (M1 + M2)

1. **房间管理**
   - 创建房间并生成6位唯一短码
   - 最多支持6个参与者
   - 4小时自动过期
   - 房间状态包含视频ID、线路索引、集数索引

2. **权限控制**
   - 房主独享播放控制权 (play/pause/seek/rate/switch)
   - 成员只能观看,自动同步
   - 服务器端验证,非房主intent请求被拒绝

3. **WebSocket实时同步**
   - 服务器权威的PlaybackState (playing, position_ms, rate, revision等)
   - Hub管理所有活跃房间和连接
   - 房主操作立即广播给所有成员
   - 支持心跳保活

4. **房主断线处理**
   - 30秒等待期
   - 自动转移给最早加入的成员
   - 无人时自动关闭房间

5. **安全特性**
   - 所有接口需要登录验证
   - 房间码唯一性校验
   - 最大参与人数限制
   - 防止非房主控制

### ✅ 数据库

新增两张表,支持PostgreSQL和SQLite:

- `watch_rooms`: 房间信息(id, code, host_user_id, video_id, route_index, episode_index, status, max_participants, created_at, expires_at)
- `watch_participants`: 参与者信息(id, room_id, user_id, username, nickname, role, joined_at, left_at)

### ✅ API接口

**REST API**:
- POST `/api/watch/rooms` - 创建房间
- GET `/api/watch/rooms/by-code/{code}` - 根据短码获取房间
- GET `/api/watch/rooms/{id}/state` - 获取房间状态
- POST `/api/watch/rooms/{id}/join` - 加入房间
- POST `/api/watch/rooms/{id}/leave` - 离开房间
- POST `/api/watch/rooms/{id}/kick` - 踢出参与者(房主)
- POST `/api/watch/rooms/{id}/transfer` - 转移房主(当前房主)

**WebSocket API**:
- 连接: `ws://localhost/api/watch/ws?room_id={room_id}`
- 消息类型: welcome, state, intent, heartbeat

### ✅ 测试

- 单元测试: `pkg/watch/watch_test.go` ✅ 通过
- 集成测试脚本: `scripts/test-watch-together.sh`
- 编译测试: ✅ 无错误

### ✅ 文档

- 完整功能文档: `docs/watch-together.md`
- Nginx WebSocket配置: `deploy/nginx-websocket.md`
- API使用示例和客户端实现指南

## 技术栈

- **后端**: Go 1.26+
- **WebSocket**: gorilla/websocket v1.5.1
- **数据库**: PostgreSQL / SQLite (双路径支持)
- **架构**: Hub模式,内存状态管理

## 产品需求对照

| 需求 | 状态 |
|------|------|
| 服务器权威PlaybackState | ✅ |
| 房主独享控制权 | ✅ |
| App-first(后端优先) | ✅ |
| 短码分享 | ✅ |
| 最多6人 | ✅ |
| 4小时过期 | ✅ |
| 房主断线转移 | ✅ |
| 不污染user_history | ✅ (文档说明) |
| 不广播完整CDN URL | ✅ |
| 登录验证 | ✅ |

## 部署注意事项

1. **Nginx配置**: 需要添加WebSocket升级头 (见 `deploy/nginx-websocket.md`)
2. **HTTPS**: 使用wss://连接
3. **单实例**: 当前使用内存Hub,不支持多实例(未来可扩展Redis Pub/Sub)

## 客户端TODO

客户端需要实现:
1. 时间漂移检测和校正 (软阈值400ms / 硬阈值2s)
2. 一起看会话期间不写入user_history
3. 本地解析播放URL (不依赖服务器广播)

## 测试方法

```bash
# 运行单元测试
cd video-collection-service
go test ./pkg/watch/... -v

# 运行集成测试
./scripts/test-watch-together.sh

# 手动WebSocket测试 (需要wscat)
wscat -c "ws://localhost/api/watch/ws?room_id=1" \
  -H "Authorization: Bearer <token>"
```

## 文件清单

新增文件:
- `pkg/watch/models.go`
- `pkg/watch/store.go`
- `pkg/watch/hub.go`
- `pkg/watch/service.go`
- `pkg/watch/handler.go`
- `pkg/watch/watch_test.go`
- `docs/watch-together.md`
- `deploy/nginx-websocket.md`
- `scripts/test-watch-together.sh`

修改文件:
- `main.go` (集成watch服务)
- `pkg/store/postgres.go` (添加watch表)
- `pkg/store/sqlite.go` (添加watch表)
- `go.mod` / `go.sum` (添加gorilla/websocket)

## 后续工作 (Phase 2, 可选)

- [ ] Redis Pub/Sub支持多实例部署
- [ ] 聊天消息功能
- [ ] 房间密码保护
- [ ] 观看统计和回放
- [ ] Flutter客户端UI实现

---

**实现完成,Ready for Review!** ✅
