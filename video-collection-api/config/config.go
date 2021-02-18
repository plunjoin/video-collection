package config

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

// DatabaseConfig 数据库连接配置
type DatabaseConfig struct {
	Driver string `yaml:"driver" json:"driver"` // "postgres" 或 "sqlite"
	DSN    string `yaml:"dsn" json:"dsn"`       // 连接串
	// SQLite 数据文件路径，PostgreSQL 不可用时降级使用
	SQLitePath string `yaml:"sqlite_path" json:"sqlite_path"`
}

// AppConfig 根配置
type AppConfig struct {
	Database DatabaseConfig `yaml:"database" json:"database"`
	Sources  []SourceConfig `yaml:"sources" json:"sources"`
}

// SourceConfig 针对单个视频采集源的完整配置 (支持 MacCMS JSON、MacCMS XML、网页 RSS 订阅、自定义通用 JSON 等多种形态)
type SourceConfig struct {
	ID               string            `yaml:"id" json:"id"`                               // 采集源唯一ID
	Name             string            `yaml:"name" json:"name"`                           // 采集源名称，如 "示例数据源"
	API              string            `yaml:"api" json:"api"`                             // 采集端点 URL
	Type             string            `yaml:"type" json:"type"`                           // 协议类型: "json"(MacCMS JSON), "xml"(MacCMS XML), "rss"(网页RSS订阅), "custom_json"(自定义通用JSON)
	Enabled          bool              `yaml:"enabled" json:"enabled"`                     // 是否启用该采集源
	Active           bool              `yaml:"active,omitempty" json:"active"`             // 兼容前端 active 字段
	CollectHours     int               `yaml:"collect_hours" json:"collect_hours"`         // 采集最近几小时更新的数据 (h参数, 0表示全量, 默认24)
	PageLimit        int               `yaml:"page_limit" json:"page_limit"`               // 单次采集的最大页数 (0表示采集到底)
	TimeoutSec       int               `yaml:"timeout_sec" json:"timeout_sec"`             // HTTP超时时间(秒)
	RetryCount       int               `yaml:"retry_count" json:"retry_count"`             // 请求失败重试次数
	IntervalMs       int               `yaml:"interval_ms" json:"interval_ms"`             // 翻页间隔毫秒数(防封防频控)
	Concurrency      int               `yaml:"concurrency" json:"concurrency"`             // 并发采集协程数
	Headers          map[string]string `yaml:"headers" json:"headers"`                     // 自定义 HTTP 请求头 (如 User-Agent, Referer, Authorization, Cookie)
	CustomParams     map[string]string `yaml:"custom_params" json:"custom_params"`         // 自定义请求附加 Query 参数 (如 token=xxx)
	CustomMapping    CustomMapping     `yaml:"custom_mapping" json:"custom_mapping"`       // 自定义通用 JSON 字段映射 (用于非MacCMS规范接口)
	CategoryMappings []CategoryMapping `yaml:"category_mappings" json:"category_mappings"` // 分类绑定规则列表
	Filter           FilterRule        `yaml:"filter" json:"filter"`                       // 清洗与过滤规则
}

// CustomMapping 自定义 JSON API 提取字段映射
type CustomMapping struct {
	ListPath     string `yaml:"list_path" json:"list_path"`         // 列表对象路径 (如 "data", "items", "results")
	IDPath       string `yaml:"id_path" json:"id_path"`             // 唯一ID字段名
	NamePath     string `yaml:"name_path" json:"name_path"`         // 片名字段名 (如 "title", "name")
	TypePath     string `yaml:"type_path" json:"type_path"`         // 分类名字段名 (如 "category", "type")
	PicPath      string `yaml:"pic_path" json:"pic_path"`           // 封面图字段名 (如 "cover", "pic")
	PlayURLPath  string `yaml:"play_url_path" json:"play_url_path"` // 播放链接字段名 (如 "play_url", "m3u8")
	RemarksPath  string `yaml:"remarks_path" json:"remarks_path"`   // 连载更新状态字段名 (如 "remarks", "note")
	ActorPath    string `yaml:"actor_path" json:"actor_path"`       // 主演字段名
	DirectorPath string `yaml:"director_path" json:"director_path"` // 导演字段名
	AreaPath     string `yaml:"area_path" json:"area_path"`         // 地区字段名
	YearPath     string `yaml:"year_path" json:"year_path"`         // 年份字段名
	ContentPath  string `yaml:"content_path" json:"content_path"`   // 剧情简介字段名
}

// CategoryMapping 分类绑定映射 (将采集源分类映射为本地系统的分类)
type CategoryMapping struct {
	SourceTypeID   int    `yaml:"source_type_id" json:"source_type_id"`     // 采集源分类ID
	SourceTypeName string `yaml:"source_type_name" json:"source_type_name"` // 采集源分类名称
	TargetTypeID   int    `yaml:"target_type_id" json:"target_type_id"`     // 本地目标分类ID
	TargetTypeName string `yaml:"target_type_name" json:"target_type_name"` // 本地目标分类名称
}

// FilterRule 采集过滤与数据清洗规则
type FilterRule struct {
	IgnoreNameKeywords     []string          `yaml:"ignore_name_keywords" json:"ignore_name_keywords"`         // 片名包含此关键字时直接忽略(如: 预告, 抢先版)
	IgnoreTypeIDs          []int             `yaml:"ignore_type_ids" json:"ignore_type_ids"`                   // 忽略的采集源分类ID列表
	AllowedPlayers         []string          `yaml:"allowed_players" json:"allowed_players"`                   // 仅允许的播放器标识(如: m3u8), 为空则保留全部
	PlayerMappings         map[string]string `yaml:"player_mappings" json:"player_mappings"`                   // 播放器标识映射(如: kkm3u8 -> m3u8)
	RequirePlayURLs        bool              `yaml:"require_play_urls" json:"require_play_urls"`               // 是否过滤掉没有播放地址的视频
	NameCleanPrefixes      []string          `yaml:"name_clean_prefixes" json:"name_clean_prefixes"`           // 清除片名前缀(如: 【高清】, [未删减])
	ContentReplacePatterns []ReplaceRule     `yaml:"content_replace_patterns" json:"content_replace_patterns"` // 内容及简介中的广告/水印替换规则
	DefaultPlayer          string            `yaml:"default_player" json:"default_player"`                     // 缺省播放器标识 (默认 m3u8)
	DefaultTypeName        string            `yaml:"default_type_name" json:"default_type_name"`               // 缺省分类名称

	// 冗余镜像存储，用于老版本数据库平滑持久化扩展属性
	Headers       map[string]string `yaml:"headers,omitempty" json:"headers,omitempty"`
	CustomParams  map[string]string `yaml:"custom_params,omitempty" json:"custom_params,omitempty"`
	CustomMapping *CustomMapping    `yaml:"custom_mapping,omitempty" json:"custom_mapping,omitempty"`
}

// ReplaceRule 文本替换规则 (用于过滤内容中的引流广告)
type ReplaceRule struct {
	Pattern     string `yaml:"pattern" json:"pattern"`         // 匹配表达式
	IsRegex     bool   `yaml:"is_regex" json:"is_regex"`       // 是否为正则表达式
	Replacement string `yaml:"replacement" json:"replacement"` // 替换成的内容
}

// LoadConfig 从指定 YAML 文件加载配置
func LoadConfig(filePath string) (*AppConfig, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("read config file failed: %w", err)
	}

	var cfg AppConfig
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("unmarshal yaml failed: %w", err)
	}

	// 填补默认值
	if cfg.Database.Driver == "" {
		cfg.Database.Driver = "postgres"
	}
	if cfg.Database.DSN == "" {
		cfg.Database.DSN = "postgres://postgres:postgres@localhost:5432/videodb?sslmode=disable"
	}

	for i := range cfg.Sources {
		s := &cfg.Sources[i]
		if s.Type == "" {
			s.Type = "json"
		}
		if s.CollectHours <= 0 {
			s.CollectHours = 24 // 默认24小时增量采集
		}
		if s.TimeoutSec <= 0 {
			s.TimeoutSec = 15
		}
		if s.RetryCount <= 0 {
			s.RetryCount = 3
		}
		if s.Concurrency <= 0 {
			s.Concurrency = 3
		}
	}

	return &cfg, nil
}
