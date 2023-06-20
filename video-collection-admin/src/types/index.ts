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
  type: 'json' | 'xml' | 'rss' | 'custom' | 'custom_json' | 'pipeline'
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

// ========== 数据库管理 ==========

// 数据库整体信息
export interface DBInfo {
  engine: 'postgres' | 'sqlite'
  driver: string
  version: string
  host?: string
  database?: string
  file_path?: string
  size_bytes: number
  table_count: number
  backups_dir: string
  server_time: string
}

// 单表统计信息
export interface DBTableInfo {
  name: string
  rows: number
  approximate: boolean
  size_bytes: number
  column_count: number
  index_count: number
  comment?: string
}

// 表字段信息
export interface TableColumn {
  name: string
  data_type: string
}

// 表数据浏览结果
export interface TableBrowseResult {
  columns: TableColumn[]
  rows: Record<string, any>[]
  total: number
  page: number
  page_size: number
}

// 备份创建结果
export interface BackupResult {
  filename: string
  file_path: string
  size_bytes: number
  tables: number
  rows: number
  created_at: string
}

// 备份文件元信息
export interface BackupMeta {
  filename: string
  size_bytes: number
  created_at: string
  engine: string
  tables: number
  rows: number
}

// 恢复预览中的单表
export interface RestorePreviewTable {
  name: string
  rows: number
  exists: boolean
}

// 恢复预览结果
export interface RestorePreview {
  file: string
  mode: 'merge' | 'replace'
  engine: string
  created_at: string
  tables: RestorePreviewTable[]
}

// 恢复执行结果
export interface RestoreResult {
  file: string
  mode: string
  tables: number
  inserted: number
  skipped: number
  elapsed: string
}

// 清理动作结果
export interface CleanupResult {
  action: string
  affected: number
  error?: string
}

// SQL 执行结果
export interface SQLExecResult {
  type: 'select' | 'write' | 'ddl'
  columns?: string[]
  rows?: Record<string, any>[]
  row_count?: number
  truncated?: boolean
  affected?: number
  message?: string
}

// 资讯/社区帖子内容 (kind: news=资讯, post=社区帖子)
export interface ContentItem {
  id: number
  kind: 'news' | 'post'
  author_id: number
  author_name: string
  author_avatar: string
  title: string
  summary: string
  content: string
  cover: string
  category: string
  status: 'published' | 'draft' | 'hidden'
  pinned: boolean
  like_count: number
  comment_count: number
  liked: boolean
  created_at: string
  updated_at: string
}

// 社区帖子评论
export interface CommunityCommentItem {
  id: number
  target_type: string
  target_id: number
  post_id: number
  parent_id: number
  root_id: number
  user_id: number
  author_name: string
  author_avatar: string
  content: string
  is_deleted: boolean
  like_count: number
  reply_count: number
  liked: boolean
  created_at: string
}
