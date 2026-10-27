package watch

import (
	"time"
)

// Room 一起看房间模型
type Room struct {
	ID             int       `json:"id"`
	Code           string    `json:"code"`             // 6位短码,用于分享
	HostUserID     int       `json:"host_user_id"`     // 房主用户ID
	VideoID        int       `json:"video_id"`         // 视频ID
	RouteIndex     int       `json:"route_index"`      // 线路索引
	EpisodeIndex   int       `json:"episode_index"`    // 集数索引
	Status         string    `json:"status"`           // active, closed
	MaxParticipants int      `json:"max_participants"` // 最大参与人数(默认6)
	CreatedAt      time.Time `json:"created_at"`
	ExpiresAt      time.Time `json:"expires_at"`       // 过期时间(创建后约4小时)
}

// Participant 房间参与者
type Participant struct {
	ID       int       `json:"id"`
	RoomID   int       `json:"room_id"`
	UserID   int       `json:"user_id"`
	Username string    `json:"username"`
	Nickname string    `json:"nickname"`
	Role     string    `json:"role"`      // host, member
	JoinedAt time.Time `json:"joined_at"`
	LeftAt   *time.Time `json:"left_at,omitempty"`
}

// PlaybackState 服务器权威的播放状态
type PlaybackState struct {
	Playing      bool      `json:"playing"`        // 是否播放中
	PositionMs   int64     `json:"position_ms"`    // 播放位置(毫秒)
	Rate         float64   `json:"rate"`           // 播放速率(默认1.0)
	ServerTsMs   int64     `json:"server_ts_ms"`   // 服务器时间戳(毫秒)
	Revision     int64     `json:"revision"`       // 状态版本号
	VideoID      int       `json:"video_id"`       // 视频ID
	RouteIndex   int       `json:"route_index"`    // 线路索引
	EpisodeIndex int       `json:"episode_index"`  // 集数索引
	HostUserID   int       `json:"host_user_id"`   // 当前房主ID
	UpdatedAt    time.Time `json:"updated_at"`     // 更新时间
}

// RoomInfo 房间详细信息(包含参与者列表和播放状态)
type RoomInfo struct {
	Room         Room            `json:"room"`
	Participants []Participant   `json:"participants"`
	State        PlaybackState   `json:"state"`
}

// CreateRoomRequest 创建房间请求
type CreateRoomRequest struct {
	VideoID      int `json:"video_id"`
	RouteIndex   int `json:"route_index"`
	EpisodeIndex int `json:"episode_index"`
}

// CreateRoomResponse 创建房间响应
type CreateRoomResponse struct {
	Room Room   `json:"room"`
	Code string `json:"code"`
}
