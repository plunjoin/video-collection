package store

import (
	"context"
	"strings"
	"time"

	"video-collection-api/config"
	"video-collection-api/pkg/maccms"
)

// User 系统用户模型
type User struct {
	ID           int       `json:"id"`
	Username     string    `json:"username"`
	PasswordHash string    `json:"-"`
	Nickname     string    `json:"nickname"`
	Avatar       string    `json:"avatar"`
	Role         string    `json:"role"`   // "admin" 或 "user"
	Status       int       `json:"status"` // 1 正常, 0 禁用
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// Category 本地系统维护的标准分类
type Category struct {
	ID   int    `json:"id"`
	PID  int    `json:"pid"`
	Name string `json:"name"`
	Sort int    `json:"sort"`
}

// VideoRecord 存储在数据库中的标准视频记录（深度支持多节点聚合与双向接口规范兼容）
type VideoRecord struct {
	ID         int                `json:"id"`
	Name       string             `json:"name"`
	SubName    string             `json:"sub_name"`
	TypeID     int                `json:"type_id"`
	TypeName   string             `json:"type_name"`
	Picture    string             `json:"picture"`
	Pic        string             `json:"pic,omitempty"`         // 兼容 Admin 管理后台 pic 字段
	Actor      string             `json:"actor"`
	Director   string             `json:"director"`
	Area       string             `json:"area"`
	Language   string             `json:"language"`
	Year       string             `json:"year"`
	Remarks    string             `json:"remarks"`
	Content    string             `json:"content"`
	SourceID   string             `json:"source_id"`
	SourceIDs  []string           `json:"source_ids,omitempty"`  // 所属的所有采集节点ID集合
	Hits       int                `json:"hits"`
	CreatedAt  time.Time          `json:"created_at"`
	UpdatedAt  time.Time          `json:"updated_at"`
	PlayGroups []maccms.PlayGroup `json:"play_groups"`
	PlayRoutes []maccms.PlayGroup `json:"play_routes,omitempty"` // 兼容 Admin 管理后台 play_routes 字段
}

// FillCompatFields 自动补齐各端兼容字段
func (v *VideoRecord) FillCompatFields() {
	if v.Pic == "" {
		v.Pic = v.Picture
	}
	if v.Picture == "" {
		v.Picture = v.Pic
	}

	// 解析多节点来源ID
	if v.SourceID != "" {
		parts := strings.Split(v.SourceID, ",")
		uniqueMap := make(map[string]bool)
		var sids []string
		for _, p := range parts {
			trimmed := strings.TrimSpace(p)
			if trimmed != "" && !uniqueMap[trimmed] {
				uniqueMap[trimmed] = true
				sids = append(sids, trimmed)
			}
		}
		v.SourceIDs = sids
	}

	// 填充 play_routes 并格式化线路名称
	routes := make([]maccms.PlayGroup, len(v.PlayGroups))
	for i, pg := range v.PlayGroups {
		item := pg
		if item.SourceName == "" {
			if item.Server != "" && item.Server != "no" {
				item.SourceName = item.Server
			} else if len(v.SourceIDs) > i && v.SourceIDs[i] != "" {
				if v.SourceIDs[i] == "example_json" {
					item.SourceName = "示例数据源"
				} else {
					item.SourceName = v.SourceIDs[i]
				}
			} else if v.SourceID == "example_json" || strings.HasPrefix(v.SourceID, "example_json") {
				item.SourceName = "示例数据源"
			}
		}
		if item.From == "" {
			if item.SourceName != "" {
				item.From = item.SourceName + " (" + item.PlayerCode + ")"
			} else {
				item.From = item.PlayerCode
			}
		}
		if item.Server == "" || item.Server == "no" {
			if item.SourceName != "" {
				item.Server = item.SourceName
			}
		}
		v.PlayGroups[i] = item
		routes[i] = item
	}

	// 针对相同展示来源及编码做读取端去重兜底，保留剧集最全的线路
	dedupRoutes := make(map[string]maccms.PlayGroup)
	var routeKeys []string
	for _, r := range routes {
		key := strings.ToLower(strings.TrimSpace(r.SourceName)) + ":" + strings.ToLower(strings.TrimSpace(r.PlayerCode))
		if key == ":" {
			key = strings.ToLower(strings.TrimSpace(r.From))
		}
		if existing, exists := dedupRoutes[key]; exists {
			if len(r.Episodes) >= len(existing.Episodes) {
				dedupRoutes[key] = r
			}
		} else {
			dedupRoutes[key] = r
			routeKeys = append(routeKeys, key)
		}
	}
	cleanRoutes := make([]maccms.PlayGroup, 0, len(routeKeys))
	for _, k := range routeKeys {
		cleanRoutes = append(cleanRoutes, dedupRoutes[k])
	}
	v.PlayGroups = cleanRoutes
	v.PlayRoutes = cleanRoutes
}

// VideoQuery 视频查询条件 (适配 MacCMS v10 输出接口与后台检索)
type VideoQuery struct {
	Page        int
	PageSize    int
	TypeID      int
	Hours       int    // 最近几小时内更新的数据
	Keyword     string // 关键字搜索
	NameKeyword string // 视频名称/同系列匹配
	ExcludeIDs  []int  // 排除的视频ID列表
	Area        string // 地区筛选
	Year        string // 年份筛选
	IDs         []int  // 指定 ID 列表
	OrderBy     string // "updated_at", "hits", "id", "score"
	OrderDesc   bool
}

// Feedback 用户留言求片与播放故障报错
type Feedback struct {
	ID        int       `json:"id"`
	Type      string    `json:"type"`      // "request" (求片), "report" (报错), "suggest" (建议)
	Title     string    `json:"title"`     // 影片名或反馈主题
	Content   string    `json:"content"`   // 详细内容/失效集数
	Contact   string    `json:"contact"`   // 联系方式 (邮箱/QQ/微信)
	Status    string    `json:"status"`    // "pending" (待处理), "processing" (处理中), "resolved" (已处理/已收录), "rejected" (已驳回)
	Reply     string    `json:"reply"`     // 管理员答复内容
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// UserHistoryItem 用户播放历史与进度云端记录
type UserHistoryItem struct {
	ID           int       `json:"id"`
	UserID       int       `json:"user_id"`
	VideoID      int       `json:"video_id"`
	VideoName    string    `json:"video_name"`
	Picture      string    `json:"picture"`
	EpisodeName  string    `json:"episode_name"`
	RouteIndex   int       `json:"route_index"`
	EpisodeIndex int       `json:"episode_index"`
	CurrentTime  int       `json:"current_time"`
	Duration     int       `json:"duration"`
	Progress     float64   `json:"progress"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// UserFavoriteItem 用户追剧收藏云端记录
type UserFavoriteItem struct {
	ID        int       `json:"id"`
	UserID    int       `json:"user_id"`
	VideoID   int       `json:"video_id"`
	VideoName string    `json:"video_name"`
	Picture   string    `json:"picture"`
	Remarks   string    `json:"remarks"`
	CreatedAt time.Time `json:"created_at"`
}

// StatsInfo 仪表盘统计数据
type StatsInfo struct {
	TotalSources   int `json:"total_sources"`
	ActiveSources  int `json:"active_sources"`
	TotalVideos    int `json:"total_videos"`
	TodayUpdated   int `json:"today_updated"`
	TotalPlayCount int `json:"total_play_groups"`
	TotalUsers     int `json:"total_users"`
	TotalFeedbacks int `json:"total_feedbacks"`
}

// Store 统一存储接口
type Store interface {
	// 用户管理
	GetUserByUsername(ctx context.Context, username string) (*User, error)
	GetUserByID(ctx context.Context, id int) (*User, error)
	ListUsers(ctx context.Context) ([]User, error)
	CreateUser(ctx context.Context, user *User) error
	UpdateUser(ctx context.Context, user *User) error
	DeleteUser(ctx context.Context, id int) error
	InitDefaultAdmin(ctx context.Context) error

	// 用户播放历史与追剧收藏 (云端多设备同步)
	SaveUserHistory(ctx context.Context, item *UserHistoryItem) error
	GetUserHistory(ctx context.Context, userID int, limit int) ([]UserHistoryItem, error)
	DeleteUserHistory(ctx context.Context, userID int, videoID int) error
	ClearUserHistory(ctx context.Context, userID int) error
	SaveUserFavorite(ctx context.Context, item *UserFavoriteItem) error
	GetUserFavorites(ctx context.Context, userID int, limit int) ([]UserFavoriteItem, error)
	DeleteUserFavorite(ctx context.Context, userID int, videoID int) error

	// 系统全局设置 (如当前激活主题、站点公告、网站标题等)
	GetSetting(ctx context.Context, key, defaultVal string) (string, error)
	SetSetting(ctx context.Context, key, val string) error
	GetAllSettings(ctx context.Context) (map[string]string, error)
	SetSettings(ctx context.Context, settings map[string]string) error

	// 采集源配置管理
	GetSources(ctx context.Context) ([]config.SourceConfig, error)
	GetSourceByID(ctx context.Context, id string) (*config.SourceConfig, error)
	SaveSource(ctx context.Context, source config.SourceConfig) error
	DeleteSource(ctx context.Context, id string) error

	// 分类管理与树形展开
	GetCategories(ctx context.Context) ([]Category, error)
	InitDefaultCategories(ctx context.Context) error
	GetCategoryFamilyIDs(ctx context.Context, catID int) ([]int, error) // 获取分类及其所有子孙分类ID，用于级联查询

	// 视频与播放源存储
	UpsertVideo(ctx context.Context, sourceID string, vod *maccms.CleanedVod) (int, error)
	SaveVideoManual(ctx context.Context, video *VideoRecord) (int, error)
	QueryVideos(ctx context.Context, query VideoQuery) ([]VideoRecord, int, error)
	GetVideoByID(ctx context.Context, id int) (*VideoRecord, error)
	DeleteVideo(ctx context.Context, id int) error
	BatchDeleteVideos(ctx context.Context, ids []int) error
	IncrementVideoHits(ctx context.Context, id int) error
	GetHotVideos(ctx context.Context, typeID int, limit int) ([]VideoRecord, error)

	// 用户留言求片与报错反馈
	CreateFeedback(ctx context.Context, fb *Feedback) error
	ListFeedbacks(ctx context.Context, page, pageSize int, status, fbType string) ([]Feedback, int, error)
	UpdateFeedback(ctx context.Context, id int, status, reply string) error
	DeleteFeedback(ctx context.Context, id int) error

	// 统计数据
	GetStats(ctx context.Context) (*StatsInfo, error)
}

func parseVodTime(raw string) time.Time {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return time.Now()
	}
	formats := []string{
		"2006-01-02 15:04:05",
		"2006-01-02 15:04",
		"2006-01-02",
		"2006/01/02 15:04:05",
		"2006/01/02",
	}
	for _, f := range formats {
		if t, err := time.ParseInLocation(f, raw, time.Local); err == nil {
			return t
		}
	}
	return time.Now()
}
