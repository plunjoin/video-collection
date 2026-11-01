package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"time"

	"video-collection-service/pkg/store"
)

// 一起看的实时推送通道（SSE）。
//
// 设计：房内任何变更（播放状态 / 聊天 / 房主转让 / 控制权 / 成员增减 / 解散）
// 通过进程内 watchHub 即时广播给订阅者；客户端不再依赖 2 秒轮询获取状态，
// 心跳仅用于在线保活与本地进度上报（SSE 在线时放缓到 10 秒，回退轮询时 2 秒）。
// 选 SSE 而非 WebSocket：单向推送恰好匹配「房主→成员」的数据流，
// 且只需 Go 标准库（http.Flusher），不引入任何新依赖。

const (
	watchSSEPresenceEvery = 10 * time.Second // SSE 连接内成员保活周期
	watchSSEPingEvery     = 15 * time.Second // SSE 注释级 keepalive，防代理断连
)

// watchEvent 房间事件。Kind: state / chat / closed。
type watchEvent struct {
	Kind string              `json:"kind"`
	Room *store.WatchRoom    `json:"room,omitempty"`
	Chat *store.WatchMessage `json:"chat,omitempty"`
}

// watchHub 房间订阅表。发布为非阻塞：慢消费者丢弃事件，
// 由其心跳/下一轮状态对齐兜底（快照式推送，丢一帧不影响最终一致）。
type watchHub struct {
	mu   sync.Mutex
	subs map[int]map[chan watchEvent]struct{}
}

func newWatchHub() *watchHub {
	return &watchHub{subs: make(map[int]map[chan watchEvent]struct{})}
}

func (h *watchHub) subscribe(roomID int) (chan watchEvent, func()) {
	ch := make(chan watchEvent, 16)
	h.mu.Lock()
	if h.subs[roomID] == nil {
		h.subs[roomID] = make(map[chan watchEvent]struct{})
	}
	h.subs[roomID][ch] = struct{}{}
	h.mu.Unlock()
	return ch, func() {
		h.mu.Lock()
		if set, ok := h.subs[roomID]; ok {
			delete(set, ch)
			if len(set) == 0 {
				delete(h.subs, roomID)
			}
		}
		h.mu.Unlock()
	}
}

func (h *watchHub) publish(roomID int, event watchEvent) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for ch := range h.subs[roomID] {
		select {
		case ch <- event:
		default: // 订阅者积压则丢弃，客户端靠周期心跳兜底
		}
	}
}

func (h *watchHub) publishState(roomID int, room *store.WatchRoom) {
	h.publish(roomID, watchEvent{Kind: "state", Room: room})
}

func (h *watchHub) publishChat(roomID int, msg *store.WatchMessage) {
	h.publish(roomID, watchEvent{Kind: "chat", Chat: msg})
}

func (h *watchHub) publishClosed(roomID int) {
	h.publish(roomID, watchEvent{Kind: "closed"})
}

// registerWatchRoutes 中的 events 路由在此注册，避免与 watch.go 循环依赖。
func (srv *Server) registerWatchEventRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/api/watch/rooms/events", srv.handleWatchEvents)
}

// handleWatchEvents SSE 房间事件流（GET）。EventSource 无法携带 Authorization 头，
// 网页端通过 token 查询参数鉴权（自部署场景，风险可控）。
func (srv *Server) handleWatchEvents(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
		return
	}
	if tk := r.URL.Query().Get("token"); tk != "" && r.Header.Get("Authorization") == "" {
		r.Header.Set("Authorization", "Bearer "+tk)
	}
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	room, ok := srv.loadWatchRoom(w, r, r.URL.Query().Get("code"))
	if !ok {
		return
	}
	// 断线重连的成员可能已被清理，自动补挂（与心跳同一语义）。
	if !isWatchMember(r.Context(), srv.store, room.ID, u.ID) {
		if err := srv.store.JoinWatchRoom(r.Context(), room.ID, u.ID, watchDisplayName(u), u.Avatar); err != nil {
			errorResponse(w, http.StatusInternalServerError, "加入房间失败，请重试")
			return
		}
		srv.watchHub.publishState(room.ID, room)
	}
	flusher, ok := w.(http.Flusher)
	if !ok {
		errorResponse(w, http.StatusInternalServerError, "当前环境不支持事件流")
		return
	}
	// 清除 Server 级 WriteTimeout（默认 30s 会掐断长连接）。
	rc := http.NewResponseController(w)
	_ = rc.SetWriteDeadline(time.Time{})

	w.Header().Set("Content-Type", "text/event-stream; charset=utf-8")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)

	writeEvent := func(kind string, payload any) bool {
		data, err := json.Marshal(payload)
		if err != nil {
			return true
		}
		if _, err = fmt.Fprintf(w, "event: %s\ndata: %s\n\n", kind, data); err != nil {
			return false
		}
		flusher.Flush()
		return true
	}
	writeComment := func(text string) bool {
		if _, err := fmt.Fprintf(w, ": %s\n\n", text); err != nil {
			return false
		}
		flusher.Flush()
		return true
	}

	// 立即下发当前快照，订阅者免等下一轮变更。
	if !writeEvent("state", srv.watchStatePayload(r.Context(), room)) {
		return
	}
	// 订阅动作放在初始快照之后，避免重复。
	events, cancel := srv.watchHub.subscribe(room.ID)
	defer cancel()

	presence := time.NewTicker(watchSSEPresenceEvery)
	defer presence.Stop()
	ping := time.NewTicker(watchSSEPingEvery)
	defer ping.Stop()

	for {
		select {
		case <-r.Context().Done():
			return
		case ev := <-events:
			switch ev.Kind {
			case "state":
				// 发布方带的是变更时的房间指针，这里以最新库内状态为准重取一次。
				if fresh, err := srv.store.GetWatchRoomByCode(r.Context(), ev.Room.Code); err == nil {
					if !writeEvent("state", srv.watchStatePayload(r.Context(), fresh)) {
						return
					}
				}
			case "chat":
				if !writeEvent("chat", ev.Chat) {
					return
				}
			case "closed":
				_ = writeEvent("closed", map[string]any{})
				return
			}
		case <-presence.C:
			// SSE 在线即保活：刷新 last_seen，房主失联判定与成员列表随之准确。
			_ = srv.store.TouchWatchMember(r.Context(), room.ID, u.ID, 0)
			_ = writeComment("ping")
		case <-ping.C:
			if !writeComment("ping") {
				return
			}
		}
	}
}

// watchStatePayload 房间状态载荷（与心跳 data 同构）。
// 不含 viewer_is_host —— SSE 是广播，观看者身份由客户端按 host_id 自行判定。
func (srv *Server) watchStatePayload(ctx context.Context, room *store.WatchRoom) map[string]any {
	now := time.Now().UTC()
	members, err := srv.store.ListWatchMembers(ctx, room.ID)
	if err != nil {
		members = []store.WatchMember{}
	}
	memberItems := make([]map[string]any, 0, len(members))
	for _, m := range members {
		memberItems = append(memberItems, map[string]any{
			"user_id":     m.UserID,
			"nickname":    m.Nickname,
			"avatar":      m.Avatar,
			"position_ms": m.PositionMs,
			"is_host":     m.UserID == room.HostID,
			"last_seen":   m.LastSeenAt.Format(time.RFC3339),
		})
	}
	return map[string]any{
		"code":               room.Code,
		"video_id":           room.VideoID,
		"group_index":        room.GroupIndex,
		"episode_index":      room.EpisodeIndex,
		"title":              room.Title,
		"host_id":            room.HostID,
		"version":            room.Version,
		"playing":            room.Playing,
		"position_ms":        room.PositionMs,
		"anchor_ms":          room.AnchorMs,
		"rate":               room.Rate,
		"control_mode":       room.ControlMode,
		"target_position_ms": room.TargetPositionMs(now),
		"updated_by":         room.UpdatedBy,
		"members":            memberItems,
		"server_time_ms":     now.UnixMilli(),
	}
}
