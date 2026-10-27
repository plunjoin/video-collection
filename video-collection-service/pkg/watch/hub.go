package watch

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"
)

// Hub 房间中心,管理所有活跃的房间和WebSocket连接
type Hub struct {
	store       Store
	rooms       map[int]*RoomHub // roomID -> RoomHub
	mu          sync.RWMutex
	register    chan *Client
	unregister  chan *Client
	broadcast   chan *BroadcastMessage
	stopChan    chan struct{}
}

// RoomHub 单个房间的连接管理器
type RoomHub struct {
	roomID       int
	clients      map[int]*Client // userID -> Client
	state        *PlaybackState
	stateMu      sync.RWMutex
	hostDisconnectTimer *time.Timer
	mu           sync.RWMutex
}

// Client WebSocket客户端连接
type Client struct {
	hub      *Hub
	roomID   int
	userID   int
	username string
	nickname string
	role     string
	send     chan []byte
	conn     WSConnection
}

// WSConnection WebSocket连接接口
type WSConnection interface {
	ReadMessage() (messageType int, p []byte, err error)
	WriteMessage(messageType int, data []byte) error
	Close() error
}

// BroadcastMessage 广播消息
type BroadcastMessage struct {
	RoomID  int
	Message []byte
	Exclude int // 排除的userID(可选)
}

// WSMessage WebSocket消息格式
type WSMessage struct {
	Type string          `json:"type"`
	Data json.RawMessage `json:"data"`
}

// IntentMessage 房主意图消息
type IntentMessage struct {
	Action   string  `json:"action"` // play, pause, seek, rate, switch
	Position *int64  `json:"position,omitempty"`
	Rate     *float64 `json:"rate,omitempty"`
	RouteIndex   *int `json:"route_index,omitempty"`
	EpisodeIndex *int `json:"episode_index,omitempty"`
}

// StateMessage 播放状态消息
type StateMessage struct {
	State    PlaybackState `json:"state"`
	Participants []ParticipantInfo `json:"participants"`
}

// ParticipantInfo 参与者信息
type ParticipantInfo struct {
	UserID   int    `json:"user_id"`
	Username string `json:"username"`
	Nickname string `json:"nickname"`
	Role     string `json:"role"`
}

// CorrectMessage 时间校正消息
type CorrectMessage struct {
	ExpectedPosition int64 `json:"expected_position"`
	ServerTime       int64 `json:"server_time"`
}

// NewHub 创建房间中心
func NewHub(store Store) *Hub {
	return &Hub{
		store:      store,
		rooms:      make(map[int]*RoomHub),
		register:   make(chan *Client, 100),
		unregister: make(chan *Client, 100),
		broadcast:  make(chan *BroadcastMessage, 256),
		stopChan:   make(chan struct{}),
	}
}

// Run 启动Hub
func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			h.handleRegister(client)
		case client := <-h.unregister:
			h.handleUnregister(client)
		case msg := <-h.broadcast:
			h.handleBroadcast(msg)
		case <-h.stopChan:
			return
		}
	}
}

// Stop 停止Hub
func (h *Hub) Stop() {
	close(h.stopChan)
}

// handleRegister 处理客户端注册
func (h *Hub) handleRegister(client *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	
	roomHub, exists := h.rooms[client.roomID]
	if !exists {
		roomHub = &RoomHub{
			roomID:  client.roomID,
			clients: make(map[int]*Client),
			state:   nil,
		}
		h.rooms[client.roomID] = roomHub
	}
	
	roomHub.mu.Lock()
	roomHub.clients[client.userID] = client
	
	// 取消房主断线计时器(如果有)
	if roomHub.hostDisconnectTimer != nil {
		roomHub.hostDisconnectTimer.Stop()
		roomHub.hostDisconnectTimer = nil
	}
	roomHub.mu.Unlock()
	
	log.Printf("[watch] Client registered: room=%d user=%d(%s)", client.roomID, client.userID, client.username)
	
	// 发送欢迎消息和当前状态
	h.sendWelcome(client, roomHub)
}

// handleUnregister 处理客户端断开
func (h *Hub) handleUnregister(client *Client) {
	h.mu.RLock()
	roomHub, exists := h.rooms[client.roomID]
	h.mu.RUnlock()
	
	if !exists {
		return
	}
	
	roomHub.mu.Lock()
	delete(roomHub.clients, client.userID)
	clientCount := len(roomHub.clients)
	wasHost := client.role == "host"
	roomHub.mu.Unlock()
	
	close(client.send)
	
	log.Printf("[watch] Client unregistered: room=%d user=%d(%s)", client.roomID, client.userID, client.username)
	
	// 从数据库标记为已离开
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = h.store.RemoveParticipant(ctx, client.roomID, client.userID)
	
	// 如果房主断开
	if wasHost {
		if clientCount > 0 {
			// 启动30秒计时器,准备转移房主
			roomHub.mu.Lock()
			roomHub.hostDisconnectTimer = time.AfterFunc(30*time.Second, func() {
				h.transferHost(client.roomID)
			})
			roomHub.mu.Unlock()
			log.Printf("[watch] Host disconnected, starting 30s timer for room %d", client.roomID)
		} else {
			// 房间空了,关闭房间
			h.closeRoom(client.roomID)
		}
	} else if clientCount == 0 {
		// 最后一个人离开,关闭房间
		h.closeRoom(client.roomID)
	}
	
	// 通知其他人
	h.broadcastParticipantUpdate(client.roomID)
}

// handleBroadcast 处理广播消息
func (h *Hub) handleBroadcast(msg *BroadcastMessage) {
	h.mu.RLock()
	roomHub, exists := h.rooms[msg.RoomID]
	h.mu.RUnlock()
	
	if !exists {
		return
	}
	
	roomHub.mu.RLock()
	defer roomHub.mu.RUnlock()
	
	for userID, client := range roomHub.clients {
		if msg.Exclude > 0 && userID == msg.Exclude {
			continue
		}
		select {
		case client.send <- msg.Message:
		default:
			// 发送缓冲区满,跳过
			log.Printf("[watch] Send buffer full for user %d in room %d", userID, msg.RoomID)
		}
	}
}

// sendWelcome 发送欢迎消息
func (h *Hub) sendWelcome(client *Client, roomHub *RoomHub) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	
	// 获取当前状态
	roomHub.stateMu.RLock()
	state := roomHub.state
	roomHub.stateMu.RUnlock()
	
	// 如果没有状态,初始化
	if state == nil {
		room, err := h.store.GetRoomByID(ctx, client.roomID)
		if err != nil {
			log.Printf("[watch] Failed to get room %d: %v", client.roomID, err)
			return
		}
		
		state = &PlaybackState{
			Playing:      false,
			PositionMs:   0,
			Rate:         1.0,
			ServerTsMs:   time.Now().UnixMilli(),
			Revision:     0,
			VideoID:      room.VideoID,
			RouteIndex:   room.RouteIndex,
			EpisodeIndex: room.EpisodeIndex,
			HostUserID:   room.HostUserID,
			UpdatedAt:    time.Now(),
		}
		
		roomHub.stateMu.Lock()
		roomHub.state = state
		roomHub.stateMu.Unlock()
	}
	
	// 获取参与者列表
	participants, _ := h.store.GetActiveParticipants(ctx, client.roomID)
	participantInfos := make([]ParticipantInfo, 0, len(participants))
	for _, p := range participants {
		participantInfos = append(participantInfos, ParticipantInfo{
			UserID:   p.UserID,
			Username: p.Username,
			Nickname: p.Nickname,
			Role:     p.Role,
		})
	}
	
	welcomeMsg := WSMessage{
		Type: "welcome",
		Data: mustMarshal(StateMessage{
			State:        *state,
			Participants: participantInfos,
		}),
	}
	
	data := mustMarshal(welcomeMsg)
	select {
	case client.send <- data:
	default:
	}
}

// HandleIntent 处理房主意图
func (h *Hub) HandleIntent(roomID, userID int, intent IntentMessage) error {
	h.mu.RLock()
	roomHub, exists := h.rooms[roomID]
	h.mu.RUnlock()
	
	if !exists {
		return fmt.Errorf("room not found")
	}
	
	// 检查是否是房主
	roomHub.mu.RLock()
	client, ok := roomHub.clients[userID]
	roomHub.mu.RUnlock()
	
	if !ok || client.role != "host" {
		return fmt.Errorf("only host can control playback")
	}
	
	// 更新状态
	roomHub.stateMu.Lock()
	state := roomHub.state
	if state == nil {
		roomHub.stateMu.Unlock()
		return fmt.Errorf("state not initialized")
	}
	
	now := time.Now()
	state.Revision++
	state.ServerTsMs = now.UnixMilli()
	state.UpdatedAt = now
	
	switch intent.Action {
	case "play":
		state.Playing = true
	case "pause":
		state.Playing = false
	case "seek":
		if intent.Position != nil {
			state.PositionMs = *intent.Position
		}
	case "rate":
		if intent.Rate != nil && *intent.Rate > 0 {
			state.Rate = *intent.Rate
		}
	case "switch":
		if intent.RouteIndex != nil {
			state.RouteIndex = *intent.RouteIndex
		}
		if intent.EpisodeIndex != nil {
			state.EpisodeIndex = *intent.EpisodeIndex
		}
		state.PositionMs = 0
		state.Playing = false
	}
	
	roomHub.stateMu.Unlock()
	
	// 广播新状态
	h.BroadcastState(roomID)
	
	return nil
}

// BroadcastState 广播播放状态
func (h *Hub) BroadcastState(roomID int) {
	h.mu.RLock()
	roomHub, exists := h.rooms[roomID]
	h.mu.RUnlock()
	
	if !exists {
		return
	}
	
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	
	roomHub.stateMu.RLock()
	state := *roomHub.state
	roomHub.stateMu.RUnlock()
	
	participants, _ := h.store.GetActiveParticipants(ctx, roomID)
	participantInfos := make([]ParticipantInfo, 0, len(participants))
	for _, p := range participants {
		participantInfos = append(participantInfos, ParticipantInfo{
			UserID:   p.UserID,
			Username: p.Username,
			Nickname: p.Nickname,
			Role:     p.Role,
		})
	}
	
	stateMsg := WSMessage{
		Type: "state",
		Data: mustMarshal(StateMessage{
			State:        state,
			Participants: participantInfos,
		}),
	}
	
	data := mustMarshal(stateMsg)
	h.broadcast <- &BroadcastMessage{
		RoomID:  roomID,
		Message: data,
	}
}

// broadcastParticipantUpdate 广播参与者更新
func (h *Hub) broadcastParticipantUpdate(roomID int) {
	h.BroadcastState(roomID)
}

// transferHost 转移房主权限
func (h *Hub) transferHost(roomID int) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	
	// 获取最早加入的成员
	participants, err := h.store.GetActiveParticipants(ctx, roomID)
	if err != nil || len(participants) == 0 {
		// 没有参与者,关闭房间
		h.closeRoom(roomID)
		return
	}
	
	// 找到最早加入的成员
	var newHost *Participant
	for i := range participants {
		if participants[i].Role != "host" {
			newHost = &participants[i]
			break
		}
	}
	
	if newHost == nil {
		// 没有可转移的成员
		h.closeRoom(roomID)
		return
	}
	
	// 更新数据库
	_ = h.store.UpdateParticipantRole(ctx, roomID, newHost.UserID, "host")
	
	// 更新房间
	room, err := h.store.GetRoomByID(ctx, roomID)
	if err != nil {
		return
	}
	room.HostUserID = newHost.UserID
	_ = h.store.UpdateRoom(ctx, room)
	
	// 更新内存状态
	h.mu.RLock()
	roomHub, exists := h.rooms[roomID]
	h.mu.RUnlock()
	
	if exists {
		roomHub.mu.RLock()
		if client, ok := roomHub.clients[newHost.UserID]; ok {
			client.role = "host"
		}
		roomHub.mu.RUnlock()
		
		roomHub.stateMu.Lock()
		if roomHub.state != nil {
			roomHub.state.HostUserID = newHost.UserID
			roomHub.state.Revision++
			roomHub.state.UpdatedAt = time.Now()
		}
		roomHub.stateMu.Unlock()
	}
	
	log.Printf("[watch] Host transferred to user %d in room %d", newHost.UserID, roomID)
	
	// 广播更新
	h.BroadcastState(roomID)
}

// closeRoom 关闭房间
func (h *Hub) closeRoom(roomID int) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	
	_ = h.store.CloseRoom(ctx, roomID)
	
	h.mu.Lock()
	delete(h.rooms, roomID)
	h.mu.Unlock()
	
	log.Printf("[watch] Room %d closed", roomID)
}

// GetState 获取房间当前状态
func (h *Hub) GetState(roomID int) (*PlaybackState, error) {
	h.mu.RLock()
	roomHub, exists := h.rooms[roomID]
	h.mu.RUnlock()
	
	if !exists {
		return nil, fmt.Errorf("room not found")
	}
	
	roomHub.stateMu.RLock()
	defer roomHub.stateMu.RUnlock()
	
	if roomHub.state == nil {
		return nil, fmt.Errorf("state not initialized")
	}
	
	state := *roomHub.state
	return &state, nil
}

// mustMarshal JSON序列化(panic on error)
func mustMarshal(v interface{}) json.RawMessage {
	data, err := json.Marshal(v)
	if err != nil {
		panic(fmt.Sprintf("marshal failed: %v", err))
	}
	return data
}
