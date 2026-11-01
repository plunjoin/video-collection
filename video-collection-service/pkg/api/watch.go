package api

import (
	"context"
	"crypto/rand"
	"errors"
	"log"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"video-collection-service/pkg/auth"
	"video-collection-service/pkg/store"
)

// 一起看（Watch Together）：房主控制播放，成员轮询心跳跟随。
// 同步模型：房间保存「锚点状态」（position_ms + anchor_ms + playing），
// 服务端读取时按墙上时钟推算 target_position_ms，客户端无需对时。

const (
	watchCodeAlphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ" // 去掉易混淆字符
	watchCodeLength   = 6
	watchRoomIdleTTL  = 30 * time.Minute // 全员失联后房间保留时长
	watchSweepEvery   = 5 * time.Minute  // 过期房间惰性清理周期
	watchMessageLimit = 100              // 单条聊天最长字符数（按 rune 计）
)

// watchHostStale 房主心跳失联阈值，超过则自动转让。var 仅为测试可缩短阈值。
var watchHostStale = 20 * time.Second

var (
	watchSweepMu     sync.Mutex
	watchLastSweep   time.Time
	watchCodeChars   = []rune(watchCodeAlphabet)
	errWatchNotHost  = errors.New("只有房主可以控制播放")
	errWatchNoMember = errors.New("请先加入房间")
)

// registerWatchRoutes 注册一起看房间路由。
func (srv *Server) registerWatchRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/api/watch/rooms", srv.handleWatchRooms)
	mux.HandleFunc("/api/watch/rooms/join", srv.handleWatchJoin)
	mux.HandleFunc("/api/watch/rooms/leave", srv.handleWatchLeave)
	mux.HandleFunc("/api/watch/rooms/state", srv.handleWatchState)
	mux.HandleFunc("/api/watch/rooms/heartbeat", srv.handleWatchHeartbeat)
	mux.HandleFunc("/api/watch/rooms/chat", srv.handleWatchChat)
	mux.HandleFunc("/api/watch/rooms/host", srv.handleWatchTransferHost)
	mux.HandleFunc("/api/watch/rooms/control", srv.handleWatchControlMode)
	srv.registerWatchEventRoutes(mux)
}

// handleWatchRooms 建房（POST）与房间详情（GET ?code=）。
func (srv *Server) handleWatchRooms(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPost:
		srv.createWatchRoom(w, r)
	case http.MethodGet:
		srv.getWatchRoom(w, r)
	default:
		errorResponse(w, http.StatusMethodNotAllowed, "Method Not Allowed")
	}
}

func (srv *Server) createWatchRoom(w http.ResponseWriter, r *http.Request) {
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	if u.Role == "observer" {
		errorResponse(w, http.StatusForbidden, "观察员无法发起一起看")
		return
	}
	var req struct {
		VideoID      int    `json:"video_id"`
		GroupIndex   int    `json:"group_index"`
		EpisodeIndex int    `json:"episode_index"`
		ControlMode  string `json:"control_mode"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	if req.VideoID < 1 {
		errorResponse(w, http.StatusBadRequest, "video_id 无效")
		return
	}
	controlMode := "host"
	if req.ControlMode != "" {
		if req.ControlMode != "host" && req.ControlMode != "all" {
			errorResponse(w, http.StatusBadRequest, "控制权限仅支持 host 或 all")
			return
		}
		controlMode = req.ControlMode
	}
	video, err := srv.store.GetVideoByID(r.Context(), req.VideoID)
	if err != nil || video == nil {
		errorResponse(w, http.StatusNotFound, "影片不存在或不可访问")
		return
	}
	if req.GroupIndex < 0 || req.GroupIndex >= len(video.PlayGroups) {
		errorResponse(w, http.StatusBadRequest, "线路编号无效")
		return
	}
	episodes := video.PlayGroups[req.GroupIndex].Episodes
	if req.EpisodeIndex < 0 || req.EpisodeIndex >= len(episodes) {
		errorResponse(w, http.StatusBadRequest, "剧集编号无效")
		return
	}
	// 建新房前回收自己名下已无他人活跃的旧房间，避免残留。
	_, _ = srv.store.RecycleHostRooms(r.Context(), u.ID, watchHostStale)

	nickname := watchDisplayName(u)
	room := &store.WatchRoom{
		VideoID:      req.VideoID,
		GroupIndex:   req.GroupIndex,
		EpisodeIndex: req.EpisodeIndex,
		Title:        watchRoomTitle(video.Name, episodes[req.EpisodeIndex].Name),
		HostID:       u.ID,
		Version:      1,
		Playing:      false,
		PositionMs:   0,
		ControlMode:  controlMode,
		UpdatedBy:    u.ID,
	}
	created := false
	for attempt := 0; attempt < 5 && !created; attempt++ {
		room.Code = generateWatchCode()
		if err = srv.store.CreateWatchRoom(r.Context(), room); err != nil {
			// 真实原因必须进日志（典型：旧库缺列等 schema 问题），否则只能看到笼统的 500。
			log.Printf("[watch] 创建房间失败(第 %d 次尝试): %v", attempt+1, err)
			continue
		}
		created = true
	}
	if !created {
		errorResponse(w, http.StatusInternalServerError, "房间创建失败，请重试")
		return
	}
	if err = srv.store.JoinWatchRoom(r.Context(), room.ID, u.ID, nickname, u.Avatar); err != nil {
		log.Printf("[watch] 房主加入房间失败 room=%d: %v", room.ID, err)
		errorResponse(w, http.StatusInternalServerError, "房间创建失败，请重试")
		return
	}
	srv.logSystem(r, "info", "watch", "创建一起看房间 "+room.Code, map[string]any{"video_id": room.VideoID, "user_id": u.ID})
	srv.watchHub.publishState(room.ID, room)
	srv.writeWatchSnapshot(w, r, room, u.ID, nil)
}

func (srv *Server) getWatchRoom(w http.ResponseWriter, r *http.Request) {
	code := strings.ToUpper(strings.TrimSpace(r.URL.Query().Get("code")))
	if len(code) != watchCodeLength {
		errorResponse(w, http.StatusBadRequest, "房间码无效")
		return
	}
	room, err := srv.store.GetWatchRoomByCode(r.Context(), code)
	if err != nil {
		writeWatchStoreError(w, err)
		return
	}
	var viewerID int
	if u := auth.GetCurrentUser(r, srv.store); u != nil {
		viewerID = u.ID
	}
	srv.writeWatchSnapshot(w, r, room, viewerID, nil)
}

// handleWatchJoin 加入房间，返回完整快照（状态+成员+最近消息）。
func (srv *Server) handleWatchJoin(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	if u.Role == "observer" {
		errorResponse(w, http.StatusForbidden, "观察员无法参与一起看")
		return
	}
	var req struct {
		Code string `json:"code"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	room, ok := srv.loadWatchRoom(w, r, req.Code)
	if !ok {
		return
	}
	if err := srv.store.JoinWatchRoom(r.Context(), room.ID, u.ID, watchDisplayName(u), u.Avatar); err != nil {
		errorResponse(w, http.StatusInternalServerError, "加入房间失败，请重试")
		return
	}
	srv.watchHub.publishState(room.ID, room)
	srv.writeWatchSnapshot(w, r, room, u.ID, nil)
}

// handleWatchLeave 离开房间；房主离开时立即转让，房间无人时解散。
func (srv *Server) handleWatchLeave(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	var req struct {
		Code string `json:"code"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	room, ok := srv.loadWatchRoom(w, r, req.Code)
	if !ok {
		return
	}
	if err := srv.store.LeaveWatchRoom(r.Context(), room.ID, u.ID); err != nil {
		errorResponse(w, http.StatusInternalServerError, "退出房间失败，请重试")
		return
	}
	if room.HostID == u.ID {
		_, _ = srv.store.EnsureWatchHost(r.Context(), room.ID, 0)
	}
	// 没有成员了就解散房间。
	if members, err := srv.store.ListWatchMembers(r.Context(), room.ID); err == nil && len(members) == 0 {
		_ = srv.store.DeleteWatchRoom(r.Context(), room.ID)
		srv.watchHub.publishClosed(room.ID)
	} else {
		srv.watchHub.publishState(room.ID, room)
	}
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "msg": "已退出房间"})
}

// handleWatchState 房主推送播放状态（播放/暂停/拖进度/切集）。
func (srv *Server) handleWatchState(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	var req struct {
		Code         string   `json:"code"`
		GroupIndex   *int     `json:"group_index"`
		EpisodeIndex *int     `json:"episode_index"`
		Playing      *bool    `json:"playing"`
		PositionMs   *int64   `json:"position_ms"`
		Rate         *float64 `json:"rate"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	room, ok := srv.loadWatchRoom(w, r, req.Code)
	if !ok {
		return
	}
	hostID, err := srv.store.EnsureWatchHost(r.Context(), room.ID, watchHostStale)
	if err != nil {
		writeWatchStoreError(w, err)
		return
	}
	if hostID != u.ID && !(room.ControlMode == "all" && isWatchMember(r.Context(), srv.store, room.ID, u.ID)) {
		if room.ControlMode == "all" {
			writeWatchError(w, errWatchNoMember)
		} else {
			writeWatchError(w, errWatchNotHost)
		}
		return
	}
	if req.GroupIndex != nil {
		if *req.GroupIndex < 0 {
			errorResponse(w, http.StatusBadRequest, "线路编号无效")
			return
		}
		room.GroupIndex = *req.GroupIndex
	}
	if req.EpisodeIndex != nil {
		if *req.EpisodeIndex < 0 {
			errorResponse(w, http.StatusBadRequest, "剧集编号无效")
			return
		}
		room.EpisodeIndex = *req.EpisodeIndex
	}
	if req.Playing != nil {
		room.Playing = *req.Playing
	}
	if req.PositionMs != nil {
		if *req.PositionMs < 0 || *req.PositionMs > 12*60*60*1000 {
			errorResponse(w, http.StatusBadRequest, "播放进度无效")
			return
		}
		room.PositionMs = *req.PositionMs
	}
	if req.Rate != nil {
		if *req.Rate < 0.25 || *req.Rate > 4 {
			errorResponse(w, http.StatusBadRequest, "倍速无效")
			return
		}
		room.Rate = *req.Rate
	}
	room.HostID = hostID
	room.UpdatedBy = u.ID
	if err = srv.store.UpdateWatchState(r.Context(), room); err != nil {
		writeWatchStoreError(w, err)
		return
	}
	srv.watchHub.publishState(room.ID, room)
	srv.writeWatchSnapshot(w, r, room, u.ID, nil)
}

// handleWatchHeartbeat 成员心跳：刷新在线状态，返回房间状态、成员与增量消息。
func (srv *Server) handleWatchHeartbeat(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	var req struct {
		Code       string `json:"code"`
		PositionMs int    `json:"position_ms"`
		SinceMsgID int    `json:"since_msg_id"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	room, ok := srv.loadWatchRoom(w, r, req.Code)
	if !ok {
		return
	}
	srv.sweepStaleWatchRooms(r.Context())
	// 心跳即在线；若成员记录丢失则自动补挂，保证弱网下不掉线。
	if err := srv.store.TouchWatchMember(r.Context(), room.ID, u.ID, req.PositionMs); err != nil {
		if errors.Is(err, store.ErrWatchNotMember) {
			if err = srv.store.JoinWatchRoom(r.Context(), room.ID, u.ID, watchDisplayName(u), u.Avatar); err != nil {
				errorResponse(w, http.StatusInternalServerError, "同步失败，请重试")
				return
			}
		} else {
			errorResponse(w, http.StatusInternalServerError, "同步失败，请重试")
			return
		}
	}
	originalHost := room.HostID
	hostID, err := srv.store.EnsureWatchHost(r.Context(), room.ID, watchHostStale)
	if err != nil {
		writeWatchStoreError(w, err)
		return
	}
	room.HostID = hostID

	// 房主心跳即时间线权威：每次心跳都把房间进度重锚到房主播放器的真实位置。
	// （不升版本，成员按漂移+节流平滑跟随；目标外推另有 5 秒硬上限。）
	// 仅当重锚使目标明显变化（>1.2s，即房主缓冲/未上报的 seek 等）时才广播，
	// 健康播放下保持 SSE 安静，成员靠外推即可。
	if hostID == u.ID && req.PositionMs > 0 {
		now := time.Now().UTC()
		previousTarget := room.TargetPositionMs(now)
		room.PositionMs = int64(req.PositionMs)
		room.AnchorMs = now.UnixMilli()
		_ = srv.store.UpdateWatchHostProgress(r.Context(), room.ID, room.PositionMs, room.AnchorMs)
		if newTarget := room.TargetPositionMs(now); watchAbsDiff(newTarget, previousTarget) > 1200 {
			srv.watchHub.publishState(room.ID, room)
		}
	}

	messages, err := srv.store.ListWatchMessages(r.Context(), room.ID, req.SinceMsgID, 50)
	if err != nil {
		messages = []store.WatchMessage{}
	}
	// 心跳触发的房主失联转让对所有人可见。
	if hostID != originalHost {
		srv.watchHub.publishState(room.ID, room)
	}
	srv.writeWatchSnapshot(w, r, room, u.ID, messages)
}

// handleWatchChat 房间聊天。
func (srv *Server) handleWatchChat(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	if u.Role == "observer" {
		errorResponse(w, http.StatusForbidden, "观察员无法发言")
		return
	}
	var req struct {
		Code    string `json:"code"`
		Content string `json:"content"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	room, ok := srv.loadWatchRoom(w, r, req.Code)
	if !ok {
		return
	}
	if !isWatchMember(r.Context(), srv.store, room.ID, u.ID) {
		writeWatchError(w, errWatchNoMember)
		return
	}
	content := strings.TrimSpace(req.Content)
	if !utf8.ValidString(content) || utf8.RuneCountInString(content) < 1 || utf8.RuneCountInString(content) > watchMessageLimit {
		errorResponse(w, http.StatusBadRequest, "聊天内容需要 1 到 100 个字")
		return
	}
	msg := &store.WatchMessage{RoomID: room.ID, UserID: u.ID, AuthorName: watchDisplayName(u), Content: content}
	if err := srv.store.AddWatchMessage(r.Context(), msg); err != nil {
		writeWatchStoreError(w, err)
		return
	}
	srv.watchHub.publishChat(room.ID, msg)
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": msg})
}

// handleWatchControlMode 房主切换播放控制权限（host=仅房主 / all=所有成员）。
func (srv *Server) handleWatchControlMode(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	var req struct {
		Code string `json:"code"`
		Mode string `json:"mode"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	if req.Mode != "host" && req.Mode != "all" {
		errorResponse(w, http.StatusBadRequest, "控制权限仅支持 host 或 all")
		return
	}
	room, ok := srv.loadWatchRoom(w, r, req.Code)
	if !ok {
		return
	}
	hostID, err := srv.store.EnsureWatchHost(r.Context(), room.ID, watchHostStale)
	if err != nil {
		writeWatchStoreError(w, err)
		return
	}
	if hostID != u.ID {
		writeWatchError(w, errWatchNotHost)
		return
	}
	if err = srv.store.SetWatchControlMode(r.Context(), room.ID, req.Mode); err != nil {
		writeWatchStoreError(w, err)
		return
	}
	room.ControlMode = req.Mode
	srv.logSystem(r, "info", "watch", "房间 "+room.Code+" 控制权限切换为 "+req.Mode, map[string]any{"user_id": u.ID, "mode": req.Mode})
	srv.watchHub.publishState(room.ID, room)
	srv.writeWatchSnapshot(w, r, room, u.ID, nil)
}

// handleWatchTransferHost 房主手动转让。
func (srv *Server) handleWatchTransferHost(w http.ResponseWriter, r *http.Request) {
	if !contentMethod(w, r, http.MethodPost) {
		return
	}
	u := contentUser(w, r, srv.store)
	if u == nil {
		return
	}
	var req struct {
		Code   string `json:"code"`
		UserID int    `json:"user_id"`
	}
	if !contentBody(w, r, &req) {
		return
	}
	room, ok := srv.loadWatchRoom(w, r, req.Code)
	if !ok {
		return
	}
	hostID, err := srv.store.EnsureWatchHost(r.Context(), room.ID, watchHostStale)
	if err != nil {
		writeWatchStoreError(w, err)
		return
	}
	if hostID != u.ID {
		writeWatchError(w, errWatchNotHost)
		return
	}
	if req.UserID == u.ID {
		errorResponse(w, http.StatusBadRequest, "已经是房主")
		return
	}
	if err = srv.store.SetWatchHost(r.Context(), room.ID, req.UserID); err != nil {
		writeWatchStoreError(w, err)
		return
	}
	room.HostID = req.UserID
	srv.watchHub.publishState(room.ID, room)
	srv.writeWatchSnapshot(w, r, room, u.ID, nil)
}

// ---- 内部工具 ----

func watchAbsDiff(a, b int64) int64 {
	d := a - b
	if d < 0 {
		return -d
	}
	return d
}

// isWatchMember 判断用户是否为房间成员。
func isWatchMember(ctx context.Context, s store.Store, roomID, userID int) bool {
	members, err := s.ListWatchMembers(ctx, roomID)
	if err != nil {
		return false
	}
	for _, m := range members {
		if m.UserID == userID {
			return true
		}
	}
	return false
}

func (srv *Server) loadWatchRoom(w http.ResponseWriter, r *http.Request, rawCode string) (*store.WatchRoom, bool) {
	code := strings.ToUpper(strings.TrimSpace(rawCode))
	if len(code) != watchCodeLength {
		errorResponse(w, http.StatusBadRequest, "房间码无效")
		return nil, false
	}
	room, err := srv.store.GetWatchRoomByCode(r.Context(), code)
	if err != nil {
		writeWatchStoreError(w, err)
		return nil, false
	}
	return room, true
}

// writeWatchSnapshot 输出房间快照：播放状态（含服务端推算的目标进度）、成员与增量消息。
func (srv *Server) writeWatchSnapshot(w http.ResponseWriter, r *http.Request, room *store.WatchRoom, viewerID int, messages []store.WatchMessage) {
	payload := srv.watchStatePayload(r.Context(), room)
	payload["viewer_is_host"] = viewerID != 0 && viewerID == room.HostID
	if messages == nil {
		messages = []store.WatchMessage{}
	}
	payload["messages"] = messages
	jsonResponse(w, http.StatusOK, map[string]any{"code": 1, "data": payload})
}

// sweepStaleWatchRooms 惰性清理全员失联的过期房间，全局每 5 分钟最多执行一次。
func (srv *Server) sweepStaleWatchRooms(ctx context.Context) {
	watchSweepMu.Lock()
	defer watchSweepMu.Unlock()
	if time.Since(watchLastSweep) < watchSweepEvery {
		return
	}
	watchLastSweep = time.Now()
	if _, err := srv.store.CleanStaleWatchRooms(ctx, watchRoomIdleTTL); err != nil {
		log.Printf("[watch] 清理过期房间失败: %v", err)
	}
}

func generateWatchCode() string {
	code := make([]rune, watchCodeLength)
	max := big.NewInt(int64(len(watchCodeChars)))
	for i := range code {
		n, err := rand.Int(rand.Reader, max)
		if err != nil {
			n = big.NewInt(time.Now().UnixNano() % int64(len(watchCodeChars)))
		}
		code[i] = watchCodeChars[n.Int64()]
	}
	return string(code)
}

func watchDisplayName(u *store.User) string {
	name := strings.TrimSpace(u.Nickname)
	if name == "" {
		name = u.Username
	}
	return name
}

func watchRoomTitle(videoName, episodeName string) string {
	title := strings.TrimSpace(videoName)
	if ep := strings.TrimSpace(episodeName); ep != "" {
		title += " · " + ep
	}
	return title
}

func writeWatchStoreError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, store.ErrWatchRoomNotFound):
		errorResponse(w, http.StatusNotFound, "房间不存在或已解散")
	case errors.Is(err, store.ErrWatchLimited):
		errorResponse(w, http.StatusTooManyRequests, "发送太频繁，请稍后再试")
	case errors.Is(err, store.ErrWatchNotMember):
		errorResponse(w, http.StatusForbidden, "请先加入房间")
	case errors.Is(err, store.ErrContentForbidden):
		errorResponse(w, http.StatusForbidden, "目标成员不在房间里")
	default:
		errorResponse(w, http.StatusInternalServerError, "操作失败，请稍后重试")
	}
}

func writeWatchError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, errWatchNotHost):
		errorResponse(w, http.StatusForbidden, "只有房主可以控制播放")
	case errors.Is(err, errWatchNoMember):
		errorResponse(w, http.StatusForbidden, "请先加入房间")
	default:
		errorResponse(w, http.StatusInternalServerError, "操作失败，请稍后重试")
	}
}
