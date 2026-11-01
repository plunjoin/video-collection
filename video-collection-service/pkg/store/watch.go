package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

var (
	// ErrWatchLimited 一起看聊天发送太频繁。
	ErrWatchLimited = errors.New("发送太频繁，请稍后再试")
	// ErrWatchRoomNotFound 房间不存在或已解散。
	ErrWatchRoomNotFound = errors.New("房间不存在或已解散")
	// ErrWatchNotMember 尚未加入该房间。
	ErrWatchNotMember = errors.New("尚未加入该房间")
)

// WatchRoom 一起看房间。播放状态采用「锚点」模型：
// PositionMs 是 AnchorMs（unix 毫秒）那一刻的进度，Playing 时读取方按墙上时钟推算目标进度。
// Rate 记录房主倍速，成员同步应用，避免倍速观看时进度持续漂移。
// ControlMode 为 "host"（仅房主可控制，默认）或 "all"（所有成员可控制）。
type WatchRoom struct {
	ID           int       `json:"id"`
	Code         string    `json:"code"`
	VideoID      int       `json:"video_id"`
	GroupIndex   int       `json:"group_index"`
	EpisodeIndex int       `json:"episode_index"`
	Title        string    `json:"title"`
	HostID       int       `json:"host_id"`
	Version      int64     `json:"version"`
	Playing      bool      `json:"playing"`
	PositionMs   int64     `json:"position_ms"`
	AnchorMs     int64     `json:"anchor_ms"`
	Rate         float64   `json:"rate"`
	ControlMode  string    `json:"control_mode"`
	UpdatedBy    int       `json:"updated_by"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// TargetPositionMs 按当前时刻推算房主侧应处的进度（毫秒）。
// 外推按房主倍速换算（Rate），否则倍速播放时成员会系统性领先/落后房主。
// 外推有 5 秒硬上限：房主心跳会持续重锚（锚点新鲜度=心跳间隔），
// 上限保证即使房主端卡顿/失报/旧版本客户端，成员的目标也绝不会
// 沿理想时间线无限冲前——最多领先房主最近上报位置约 5 秒。
func (r *WatchRoom) TargetPositionMs(now time.Time) int64 {
	target := r.PositionMs
	if r.Playing {
		extra := now.UnixMilli() - r.AnchorMs
		if extra > 0 {
			rate := r.Rate
			if rate <= 0 {
				rate = 1
			}
			extra = int64(float64(extra) * rate)
			if extra > watchExtrapolationCapMs {
				extra = watchExtrapolationCapMs
			}
			target += extra
		}
	}
	if target < 0 {
		target = 0
	}
	return target
}

// watchExtrapolationCapMs 播放进度外推上限（毫秒）。
const watchExtrapolationCapMs = 5000

// WatchMember 房间成员。LastSeenAt 由心跳刷新，用于在线判定与房主失联转让。
type WatchMember struct {
	UserID     int       `json:"user_id"`
	Nickname   string    `json:"nickname"`
	Avatar     string    `json:"avatar"`
	PositionMs int64     `json:"position_ms"`
	IsHost     bool      `json:"is_host"`
	JoinedAt   time.Time `json:"joined_at"`
	LastSeenAt time.Time `json:"last_seen_at"`
}

// WatchMessage 房间聊天消息。
type WatchMessage struct {
	ID         int       `json:"id"`
	RoomID     int       `json:"room_id"`
	UserID     int       `json:"user_id"`
	AuthorName string    `json:"author_name"`
	Content    string    `json:"content"`
	CreatedAt  time.Time `json:"created_at"`
}

// WatchStore 一起看房间存储。
type WatchStore interface {
	CreateWatchRoom(ctx context.Context, room *WatchRoom) error
	GetWatchRoomByCode(ctx context.Context, code string) (*WatchRoom, error)
	DeleteWatchRoom(ctx context.Context, id int) error
	// RecycleHostRooms 回收该用户名下已无其他活跃成员的房间，返回回收数量。
	RecycleHostRooms(ctx context.Context, hostID int, activeWithin time.Duration) (int64, error)
	JoinWatchRoom(ctx context.Context, roomID, userID int, nickname, avatar string) error
	LeaveWatchRoom(ctx context.Context, roomID, userID int) error
	// TouchWatchMember 心跳刷新成员在线状态与本地进度。
	TouchWatchMember(ctx context.Context, roomID, userID, positionMs int) error
	ListWatchMembers(ctx context.Context, roomID int) ([]WatchMember, error)
	// UpdateWatchState 房主推送播放状态；版本号自增并刷新锚点。
	UpdateWatchState(ctx context.Context, room *WatchRoom) error
	// UpdateWatchHostProgress 房主心跳上报真实进度：仅刷新锚点与进度，
	// 不升版本（成员按漂移跟随，不触发全量对齐）。
	UpdateWatchHostProgress(ctx context.Context, roomID int, positionMs, anchorMs int64) error
	// EnsureWatchHost 房主失联超过 staleAfter 时把房主转让给最近活跃成员，返回当前（或新）房主。
	EnsureWatchHost(ctx context.Context, roomID int, staleAfter time.Duration) (int, error)
	// SetWatchHost 手动转让房主。
	SetWatchHost(ctx context.Context, roomID, hostID int) error
	// SetWatchControlMode 切换播放控制权限（host / all）。
	SetWatchControlMode(ctx context.Context, roomID int, mode string) error
	// ListWatchMessages 读取 sinceID 之后的房间消息（升序）。
	ListWatchMessages(ctx context.Context, roomID, sinceID, limit int) ([]WatchMessage, error)
	AddWatchMessage(ctx context.Context, msg *WatchMessage) error
	// RecentWatchMessageCount 统计成员最近窗口内在该房间发送的消息数，用于限频。
	RecentWatchMessageCount(ctx context.Context, roomID, userID int, within time.Duration) (int, error)
	// CleanStaleWatchRooms 清理全部成员失联超过 idleFor 的房间，返回清理数量。
	CleanStaleWatchRooms(ctx context.Context, idleFor time.Duration) (int64, error)
}

func migrateWatch(tx *sql.Tx, id, timestamp string) error {
	schema := fmt.Sprintf(`CREATE TABLE IF NOT EXISTS watch_rooms (
	 id %s, code TEXT NOT NULL UNIQUE, video_id INTEGER NOT NULL,
	 group_index INTEGER NOT NULL DEFAULT 0, episode_index INTEGER NOT NULL DEFAULT 0,
	 title TEXT NOT NULL DEFAULT '', host_id INTEGER NOT NULL,
	 version INTEGER NOT NULL DEFAULT 1, playing INTEGER NOT NULL DEFAULT 0,
	 position_ms INTEGER NOT NULL DEFAULT 0, anchor_ms INTEGER NOT NULL DEFAULT 0,
	 rate REAL NOT NULL DEFAULT 1, control_mode TEXT NOT NULL DEFAULT 'host',
	 updated_by INTEGER NOT NULL DEFAULT 0,
	 created_at %s NOT NULL, updated_at %s NOT NULL
	);
	CREATE INDEX IF NOT EXISTS idx_watch_rooms_host ON watch_rooms(host_id);
	CREATE TABLE IF NOT EXISTS watch_members (
	 room_id INTEGER NOT NULL REFERENCES watch_rooms(id) ON DELETE CASCADE,
	 user_id INTEGER NOT NULL, nickname TEXT NOT NULL DEFAULT '', avatar TEXT NOT NULL DEFAULT '',
	 position_ms INTEGER NOT NULL DEFAULT 0,
	 joined_at %s NOT NULL, last_seen_at %s NOT NULL,
	 PRIMARY KEY(room_id,user_id)
	);
	CREATE INDEX IF NOT EXISTS idx_watch_members_seen ON watch_members(user_id,last_seen_at);
	CREATE TABLE IF NOT EXISTS watch_messages (
	 id %s, room_id INTEGER NOT NULL REFERENCES watch_rooms(id) ON DELETE CASCADE,
	 user_id INTEGER NOT NULL, author_name TEXT NOT NULL DEFAULT '', content TEXT NOT NULL,
	 created_at %s NOT NULL
	);
	CREATE INDEX IF NOT EXISTS idx_watch_messages_room ON watch_messages(room_id,id);
	CREATE INDEX IF NOT EXISTS idx_watch_messages_rate ON watch_messages(room_id,user_id,created_at);`, id, timestamp, timestamp, timestamp, timestamp, id, timestamp)
	return execScript(tx, schema)
}

const watchRoomColumns = `id, code, video_id, group_index, episode_index, title, host_id, version, playing, position_ms, anchor_ms, rate, control_mode, updated_by, created_at, updated_at`

func scanWatchRoom(row contentScanner) (*WatchRoom, error) {
	var room WatchRoom
	var playing int
	if err := row.Scan(&room.ID, &room.Code, &room.VideoID, &room.GroupIndex, &room.EpisodeIndex, &room.Title, &room.HostID, &room.Version, &playing, &room.PositionMs, &room.AnchorMs, &room.Rate, &room.ControlMode, &room.UpdatedBy, &room.CreatedAt, &room.UpdatedAt); err != nil {
		return nil, err
	}
	room.Playing = playing != 0
	if room.Rate <= 0 {
		room.Rate = 1
	}
	if room.ControlMode != "all" {
		room.ControlMode = "host"
	}
	return &room, nil
}

func (s *SQLContentStore) CreateWatchRoom(ctx context.Context, room *WatchRoom) error {
	now := time.Now().UTC()
	room.CreatedAt, room.UpdatedAt = now, now
	if room.AnchorMs <= 0 {
		room.AnchorMs = now.UnixMilli()
	}
	if room.Rate <= 0 {
		room.Rate = 1
	}
	if room.ControlMode != "all" {
		room.ControlMode = "host"
	}
	return s.db.QueryRowContext(ctx, `INSERT INTO watch_rooms(code,video_id,group_index,episode_index,title,host_id,version,playing,position_ms,anchor_ms,rate,control_mode,updated_by,created_at,updated_at)
	VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15) RETURNING id, created_at, updated_at`,
		room.Code, room.VideoID, room.GroupIndex, room.EpisodeIndex, room.Title, room.HostID, room.Version, boolToInt(room.Playing), room.PositionMs, room.AnchorMs, room.Rate, room.ControlMode, room.UpdatedBy, room.CreatedAt, room.UpdatedAt).
		Scan(&room.ID, &room.CreatedAt, &room.UpdatedAt)
}

func (s *SQLContentStore) GetWatchRoomByCode(ctx context.Context, code string) (*WatchRoom, error) {
	row := s.db.QueryRowContext(ctx, `SELECT `+watchRoomColumns+` FROM watch_rooms WHERE code=$1`, code)
	room, err := scanWatchRoom(row)
	if err == sql.ErrNoRows {
		return nil, ErrWatchRoomNotFound
	}
	return room, err
}

func (s *SQLContentStore) DeleteWatchRoom(ctx context.Context, id int) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM watch_rooms WHERE id=$1`, id)
	return err
}

func (s *SQLContentStore) RecycleHostRooms(ctx context.Context, hostID int, activeWithin time.Duration) (int64, error) {
	res, err := s.db.ExecContext(ctx, `DELETE FROM watch_rooms WHERE host_id=$1 AND id IN (
	 SELECT r.id FROM watch_rooms r WHERE r.host_id=$1 AND NOT EXISTS (
	   SELECT 1 FROM watch_members m WHERE m.room_id=r.id AND m.user_id<>$1 AND m.last_seen_at>=$2
	 ))`, hostID, time.Now().UTC().Add(-activeWithin))
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

func (s *SQLContentStore) JoinWatchRoom(ctx context.Context, roomID, userID int, nickname, avatar string) error {
	now := time.Now().UTC()
	_, err := s.db.ExecContext(ctx, `INSERT INTO watch_members(room_id,user_id,nickname,avatar,position_ms,joined_at,last_seen_at)
	VALUES($1,$2,$3,$4,0,$5,$5)
	ON CONFLICT(room_id,user_id) DO UPDATE SET nickname=excluded.nickname, avatar=excluded.avatar, last_seen_at=excluded.last_seen_at`,
		roomID, userID, nickname, avatar, now)
	return err
}

func (s *SQLContentStore) LeaveWatchRoom(ctx context.Context, roomID, userID int) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM watch_members WHERE room_id=$1 AND user_id=$2`, roomID, userID)
	return err
}

func (s *SQLContentStore) TouchWatchMember(ctx context.Context, roomID, userID, positionMs int) error {
	res, err := s.db.ExecContext(ctx, `UPDATE watch_members SET last_seen_at=$3, position_ms=$4 WHERE room_id=$1 AND user_id=$2`,
		roomID, userID, time.Now().UTC(), positionMs)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrWatchNotMember
	}
	return nil
}

func (s *SQLContentStore) ListWatchMembers(ctx context.Context, roomID int) ([]WatchMember, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT user_id, nickname, avatar, position_ms, joined_at, last_seen_at
	FROM watch_members WHERE room_id=$1 ORDER BY last_seen_at ASC, user_id ASC`, roomID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	list := make([]WatchMember, 0)
	for rows.Next() {
		var m WatchMember
		if err = rows.Scan(&m.UserID, &m.Nickname, &m.Avatar, &m.PositionMs, &m.JoinedAt, &m.LastSeenAt); err != nil {
			return nil, err
		}
		list = append(list, m)
	}
	return list, rows.Err()
}

func (s *SQLContentStore) UpdateWatchState(ctx context.Context, room *WatchRoom) error {
	now := time.Now().UTC()
	room.UpdatedAt = now
	// 每次推送即重新锚定：PositionMs 以本次推送时刻为基准，
	// 否则锚点停留在上次状态，成员推算出的目标进度会随房间时长持续漂移。
	room.AnchorMs = now.UnixMilli()
	res, err := s.db.ExecContext(ctx, `UPDATE watch_rooms SET group_index=$2, episode_index=$3, title=$4, host_id=$5,
	version=version+1, playing=$6, position_ms=$7, anchor_ms=$8, rate=$9, updated_by=$10, updated_at=$11 WHERE id=$1`,
		room.ID, room.GroupIndex, room.EpisodeIndex, room.Title, room.HostID, boolToInt(room.Playing), room.PositionMs, room.AnchorMs, room.Rate, room.UpdatedBy, room.UpdatedAt)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrWatchRoomNotFound
	}
	room.Version++
	return nil
}

func (s *SQLContentStore) UpdateWatchHostProgress(ctx context.Context, roomID int, positionMs, anchorMs int64) error {
	_, err := s.db.ExecContext(ctx, `UPDATE watch_rooms SET position_ms=$2, anchor_ms=$3, updated_at=$4 WHERE id=$1`,
		roomID, positionMs, anchorMs, time.Now().UTC())
	return err
}

func (s *SQLContentStore) EnsureWatchHost(ctx context.Context, roomID int, staleAfter time.Duration) (int, error) {
	var hostID int
	if err := s.db.QueryRowContext(ctx, `SELECT host_id FROM watch_rooms WHERE id=$1`, roomID).Scan(&hostID); err != nil {
		if err == sql.ErrNoRows {
			return 0, ErrWatchRoomNotFound
		}
		return 0, err
	}
	cutoff := time.Now().UTC().Add(-staleAfter)
	var seen int
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM watch_members WHERE room_id=$1 AND user_id=$2 AND last_seen_at>=$3`, roomID, hostID, cutoff).Scan(&seen); err != nil {
		return 0, err
	}
	if seen > 0 {
		return hostID, nil
	}
	// 房主失联：优先转让给窗口期内仍活跃的成员；窗口内无人则退回最近活跃的任意成员
	//（例如房主直接退出、其余成员短暂离线），避免房主落在已离开的用户身上。
	var next sql.NullInt64
	err := s.db.QueryRowContext(ctx, `SELECT user_id FROM watch_members WHERE room_id=$1 AND user_id<>$2
	ORDER BY (last_seen_at>=$3) DESC, last_seen_at DESC, user_id ASC LIMIT 1`,
		roomID, hostID, cutoff).Scan(&next)
	if err == sql.ErrNoRows {
		return hostID, nil
	}
	if err != nil {
		return 0, err
	}
	newHost := int(next.Int64)
	if _, err = s.db.ExecContext(ctx, `UPDATE watch_rooms SET host_id=$2, updated_at=$3 WHERE id=$1`, roomID, newHost, time.Now().UTC()); err != nil {
		return 0, err
	}
	return newHost, nil
}

func (s *SQLContentStore) SetWatchHost(ctx context.Context, roomID, hostID int) error {
	var member int
	err := s.db.QueryRowContext(ctx, `SELECT user_id FROM watch_members WHERE room_id=$1 AND user_id=$2`, roomID, hostID).Scan(&member)
	if err == sql.ErrNoRows {
		return ErrContentForbidden
	}
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `UPDATE watch_rooms SET host_id=$2, updated_at=$3 WHERE id=$1`, roomID, hostID, time.Now().UTC())
	return err
}

func (s *SQLContentStore) SetWatchControlMode(ctx context.Context, roomID int, mode string) error {
	if mode != "host" && mode != "all" {
		mode = "host"
	}
	_, err := s.db.ExecContext(ctx, `UPDATE watch_rooms SET control_mode=$2, updated_at=$3 WHERE id=$1`, roomID, mode, time.Now().UTC())
	return err
}

func (s *SQLContentStore) ListWatchMessages(ctx context.Context, roomID, sinceID, limit int) ([]WatchMessage, error) {
	if limit < 1 || limit > 100 {
		limit = 50
	}
	rows, err := s.db.QueryContext(ctx, `SELECT id, room_id, user_id, author_name, content, created_at
	FROM watch_messages WHERE room_id=$1 AND id>$2 ORDER BY id ASC LIMIT $3`, roomID, sinceID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	list := make([]WatchMessage, 0)
	for rows.Next() {
		var m WatchMessage
		if err = rows.Scan(&m.ID, &m.RoomID, &m.UserID, &m.AuthorName, &m.Content, &m.CreatedAt); err != nil {
			return nil, err
		}
		list = append(list, m)
	}
	return list, rows.Err()
}

func (s *SQLContentStore) AddWatchMessage(ctx context.Context, msg *WatchMessage) error {
	// 限频：同一成员在同一房间 10 秒内最多 5 条。
	recent, err := s.RecentWatchMessageCount(ctx, msg.RoomID, msg.UserID, 10*time.Second)
	if err != nil {
		return err
	}
	if recent >= 5 {
		return ErrWatchLimited
	}
	msg.CreatedAt = time.Now().UTC()
	if err = s.db.QueryRowContext(ctx, `INSERT INTO watch_messages(room_id,user_id,author_name,content,created_at)
	VALUES($1,$2,$3,$4,$5) RETURNING id, created_at`,
		msg.RoomID, msg.UserID, msg.AuthorName, msg.Content, msg.CreatedAt).Scan(&msg.ID, &msg.CreatedAt); err != nil {
		return err
	}
	// 每个房间只保留最近 200 条消息。
	_, err = s.db.ExecContext(ctx, `DELETE FROM watch_messages WHERE room_id=$1 AND id <= (
	 SELECT id FROM watch_messages WHERE room_id=$1 ORDER BY id DESC LIMIT 1 OFFSET 200)`, msg.RoomID)
	return err
}

func (s *SQLContentStore) RecentWatchMessageCount(ctx context.Context, roomID, userID int, within time.Duration) (int, error) {
	var count int
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM watch_messages WHERE room_id=$1 AND user_id=$2 AND created_at>=$3`,
		roomID, userID, time.Now().UTC().Add(-within)).Scan(&count)
	return count, err
}

func (s *SQLContentStore) CleanStaleWatchRooms(ctx context.Context, idleFor time.Duration) (int64, error) {
	res, err := s.db.ExecContext(ctx, `DELETE FROM watch_rooms WHERE updated_at < $1 AND NOT EXISTS (
	 SELECT 1 FROM watch_members m WHERE m.room_id=watch_rooms.id AND m.last_seen_at>=$1)`,
		time.Now().UTC().Add(-idleFor))
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}
