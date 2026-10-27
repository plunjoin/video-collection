package watch

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true // 生产环境应该验证Origin
	},
}

// Handler HTTP API处理器
type Handler struct {
	service     *Service
	getUserFunc func(r *http.Request) (userID int, username, nickname string, authenticated bool)
}

// NewHandler 创建处理器
func NewHandler(service *Service, getUserFunc func(r *http.Request) (int, string, string, bool)) *Handler {
	return &Handler{
		service:     service,
		getUserFunc: getUserFunc,
	}
}

// RegisterRoutes 注册路由
func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/api/watch/rooms", h.handleCreateRoom)
	mux.HandleFunc("/api/watch/rooms/by-code/", h.handleGetRoomByCode)
	mux.HandleFunc("/api/watch/rooms/", h.handleRoomOperations)
	mux.HandleFunc("/api/watch/ws", h.handleWebSocket)
}

// handleCreateRoom POST /api/watch/rooms - 创建房间
func (h *Handler) handleCreateRoom(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		jsonError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}
	
	// 验证登录
	userID, username, nickname, authenticated := h.getUserFunc(r)
	if !authenticated {
		jsonError(w, http.StatusUnauthorized, "未登录")
		return
	}
	
	// 解析请求
	var req CreateRoomRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, http.StatusBadRequest, "参数解析失败")
		return
	}
	
	// 创建房间
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	
	resp, err := h.service.CreateRoom(ctx, userID, username, nickname, req)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, err.Error())
		return
	}
	
	jsonResponse(w, http.StatusOK, map[string]interface{}{
		"code": 1,
		"msg":  "房间创建成功",
		"data": resp,
	})
}

// handleGetRoomByCode GET /api/watch/rooms/by-code/:code - 根据短码获取房间
func (h *Handler) handleGetRoomByCode(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		jsonError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}
	
	// 提取code
	code := strings.TrimPrefix(r.URL.Path, "/api/watch/rooms/by-code/")
	if code == "" {
		jsonError(w, http.StatusBadRequest, "缺少房间码")
		return
	}
	
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	
	roomInfo, err := h.service.GetRoomByCode(ctx, code)
	if err != nil {
		jsonError(w, http.StatusNotFound, "房间不存在或已关闭")
		return
	}
	
	jsonResponse(w, http.StatusOK, map[string]interface{}{
		"code": 1,
		"data": roomInfo,
	})
}

// handleRoomOperations 处理房间操作
func (h *Handler) handleRoomOperations(w http.ResponseWriter, r *http.Request) {
	// 提取roomID
	pathParts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	if len(pathParts) < 4 {
		jsonError(w, http.StatusBadRequest, "Invalid path")
		return
	}
	
	roomIDStr := pathParts[3]
	roomID, err := strconv.Atoi(roomIDStr)
	if err != nil {
		jsonError(w, http.StatusBadRequest, "Invalid room ID")
		return
	}
	
	// 根据路径决定操作
	action := ""
	if len(pathParts) > 4 {
		action = pathParts[4]
	}
	
	switch action {
	case "join":
		h.handleJoinRoom(w, r, roomID)
	case "leave":
		h.handleLeaveRoom(w, r, roomID)
	case "kick":
		h.handleKickParticipant(w, r, roomID)
	case "transfer":
		h.handleTransferHost(w, r, roomID)
	case "state":
		h.handleGetState(w, r, roomID)
	default:
		jsonError(w, http.StatusNotFound, "Unknown action")
	}
}

// handleJoinRoom POST /api/watch/rooms/:id/join - 加入房间
func (h *Handler) handleJoinRoom(w http.ResponseWriter, r *http.Request, roomID int) {
	if r.Method != http.MethodPost {
		jsonError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}
	
	userID, username, nickname, authenticated := h.getUserFunc(r)
	if !authenticated {
		jsonError(w, http.StatusUnauthorized, "未登录")
		return
	}
	
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	
	if err := h.service.JoinRoom(ctx, roomID, userID, username, nickname); err != nil {
		jsonError(w, http.StatusBadRequest, err.Error())
		return
	}
	
	jsonResponse(w, http.StatusOK, map[string]interface{}{
		"code": 1,
		"msg":  "加入房间成功",
	})
}

// handleLeaveRoom POST /api/watch/rooms/:id/leave - 离开房间
func (h *Handler) handleLeaveRoom(w http.ResponseWriter, r *http.Request, roomID int) {
	if r.Method != http.MethodPost {
		jsonError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}
	
	userID, _, _, authenticated := h.getUserFunc(r)
	if !authenticated {
		jsonError(w, http.StatusUnauthorized, "未登录")
		return
	}
	
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	
	if err := h.service.LeaveRoom(ctx, roomID, userID); err != nil {
		jsonError(w, http.StatusInternalServerError, err.Error())
		return
	}
	
	jsonResponse(w, http.StatusOK, map[string]interface{}{
		"code": 1,
		"msg":  "已离开房间",
	})
}

// handleKickParticipant POST /api/watch/rooms/:id/kick - 踢出参与者
func (h *Handler) handleKickParticipant(w http.ResponseWriter, r *http.Request, roomID int) {
	if r.Method != http.MethodPost {
		jsonError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}
	
	userID, _, _, authenticated := h.getUserFunc(r)
	if !authenticated {
		jsonError(w, http.StatusUnauthorized, "未登录")
		return
	}
	
	var req struct {
		TargetUserID int `json:"target_user_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, http.StatusBadRequest, "参数解析失败")
		return
	}
	
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	
	if err := h.service.KickParticipant(ctx, roomID, userID, req.TargetUserID); err != nil {
		jsonError(w, http.StatusForbidden, err.Error())
		return
	}
	
	jsonResponse(w, http.StatusOK, map[string]interface{}{
		"code": 1,
		"msg":  "已踢出参与者",
	})
}

// handleTransferHost POST /api/watch/rooms/:id/transfer - 转移房主
func (h *Handler) handleTransferHost(w http.ResponseWriter, r *http.Request, roomID int) {
	if r.Method != http.MethodPost {
		jsonError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}
	
	userID, _, _, authenticated := h.getUserFunc(r)
	if !authenticated {
		jsonError(w, http.StatusUnauthorized, "未登录")
		return
	}
	
	var req struct {
		NewHostUserID int `json:"new_host_user_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, http.StatusBadRequest, "参数解析失败")
		return
	}
	
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	
	if err := h.service.TransferHost(ctx, roomID, userID, req.NewHostUserID); err != nil {
		jsonError(w, http.StatusForbidden, err.Error())
		return
	}
	
	jsonResponse(w, http.StatusOK, map[string]interface{}{
		"code": 1,
		"msg":  "房主已转移",
	})
}

// handleGetState GET /api/watch/rooms/:id/state - 获取房间状态
func (h *Handler) handleGetState(w http.ResponseWriter, r *http.Request, roomID int) {
	if r.Method != http.MethodGet {
		jsonError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}
	
	_, _, _, authenticated := h.getUserFunc(r)
	if !authenticated {
		jsonError(w, http.StatusUnauthorized, "未登录")
		return
	}
	
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	
	roomInfo, err := h.service.GetRoomByID(ctx, roomID)
	if err != nil {
		jsonError(w, http.StatusNotFound, "房间不存在")
		return
	}
	
	jsonResponse(w, http.StatusOK, map[string]interface{}{
		"code": 1,
		"data": roomInfo,
	})
}

// handleWebSocket WebSocket连接处理
func (h *Handler) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	// 验证登录
	userID, username, nickname, authenticated := h.getUserFunc(r)
	if !authenticated {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	
	// 获取roomID
	roomIDStr := r.URL.Query().Get("room_id")
	roomID, err := strconv.Atoi(roomIDStr)
	if err != nil || roomID <= 0 {
		http.Error(w, "Invalid room_id", http.StatusBadRequest)
		return
	}
	
	// 验证用户是否在房间中
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	
	isParticipant, err := h.service.store.IsParticipant(ctx, roomID, userID)
	if err != nil || !isParticipant {
		http.Error(w, "Not a participant", http.StatusForbidden)
		return
	}
	
	// 获取用户角色
	participants, _ := h.service.store.GetActiveParticipants(ctx, roomID)
	var role string
	for _, p := range participants {
		if p.UserID == userID {
			role = p.Role
			break
		}
	}
	
	// 升级到WebSocket
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[watch] WebSocket upgrade failed: %v", err)
		return
	}
	
	// 创建客户端
	client := &Client{
		hub:      h.service.GetHub(),
		roomID:   roomID,
		userID:   userID,
		username: username,
		nickname: nickname,
		role:     role,
		send:     make(chan []byte, 256),
		conn:     &gorillaConn{conn: conn},
	}
	
	// 注册客户端
	client.hub.register <- client
	
	// 启动读写协程
	go client.writePump()
	go client.readPump()
}

// gorillaCo对接 gorilla/websocket适配器
type gorillaConn struct {
	conn *websocket.Conn
}

func (c *gorillaConn) ReadMessage() (int, []byte, error) {
	return c.conn.ReadMessage()
}

func (c *gorillaConn) WriteMessage(messageType int, data []byte) error {
	return c.conn.WriteMessage(messageType, data)
}

func (c *gorillaConn) Close() error {
	return c.conn.Close()
}

// readPump 从WebSocket读取消息
func (c *Client) readPump() {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
	}()
	
	for {
		_, message, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("[watch] WebSocket error: %v", err)
			}
			break
		}
		
		// 解析消息
		var msg WSMessage
		if err := json.Unmarshal(message, &msg); err != nil {
			log.Printf("[watch] Failed to parse message: %v", err)
			continue
		}
		
		// 处理消息
		c.handleMessage(msg)
	}
}

// writePump 向WebSocket写入消息
func (c *Client) writePump() {
	ticker := time.NewTicker(54 * time.Second)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()
	
	for {
		select {
		case message, ok := <-c.send:
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			
			if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}
			
		case <-ticker.C:
			// 发送ping保持连接
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// handleMessage 处理WebSocket消息
func (c *Client) handleMessage(msg WSMessage) {
	switch msg.Type {
	case "intent":
		// 仅房主可以发送意图
		if c.role != "host" {
			return
		}
		
		var intent IntentMessage
		if err := json.Unmarshal(msg.Data, &intent); err != nil {
			log.Printf("[watch] Failed to parse intent: %v", err)
			return
		}
		
		if err := c.hub.HandleIntent(c.roomID, c.userID, intent); err != nil {
			log.Printf("[watch] Handle intent failed: %v", err)
		}
		
	case "heartbeat":
		// 心跳响应
		response := WSMessage{
			Type: "heartbeat",
			Data: json.RawMessage(`{"ts":` + strconv.FormatInt(time.Now().UnixMilli(), 10) + `}`),
		}
		data, _ := json.Marshal(response)
		select {
		case c.send <- data:
		default:
		}
	}
}

// jsonResponse 发送JSON响应
func jsonResponse(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

// jsonError 发送JSON错误响应
func jsonError(w http.ResponseWriter, status int, message string) {
	jsonResponse(w, status, map[string]interface{}{
		"code":  0,
		"error": message,
	})
}
