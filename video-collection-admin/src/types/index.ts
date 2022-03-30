// 通用 API 返回结构
export interface ApiResponse<T = any> {
  code: number
  msg?: string
  error?: string
  data?: T
  total?: number
  page?: number
  page_size?: number
  token?: string
  user?: UserInfo
  classes?: any[]
  classes_total?: number
  samples?: string[]
  sample_count?: number
}

// 用户信息
export interface UserInfo {
  id: number
  username: string
  nickname: string
  role: 'admin' | 'user'
  avatar?: string
  status?: number
  created_at?: string
  updated_at?: string
}

// 统计数据
export interface AdminStats {
  total_sources: number
  active_sources: number
  total_videos: number
  today_updated: number
  total_play_groups: number
  total_users: number
  total_feedbacks: number
}

// 采集源配置
export interface SourceConfig {
  id: string
  name: string
  api: string
  type: 'json' | 'xml' | 'rss' | 'custom'
  active: boolean
  collect_hours: number
  headers?: Record<string, string>
  custom_params?: Record<string, string>
  custom_mapping?: {
    list_path?: string
    id_field?: string
    name_field?: string
    type_field?: string
    pic_field?: string
    play_url_field?: string
  }
  category_filter?: string[]
}

// 视频分类
export interface Category {
  id?: number
  pid?: number
  name?: string
  sort?: number
  type_id?: number
  type_name?: string
}

// 播放线路中的单集
export interface PlayEpisode {
  name: string
  url: string
}

// 播放线路（深度支持多采集节点标识与兼容各端字段）
export interface PlayRoute {
  source_id?: string
  source_name?: string
  player_code?: string
  from: string
  server: string
  note: string
  episodes: PlayEpisode[]
}

// 视频记录
export interface VideoRecord {
  id: number
  source_id?: string
  source_ids?: string[]
  name: string
  sub_name?: string
  en_name?: string
  type_id: number
  type_name: string
  class_tag?: string
  pic?: string
  picture?: string
  actor?: string
  director?: string
  writer?: string
  blurb?: string
  remarks?: string
  pub_date?: string
  area?: string
  lang?: string
  language?: string
  year?: string
  state?: string
  note?: string
  score?: string
  hits?: number
  content?: string
  play_routes?: PlayRoute[]
  play_groups?: PlayRoute[]
  created_at?: string
  updated_at?: string
}

// 用户反馈
export interface FeedbackItem {
  id: number
  user_id?: number
  type: 'request' | 'error' | 'other'
  title: string
  content: string
  contact?: string
  status: 'pending' | 'processing' | 'resolved' | 'closed'
  reply?: string
  created_at: string
  updated_at: string
}

// 主题信息
export interface ThemeInfo {
  id: string
  name: string
  version: string
  author: string
  description?: string
  preview?: string
  is_active: boolean
  path?: string
}

// 播放器信息
export interface PlayerInfo {
  id: string
  name: string
  version: string
  author: string
  is_active: boolean
  config?: Record<string, any>
}

// 定时任务状态
export interface AutoCollectStatus {
  enabled: boolean
  interval_hours: number
  next_run_time?: string
  last_run_time?: string
  running: boolean
}

// 审计日志条目
export interface LogEntry {
  time: string
  level: 'info' | 'warn' | 'error'
  module: string
  message: string
}
