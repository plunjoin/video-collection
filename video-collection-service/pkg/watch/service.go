package watch

import (
	"context"
	"fmt"
)

// Service 一起看服务
type Service struct {
	store Store
	hub   *Hub
}

// NewService 创建服务实例
func NewService(store Store) *Service {
	hub := NewHub(store)
	go hub.Run()
	
	return &Service{
		store: store,
		hub:   hub,
	}
}

// Stop 停止服务
func (s *Service) Stop() {
	s.hub.Stop()
}

// CreateRoom 创建房间
func (s *Service) CreateRoom(ctx context.Context, userID int, username, nickname string, req CreateRoomRequest) (*CreateRoomResponse, error) {
	// 验证视频ID
	if req.VideoID <= 0 {
		return nil, fmt.Errorf("invalid video_id")
	}
	
	// 创建房间
	room := &Room{
		HostUserID:      userID,
		VideoID:         req.VideoID,
		RouteIndex:      req.RouteIndex,
		EpisodeIndex:    req.EpisodeIndex,
		MaxParticipants: 6,
	}
	
	if err := s.store.CreateRoom(ctx, room); err != nil {
		return nil, fmt.Errorf("create room: %w", err)
	}
	
	// 添加房主为参与者
	participant := &Participant{
		RoomID:   room.ID,
		UserID:   userID,
		Username: username,
		Nickname: nickname,
		Role:     "host",
	}
	
	if err := s.store.AddParticipant(ctx, participant); err != nil {
		return nil, fmt.Errorf("add host participant: %w", err)
	}
	
	return &CreateRoomResponse{
		Room: *room,
		Code: room.Code,
	}, nil
}

// GetRoomByCode 根据短码获取房间信息
func (s *Service) GetRoomByCode(ctx context.Context, code string) (*RoomInfo, error) {
	room, err := s.store.GetRoomByCode(ctx, code)
	if err != nil {
		return nil, err
	}
	
	// 检查房间是否过期
	if room.Status != "active" {
		return nil, fmt.Errorf("room is not active")
	}
	
	participants, err := s.store.GetActiveParticipants(ctx, room.ID)
	if err != nil {
		return nil, fmt.Errorf("get participants: %w", err)
	}
	
	// 获取当前状态
	state, err := s.hub.GetState(room.ID)
	if err != nil {
		// 如果没有状态,返回初始状态
		state = &PlaybackState{
			Playing:      false,
			PositionMs:   0,
			Rate:         1.0,
			VideoID:      room.VideoID,
			RouteIndex:   room.RouteIndex,
			EpisodeIndex: room.EpisodeIndex,
			HostUserID:   room.HostUserID,
		}
	}
	
	return &RoomInfo{
		Room:         *room,
		Participants: participants,
		State:        *state,
	}, nil
}

// GetRoomByID 根据ID获取房间信息
func (s *Service) GetRoomByID(ctx context.Context, roomID int) (*RoomInfo, error) {
	room, err := s.store.GetRoomByID(ctx, roomID)
	if err != nil {
		return nil, err
	}
	
	participants, err := s.store.GetActiveParticipants(ctx, room.ID)
	if err != nil {
		return nil, fmt.Errorf("get participants: %w", err)
	}
	
	state, err := s.hub.GetState(room.ID)
	if err != nil {
		state = &PlaybackState{
			Playing:      false,
			PositionMs:   0,
			Rate:         1.0,
			VideoID:      room.VideoID,
			RouteIndex:   room.RouteIndex,
			EpisodeIndex: room.EpisodeIndex,
			HostUserID:   room.HostUserID,
		}
	}
	
	return &RoomInfo{
		Room:         *room,
		Participants: participants,
		State:        *state,
	}, nil
}

// JoinRoom 加入房间
func (s *Service) JoinRoom(ctx context.Context, roomID, userID int, username, nickname string) error {
	// 获取房间
	room, err := s.store.GetRoomByID(ctx, roomID)
	if err != nil {
		return fmt.Errorf("room not found: %w", err)
	}
	
	if room.Status != "active" {
		return fmt.Errorf("room is not active")
	}
	
	// 检查是否已经在房间中
	isParticipant, err := s.store.IsParticipant(ctx, roomID, userID)
	if err != nil {
		return fmt.Errorf("check participant: %w", err)
	}
	if isParticipant {
		return nil // 已经在房间中
	}
	
	// 检查房间人数
	participants, err := s.store.GetActiveParticipants(ctx, roomID)
	if err != nil {
		return fmt.Errorf("get participants: %w", err)
	}
	
	if len(participants) >= room.MaxParticipants {
		return fmt.Errorf("room is full")
	}
	
	// 添加参与者
	participant := &Participant{
		RoomID:   roomID,
		UserID:   userID,
		Username: username,
		Nickname: nickname,
		Role:     "member",
	}
	
	if err := s.store.AddParticipant(ctx, participant); err != nil {
		return fmt.Errorf("add participant: %w", err)
	}
	
	// 通知房间内其他人
	s.hub.broadcastParticipantUpdate(roomID)
	
	return nil
}

// LeaveRoom 离开房间
func (s *Service) LeaveRoom(ctx context.Context, roomID, userID int) error {
	return s.store.RemoveParticipant(ctx, roomID, userID)
}

// KickParticipant 踢出参与者(仅房主)
func (s *Service) KickParticipant(ctx context.Context, roomID, hostUserID, targetUserID int) error {
	// 验证房主权限
	room, err := s.store.GetRoomByID(ctx, roomID)
	if err != nil {
		return fmt.Errorf("room not found: %w", err)
	}
	
	if room.HostUserID != hostUserID {
		return fmt.Errorf("only host can kick participants")
	}
	
	if targetUserID == hostUserID {
		return fmt.Errorf("host cannot kick themselves")
	}
	
	// 移除参与者
	if err := s.store.RemoveParticipant(ctx, roomID, targetUserID); err != nil {
		return fmt.Errorf("remove participant: %w", err)
	}
	
	// 通知房间
	s.hub.broadcastParticipantUpdate(roomID)
	
	return nil
}

// TransferHost 转移房主(仅当前房主)
func (s *Service) TransferHost(ctx context.Context, roomID, currentHostUserID, newHostUserID int) error {
	// 验证当前房主
	room, err := s.store.GetRoomByID(ctx, roomID)
	if err != nil {
		return fmt.Errorf("room not found: %w", err)
	}
	
	if room.HostUserID != currentHostUserID {
		return fmt.Errorf("only current host can transfer host")
	}
	
	// 验证新房主是否在房间中
	isParticipant, err := s.store.IsParticipant(ctx, roomID, newHostUserID)
	if err != nil || !isParticipant {
		return fmt.Errorf("target user is not in the room")
	}
	
	// 更新数据库
	if err := s.store.UpdateParticipantRole(ctx, roomID, currentHostUserID, "member"); err != nil {
		return fmt.Errorf("update old host role: %w", err)
	}
	
	if err := s.store.UpdateParticipantRole(ctx, roomID, newHostUserID, "host"); err != nil {
		return fmt.Errorf("update new host role: %w", err)
	}
	
	room.HostUserID = newHostUserID
	if err := s.store.UpdateRoom(ctx, room); err != nil {
		return fmt.Errorf("update room: %w", err)
	}
	
	// 通知房间
	s.hub.broadcastParticipantUpdate(roomID)
	
	return nil
}

// GetHub 获取Hub(用于WebSocket处理)
func (s *Service) GetHub() *Hub {
	return s.hub
}
