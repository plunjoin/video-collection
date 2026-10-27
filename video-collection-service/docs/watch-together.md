# Bllii 一起看 (Watch Together) 功能

## 概述

一起看功能允许多个用户实时同步观看视频,房主控制播放进度,其他成员自动同步。

## 架构设计

### 核心组件

1. **Room (房间)**: 一起看的会话单位
   - 每个房间有唯一的6位短码用于分享
   - 最多6个参与者
   - 创建后4小时自动过期
   - 支持视频、线路、集数切换

2. **Participant (参与者)**: 房间内的用户
   - `host`: 房主,拥有控制权
   - `member`: 普通成员,只能观看

3. **PlaybackState (播放状态)**: 服务器权威的播放状态
   - 包含播放/暂停、位置、倍速等信息
   - 每次更新递增revision版本号
   - 由Hub统一管理并广播

4. **Hub (房间中心)**: WebSocket连接管理
   - 管理所有活跃房间和连接
   - 处理房主意图并更新状态
   - 广播状态更新到所有参与者
   - 处理房主断线和权限转移

### 数据库表

#### watch_rooms
```sql
CREATE TABLE watch_rooms (
    id SERIAL PRIMARY KEY,
    code VARCHAR(16) UNIQUE NOT NULL,
    host_user_id INT NOT NULL,
    video_id INT NOT NULL,
    route_index INT NOT NULL DEFAULT 0,
    episode_index INT NOT NULL DEFAULT 0,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    max_participants INT NOT NULL DEFAULT 6,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL
);
```

#### watch_participants
```sql
CREATE TABLE watch_participants (
    id SERIAL PRIMARY KEY,
    room_id INT NOT NULL,
    user_id INT NOT NULL,
    username VARCHAR(64) NOT NULL,
    nickname VARCHAR(64) NOT NULL DEFAULT '',
    role VARCHAR(32) NOT NULL DEFAULT 'member',
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    left_at TIMESTAMPTZ
);
```

## API 接口

### REST API

#### 1. 创建房间
```
POST /api/watch/rooms
Content-Type: application/json
Authorization: Bearer <token>

{
  "video_id": 123,
  "route_index": 0,
  "episode_index": 0
}

Response:
{
  "code": 1,
  "msg": "房间创建成功",
  "data": {
    "room": {
      "id": 1,
      "code": "ABC123",
      "host_user_id": 1,
      "video_id": 123,
      "route_index": 0,
      "episode_index": 0,
      "status": "active",
      "max_participants": 6,
      "created_at": "2026-10-27T16:00:00Z",
      "expires_at": "2026-10-27T20:00:00Z"
    },
    "code": "ABC123"
  }
}
```

#### 2. 根据短码获取房间
```
GET /api/watch/rooms/by-code/{code}

Response:
{
  "code": 1,
  "data": {
    "room": {...},
    "participants": [...],
    "state": {
      "playing": false,
      "position_ms": 0,
      "rate": 1.0,
      "server_ts_ms": 1698412800000,
      "revision": 0,
      "video_id": 123,
      "route_index": 0,
      "episode_index": 0,
      "host_user_id": 1,
      "updated_at": "2026-10-27T16:00:00Z"
    }
  }
}
```

#### 3. 加入房间
```
POST /api/watch/rooms/{id}/join
Authorization: Bearer <token>

Response:
{
  "code": 1,
  "msg": "加入房间成功"
}
```

#### 4. 离开房间
```
POST /api/watch/rooms/{id}/leave
Authorization: Bearer <token>

Response:
{
  "code": 1,
  "msg": "已离开房间"
}
```

#### 5. 踢出参与者 (仅房主)
```
POST /api/watch/rooms/{id}/kick
Authorization: Bearer <token>
Content-Type: application/json

{
  "target_user_id": 2
}

Response:
{
  "code": 1,
  "msg": "已踢出参与者"
}
```

#### 6. 转移房主 (仅当前房主)
```
POST /api/watch/rooms/{id}/transfer
Authorization: Bearer <token>
Content-Type: application/json

{
  "new_host_user_id": 2
}

Response:
{
  "code": 1,
  "msg": "房主已转移"
}
```

#### 7. 获取房间状态
```
GET /api/watch/rooms/{id}/state
Authorization: Bearer <token>

Response:
{
  "code": 1,
  "data": {
    "room": {...},
    "participants": [...],
    "state": {...}
  }
}
```

### WebSocket API

#### 连接
```
ws://localhost/api/watch/ws?room_id={room_id}
Authorization: Bearer <token>
```

#### 消息格式

所有消息都是JSON格式:
```json
{
  "type": "message_type",
  "data": {...}
}
```

#### 服务器 → 客户端

##### welcome (连接成功)
```json
{
  "type": "welcome",
  "data": {
    "state": {...},
    "participants": [...]
  }
}
```

##### state (状态更新)
```json
{
  "type": "state",
  "data": {
    "state": {
      "playing": true,
      "position_ms": 5000,
      "rate": 1.0,
      "server_ts_ms": 1698412800000,
      "revision": 1,
      "video_id": 123,
      "route_index": 0,
      "episode_index": 0,
      "host_user_id": 1,
      "updated_at": "2026-10-27T16:00:00Z"
    },
    "participants": [...]
  }
}
```

##### heartbeat (心跳响应)
```json
{
  "type": "heartbeat",
  "data": {
    "ts": 1698412800000
  }
}
```

#### 客户端 → 服务器

##### intent (房主控制意图,仅房主可发送)
```json
{
  "type": "intent",
  "data": {
    "action": "play"  // play | pause | seek | rate | switch
  }
}
```

###### play (播放)
```json
{
  "type": "intent",
  "data": {
    "action": "play"
  }
}
```

###### pause (暂停)
```json
{
  "type": "intent",
  "data": {
    "action": "pause"
  }
}
```

###### seek (跳转)
```json
{
  "type": "intent",
  "data": {
    "action": "seek",
    "position": 5000  // 毫秒
  }
}
```

###### rate (调速)
```json
{
  "type": "intent",
  "data": {
    "action": "rate",
    "rate": 1.5
  }
}
```

###### switch (切换剧集)
```json
{
  "type": "intent",
  "data": {
    "action": "switch",
    "route_index": 0,
    "episode_index": 1
  }
}
```

##### heartbeat (心跳)
```json
{
  "type": "heartbeat",
  "data": {}
}
```

## 客户端实现指南

### 时间同步算法

客户端需要实现时间漂移检测和自动校正:

```javascript
// 计算期望位置
function calculateExpectedPosition(state) {
  if (!state.playing) {
    return state.position_ms;
  }
  
  const now = Date.now();
  const elapsedMs = (now - state.server_ts_ms) * state.rate;
  return state.position_ms + elapsedMs;
}

// 检查是否需要校正
function shouldCorrect(playerPosition, expectedPosition) {
  const diff = Math.abs(playerPosition - expectedPosition);
  const SOFT_THRESHOLD = 400;  // 软阈值
  const HARD_THRESHOLD = 2000; // 硬阈值
  
  if (diff > HARD_THRESHOLD) {
    // 立即强制seek
    return { type: 'hard', position: expectedPosition };
  } else if (diff > SOFT_THRESHOLD) {
    // 调整播放速率追赶
    const adjustment = (playerPosition < expectedPosition) ? 1.05 : 0.95;
    return { type: 'soft', rate: state.rate * adjustment };
  }
  
  return null;
}
```

### 防止用户历史污染

一起看会话期间,**不要写入**个人的user_history:

```javascript
// 检查是否在一起看模式
if (isInWatchTogetherSession) {
  // 不上报进度到 /api/user/history
  return;
}

// 正常观看时才上报
saveUserHistory(videoId, position);
```

或者在后端明确标记和隔离:

```go
// 可选: 添加 watch_session_id 字段到 user_history
// 后端可以据此过滤掉一起看产生的历史记录
```

### 房主断线处理

- 房主断线后,服务器会等待30秒
- 如果30秒内房主没有重连,自动转移给最早加入的成员
- 客户端监听`state`消息的`host_user_id`变化

### 媒体解析

客户端**不要通过WebSocket传输完整的CDN播放URL**:

```javascript
// ❌ 错误: 广播完整URL
ws.send({ type: 'url', data: { url: 'https://cdn.example.com/video.m3u8' }});

// ✅ 正确: 只传递索引,客户端本地解析
const playUrl = resolvePlayUrl(state.video_id, state.route_index, state.episode_index);
player.load(playUrl);
```

## 测试

### 单元测试
```bash
go test ./pkg/watch/... -v
```

### 集成测试 (手动)

1. 启动服务
```bash
cd video-collection-service
go run main.go main_bootstrap.go
```

2. 创建房间
```bash
curl -X POST http://localhost/api/watch/rooms \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"video_id": 1, "route_index": 0, "episode_index": 0}'
```

3. 加入房间
```bash
curl -X POST http://localhost/api/watch/rooms/1/join \
  -H "Authorization: Bearer <token>"
```

4. WebSocket测试(使用wscat)
```bash
wscat -c "ws://localhost/api/watch/ws?room_id=1" \
  -H "Authorization: Bearer <token>"

# 发送播放指令(房主)
> {"type":"intent","data":{"action":"play"}}

# 接收状态更新
< {"type":"state","data":{...}}
```

## 安全注意事项

1. **身份验证**: 所有接口都需要登录
2. **权限控制**: 只有房主可以发送控制意图
3. **房间访问**: 只有参与者可以连接WebSocket
4. **短码唯一性**: 自动重试确保短码不重复
5. **房间过期**: 4小时后自动关闭
6. **最大人数**: 限制为6人

## 部署配置

### Nginx WebSocket 升级头

如果使用Nginx反向代理,需要配置WebSocket升级:

```nginx
location /api/watch/ws {
    proxy_pass http://backend;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_read_timeout 86400;
}
```

### 环境变量

无需额外环境变量,自动使用现有数据库连接。

## 未来扩展

### Phase 2 (可选)

- [ ] Redis Pub/Sub支持多实例部署
- [ ] 聊天消息功能
- [ ] 房间密码保护
- [ ] 观看统计和回放
- [ ] 自定义房间头像/名称

### Phase 3 (可选)

- [ ] 语音通话集成
- [ ] 表情反应功能
- [ ] 房间录制功能
- [ ] 推荐算法优化

## 限制和已知问题

1. **单实例部署**: 当前实现使用内存Hub,不支持多实例
   - 解决方案: 后续可集成Redis Pub/Sub
   
2. **网络延迟**: 200ms+ 延迟可能影响同步体验
   - 缓解措施: 客户端实现软/硬阈值校正

3. **CDN限制**: 某些CDN可能限制并发播放
   - 注意事项: 不广播完整URL,客户端本地解析

## 相关文件

- `pkg/watch/models.go` - 数据模型
- `pkg/watch/store.go` - 数据库存储
- `pkg/watch/hub.go` - WebSocket中心
- `pkg/watch/service.go` - 业务逻辑
- `pkg/watch/handler.go` - HTTP/WebSocket处理器
- `pkg/store/postgres.go` - PostgreSQL schema
- `pkg/store/sqlite.go` - SQLite schema

## License

与主项目相同
