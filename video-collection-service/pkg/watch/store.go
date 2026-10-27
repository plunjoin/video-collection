package watch

import (
	"context"
	"crypto/rand"
	"database/sql"
	"fmt"
	"time"
)

// Store 一起看功能的数据存储接口
type Store interface {
	// Room operations
	CreateRoom(ctx context.Context, room *Room) error
	GetRoomByID(ctx context.Context, id int) (*Room, error)
	GetRoomByCode(ctx context.Context, code string) (*Room, error)
	UpdateRoom(ctx context.Context, room *Room) error
	CloseRoom(ctx context.Context, roomID int) error
	
	// Participant operations
	AddParticipant(ctx context.Context, participant *Participant) error
	GetParticipants(ctx context.Context, roomID int) ([]Participant, error)
	GetActiveParticipants(ctx context.Context, roomID int) ([]Participant, error)
	RemoveParticipant(ctx context.Context, roomID int, userID int) error
	IsParticipant(ctx context.Context, roomID int, userID int) (bool, error)
	UpdateParticipantRole(ctx context.Context, roomID int, userID int, role string) error
}

// DBStore 基于SQL数据库的存储实现
type DBStore struct {
	db *sql.DB
}

// NewDBStore 创建数据库存储
func NewDBStore(db *sql.DB) *DBStore {
	return &DBStore{db: db}
}

// generateRoomCode 生成6位房间短码
func generateRoomCode() (string, error) {
	const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // 去除易混淆字符
	bytes := make([]byte, 3)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	
	code := make([]byte, 6)
	for i := 0; i < 6; i++ {
		if i < 3 {
			code[i] = chars[int(bytes[i])%len(chars)]
		} else {
			// 重新读取随机字节
			var b [1]byte
			rand.Read(b[:])
			code[i] = chars[int(b[0])%len(chars)]
		}
	}
	return string(code), nil
}

// CreateRoom 创建房间
func (s *DBStore) CreateRoom(ctx context.Context, room *Room) error {
	// 生成唯一的房间码
	var code string
	var err error
	maxRetries := 10
	for i := 0; i < maxRetries; i++ {
		code, err = generateRoomCode()
		if err != nil {
			return fmt.Errorf("generate room code: %w", err)
		}
		
		// 检查是否已存在
		var exists bool
		err = s.db.QueryRowContext(ctx, 
			"SELECT EXISTS(SELECT 1 FROM watch_rooms WHERE code = $1)", 
			code).Scan(&exists)
		if err != nil {
			return fmt.Errorf("check code uniqueness: %w", err)
		}
		if !exists {
			break
		}
		
		if i == maxRetries-1 {
			return fmt.Errorf("failed to generate unique room code after %d retries", maxRetries)
		}
	}
	
	room.Code = code
	if room.MaxParticipants == 0 {
		room.MaxParticipants = 6
	}
	if room.Status == "" {
		room.Status = "active"
	}
	
	now := time.Now()
	room.CreatedAt = now
	room.ExpiresAt = now.Add(4 * time.Hour)
	
	err = s.db.QueryRowContext(ctx, `
		INSERT INTO watch_rooms (code, host_user_id, video_id, route_index, episode_index, 
			status, max_participants, created_at, expires_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		RETURNING id
	`, room.Code, room.HostUserID, room.VideoID, room.RouteIndex, room.EpisodeIndex,
		room.Status, room.MaxParticipants, room.CreatedAt, room.ExpiresAt).Scan(&room.ID)
	
	if err != nil {
		return fmt.Errorf("insert room: %w", err)
	}
	
	return nil
}

// GetRoomByID 根据ID获取房间
func (s *DBStore) GetRoomByID(ctx context.Context, id int) (*Room, error) {
	room := &Room{}
	err := s.db.QueryRowContext(ctx, `
		SELECT id, code, host_user_id, video_id, route_index, episode_index, 
			status, max_participants, created_at, expires_at
		FROM watch_rooms
		WHERE id = $1
	`, id).Scan(&room.ID, &room.Code, &room.HostUserID, &room.VideoID, &room.RouteIndex,
		&room.EpisodeIndex, &room.Status, &room.MaxParticipants, &room.CreatedAt, &room.ExpiresAt)
	
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("room not found")
	}
	if err != nil {
		return nil, fmt.Errorf("query room: %w", err)
	}
	
	return room, nil
}

// GetRoomByCode 根据短码获取房间
func (s *DBStore) GetRoomByCode(ctx context.Context, code string) (*Room, error) {
	room := &Room{}
	err := s.db.QueryRowContext(ctx, `
		SELECT id, code, host_user_id, video_id, route_index, episode_index, 
			status, max_participants, created_at, expires_at
		FROM watch_rooms
		WHERE code = $1
	`, code).Scan(&room.ID, &room.Code, &room.HostUserID, &room.VideoID, &room.RouteIndex,
		&room.EpisodeIndex, &room.Status, &room.MaxParticipants, &room.CreatedAt, &room.ExpiresAt)
	
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("room not found")
	}
	if err != nil {
		return nil, fmt.Errorf("query room: %w", err)
	}
	
	return room, nil
}

// UpdateRoom 更新房间信息
func (s *DBStore) UpdateRoom(ctx context.Context, room *Room) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE watch_rooms 
		SET host_user_id = $1, video_id = $2, route_index = $3, episode_index = $4, 
			status = $5, max_participants = $6
		WHERE id = $7
	`, room.HostUserID, room.VideoID, room.RouteIndex, room.EpisodeIndex,
		room.Status, room.MaxParticipants, room.ID)
	
	if err != nil {
		return fmt.Errorf("update room: %w", err)
	}
	
	return nil
}

// CloseRoom 关闭房间
func (s *DBStore) CloseRoom(ctx context.Context, roomID int) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE watch_rooms SET status = 'closed' WHERE id = $1
	`, roomID)
	
	if err != nil {
		return fmt.Errorf("close room: %w", err)
	}
	
	return nil
}

// AddParticipant 添加参与者
func (s *DBStore) AddParticipant(ctx context.Context, participant *Participant) error {
	now := time.Now()
	participant.JoinedAt = now
	
	err := s.db.QueryRowContext(ctx, `
		INSERT INTO watch_participants (room_id, user_id, username, nickname, role, joined_at)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id
	`, participant.RoomID, participant.UserID, participant.Username, participant.Nickname,
		participant.Role, participant.JoinedAt).Scan(&participant.ID)
	
	if err != nil {
		return fmt.Errorf("insert participant: %w", err)
	}
	
	return nil
}

// GetParticipants 获取房间所有参与者(包括已离开的)
func (s *DBStore) GetParticipants(ctx context.Context, roomID int) ([]Participant, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, room_id, user_id, username, nickname, role, joined_at, left_at
		FROM watch_participants
		WHERE room_id = $1
		ORDER BY joined_at ASC
	`, roomID)
	
	if err != nil {
		return nil, fmt.Errorf("query participants: %w", err)
	}
	defer rows.Close()
	
	var participants []Participant
	for rows.Next() {
		var p Participant
		var leftAt sql.NullTime
		err := rows.Scan(&p.ID, &p.RoomID, &p.UserID, &p.Username, &p.Nickname,
			&p.Role, &p.JoinedAt, &leftAt)
		if err != nil {
			return nil, fmt.Errorf("scan participant: %w", err)
		}
		if leftAt.Valid {
			p.LeftAt = &leftAt.Time
		}
		participants = append(participants, p)
	}
	
	return participants, nil
}

// GetActiveParticipants 获取房间当前活跃的参与者
func (s *DBStore) GetActiveParticipants(ctx context.Context, roomID int) ([]Participant, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, room_id, user_id, username, nickname, role, joined_at
		FROM watch_participants
		WHERE room_id = $1 AND left_at IS NULL
		ORDER BY joined_at ASC
	`, roomID)
	
	if err != nil {
		return nil, fmt.Errorf("query active participants: %w", err)
	}
	defer rows.Close()
	
	var participants []Participant
	for rows.Next() {
		var p Participant
		err := rows.Scan(&p.ID, &p.RoomID, &p.UserID, &p.Username, &p.Nickname,
			&p.Role, &p.JoinedAt)
		if err != nil {
			return nil, fmt.Errorf("scan participant: %w", err)
		}
		participants = append(participants, p)
	}
	
	return participants, nil
}

// RemoveParticipant 移除参与者(标记为已离开)
func (s *DBStore) RemoveParticipant(ctx context.Context, roomID int, userID int) error {
	now := time.Now()
	_, err := s.db.ExecContext(ctx, `
		UPDATE watch_participants 
		SET left_at = $1 
		WHERE room_id = $2 AND user_id = $3 AND left_at IS NULL
	`, now, roomID, userID)
	
	if err != nil {
		return fmt.Errorf("remove participant: %w", err)
	}
	
	return nil
}

// IsParticipant 检查用户是否是房间的活跃参与者
func (s *DBStore) IsParticipant(ctx context.Context, roomID int, userID int) (bool, error) {
	var exists bool
	err := s.db.QueryRowContext(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM watch_participants 
			WHERE room_id = $1 AND user_id = $2 AND left_at IS NULL
		)
	`, roomID, userID).Scan(&exists)
	
	if err != nil {
		return false, fmt.Errorf("check participant: %w", err)
	}
	
	return exists, nil
}

// UpdateParticipantRole 更新参与者角色
func (s *DBStore) UpdateParticipantRole(ctx context.Context, roomID int, userID int, role string) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE watch_participants 
		SET role = $1 
		WHERE room_id = $2 AND user_id = $3 AND left_at IS NULL
	`, role, roomID, userID)
	
	if err != nil {
		return fmt.Errorf("update participant role: %w", err)
	}
	
	return nil
}
