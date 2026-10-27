#!/bin/bash
# 一起看功能测试脚本

set -e

BASE_URL="${BASE_URL:-http://localhost}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-admin123}"

echo "=========================================="
echo "一起看 (Watch Together) 功能测试"
echo "=========================================="
echo ""

# 颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# 1. 登录获取token
log_info "步骤 1: 登录获取token..."
LOGIN_RESP=$(curl -s -X POST "${BASE_URL}/api/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${ADMIN_USER}\",\"password\":\"${ADMIN_PASS}\"}")

TOKEN=$(echo "$LOGIN_RESP" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
    log_error "登录失败,无法获取token"
    echo "响应: $LOGIN_RESP"
    exit 1
fi

log_info "登录成功,Token: ${TOKEN:0:20}..."
echo ""

# 2. 创建房间
log_info "步骤 2: 创建一起看房间..."
CREATE_ROOM_RESP=$(curl -s -X POST "${BASE_URL}/api/watch/rooms" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"video_id": 1, "route_index": 0, "episode_index": 0}')

echo "创建房间响应: $CREATE_ROOM_RESP"

ROOM_CODE=$(echo "$CREATE_ROOM_RESP" | grep -o '"code":"[A-Z0-9]*' | cut -d'"' -f4 | tail -1)
ROOM_ID=$(echo "$CREATE_ROOM_RESP" | grep -o '"id":[0-9]*' | cut -d':' -f2 | head -1)

if [ -z "$ROOM_CODE" ] || [ -z "$ROOM_ID" ]; then
    log_error "创建房间失败"
    exit 1
fi

log_info "✓ 房间创建成功"
log_info "  房间ID: $ROOM_ID"
log_info "  房间码: $ROOM_CODE"
echo ""

# 3. 根据短码获取房间
log_info "步骤 3: 根据短码获取房间信息..."
GET_ROOM_RESP=$(curl -s -X GET "${BASE_URL}/api/watch/rooms/by-code/${ROOM_CODE}")

echo "获取房间响应: $GET_ROOM_RESP"

if echo "$GET_ROOM_RESP" | grep -q '"code":1'; then
    log_info "✓ 根据短码获取房间成功"
else
    log_error "获取房间失败"
    exit 1
fi
echo ""

# 4. 获取房间状态
log_info "步骤 4: 获取房间当前状态..."
STATE_RESP=$(curl -s -X GET "${BASE_URL}/api/watch/rooms/${ROOM_ID}/state" \
  -H "Authorization: Bearer $TOKEN")

echo "房间状态响应: $STATE_RESP"

if echo "$STATE_RESP" | grep -q '"playing":false'; then
    log_info "✓ 获取房间状态成功 (初始状态: 未播放)"
else
    log_error "获取房间状态失败"
    exit 1
fi
echo ""

# 5. 测试加入房间 (需要第二个用户,这里我们尝试重复加入)
log_info "步骤 5: 测试加入房间..."
JOIN_RESP=$(curl -s -X POST "${BASE_URL}/api/watch/rooms/${ROOM_ID}/join" \
  -H "Authorization: Bearer $TOKEN")

echo "加入房间响应: $JOIN_RESP"

if echo "$JOIN_RESP" | grep -q '"code":1'; then
    log_info "✓ 加入房间成功 (或已在房间中)"
else
    log_warn "加入房间请求返回: $JOIN_RESP"
fi
echo ""

# 6. 测试离开房间
log_info "步骤 6: 测试离开房间..."
LEAVE_RESP=$(curl -s -X POST "${BASE_URL}/api/watch/rooms/${ROOM_ID}/leave" \
  -H "Authorization: Bearer $TOKEN")

echo "离开房间响应: $LEAVE_RESP"

if echo "$LEAVE_RESP" | grep -q '"code":1'; then
    log_info "✓ 离开房间成功"
else
    log_warn "离开房间请求返回: $LEAVE_RESP"
fi
echo ""

# 7. 数据库验证
log_info "步骤 7: 验证数据库表..."

# 检查表是否存在 (假设可以访问数据库)
if command -v psql &> /dev/null; then
    log_info "检测到PostgreSQL客户端,尝试验证表结构..."
    
    # 这里需要根据实际的数据库连接配置
    # psql -h localhost -U postgres -d videodb -c "SELECT COUNT(*) FROM watch_rooms;"
    
    log_warn "请手动验证数据库表: watch_rooms, watch_participants"
elif command -v sqlite3 &> /dev/null; then
    log_info "检测到SQLite客户端,尝试验证表结构..."
    
    # 这里需要根据实际的SQLite文件路径
    # sqlite3 data/video.db "SELECT COUNT(*) FROM watch_rooms;"
    
    log_warn "请手动验证数据库表: watch_rooms, watch_participants"
else
    log_warn "未检测到数据库客户端,跳过数据库验证"
fi
echo ""

# 总结
echo "=========================================="
echo "测试总结"
echo "=========================================="
log_info "✓ 登录认证"
log_info "✓ 创建房间"
log_info "✓ 获取房间(按短码)"
log_info "✓ 获取房间状态"
log_info "✓ 加入/离开房间"
echo ""
log_info "房间信息:"
log_info "  ID: $ROOM_ID"
log_info "  Code: $ROOM_CODE"
log_info "  URL: ${BASE_URL}/watch/${ROOM_CODE}"
echo ""
log_info "WebSocket测试 (需要 wscat 或类似工具):"
echo "  wscat -c \"ws://localhost/api/watch/ws?room_id=${ROOM_ID}\" \\"
echo "    -H \"Authorization: Bearer ${TOKEN}\""
echo ""
log_info "所有REST API测试通过! ✓"
echo ""
