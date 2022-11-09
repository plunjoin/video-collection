import request from '@/utils/request'
import type {
  ApiResponse,
  AdminStats,
  SourceConfig,
  UserInfo,
  FeedbackItem,
  ThemeInfo,
  PlayerInfo,
  AutoCollectStatus,
  LogEntry,
  DBInfo,
  DBTableInfo,
  TableBrowseResult,
  BackupResult,
  BackupMeta,
  RestorePreview,
  RestoreResult,
  CleanupResult,
  SQLExecResult
} from '@/types'

// 1. 系统仪表盘统计
export function getAdminStats() {
  return request.get<any, ApiResponse<AdminStats>>('/api/admin/stats')
}

// 2. 采集点管理
export function getSources() {
  return request.get<any, ApiResponse<SourceConfig[]>>('/api/admin/sources')
}

export function saveSource(data: Partial<SourceConfig>) {
  return request.post<any, ApiResponse<{ id: string }>>('/api/admin/sources', data)
}

export function deleteSource(id: string) {
  return request.delete<any, ApiResponse>(`/api/admin/sources?id=${encodeURIComponent(id)}`)
}

// 连通性探测测试
export function testSource(data: {
  api: string
  type: string
  headers?: Record<string, string>
  custom_params?: Record<string, string>
  custom_mapping?: any
}) {
  return request.post<any, ApiResponse<any>>('/api/admin/sources/test', data)
}

// 触发单个采集任务 (hours: 0 全量，24 近24小时增量)
export function triggerCollect(sourceId: string, hours: number) {
  return request.post<any, ApiResponse>('/api/admin/sources/collect', {
    source_id: sourceId,
    hours
  })
}

// 一键采集全网所有采集点
export function triggerCollectAll(hours: number) {
  return request.post<any, ApiResponse>('/api/admin/sources/collect-all', {
    hours
  })
}

// 3. 定时采集调度任务
export function getAutoCollectStatus() {
  return request.get<any, ApiResponse<AutoCollectStatus>>('/api/admin/scheduler/auto')
}

export function saveAutoCollectConfig(data: { enabled: boolean; interval_hours: number }) {
  return request.post<any, ApiResponse>('/api/admin/scheduler/auto', data)
}

// 4. 用户账号管理
export function getUsers() {
  return request.get<any, ApiResponse<UserInfo[]>>('/api/admin/users')
}

export function saveUser(data: {
  id?: number
  username: string
  password?: string
  nickname: string
  role: string
  status: number
}) {
  return request.post<any, ApiResponse<{ id?: number }>>('/api/admin/users', data)
}

export function deleteUser(id: number) {
  return request.delete<any, ApiResponse>(`/api/admin/users?id=${id}`)
}

// 5. 求片与报错反馈管理
export function getFeedbacks(params?: {
  page?: number
  page_size?: number
  status?: string
  type?: string
}) {
  return request.get<any, ApiResponse<FeedbackItem[]>>('/api/admin/feedbacks', { params })
}

export function replyFeedback(data: { id: number; status: string; reply: string }) {
  return request.post<any, ApiResponse>('/api/admin/feedbacks/reply', data)
}

export function deleteFeedback(id: number) {
  return request.delete<any, ApiResponse>(`/api/admin/feedbacks?id=${id}`)
}

// 6. 客户端主题管理
export function getThemes() {
  return request.get<any, ApiResponse<ThemeInfo[]>>('/api/admin/themes')
}

export function switchTheme(themeId: string) {
  return request.post<any, ApiResponse>('/api/admin/themes/switch', { theme_id: themeId })
}

export function uploadTheme(formData: FormData) {
  return request.post<any, ApiResponse<ThemeInfo>>('/api/admin/themes/upload', formData, {
    headers: { 'Content-Type': 'multipart/form-data' }
  })
}

// 7. 播放器管理
export function getPlayers() {
  return request.get<any, ApiResponse<PlayerInfo[]>>('/api/admin/players')
}

export function switchPlayer(playerId: string) {
  return request.post<any, ApiResponse>('/api/admin/players/switch', { player_id: playerId })
}

export function updatePlayerConfig(playerId: string, config: Record<string, any>) {
  return request.post<any, ApiResponse>('/api/admin/players/config', {
    player_id: playerId,
    config
  })
}

export function uploadPlayer(formData: FormData) {
  return request.post<any, ApiResponse<PlayerInfo>>('/api/admin/players/upload', formData, {
    headers: { 'Content-Type': 'multipart/form-data' }
  })
}

// 8. 站点全局配置
export function getSiteConfig() {
  return request.get<any, ApiResponse<Record<string, string>>>('/api/site/config')
}

export function saveSiteConfig(data: Record<string, string>) {
  return request.post<any, ApiResponse>('/api/admin/site/config', data)
}

// 9. 运行审计日志
export function getLogs(limit: number = 100) {
  return request.get<any, ApiResponse<LogEntry[]>>('/api/admin/logs', {
    params: { limit }
  })
}

// 10. 数据库管理
export function getDBInfo() {
  return request.get<any, ApiResponse<DBInfo>>('/api/admin/db/info')
}

export function getDBTables() {
  return request.get<any, ApiResponse<DBTableInfo[]>>('/api/admin/db/tables')
}

export function browseTable(params: {
  table: string
  page?: number
  page_size?: number
  order_by?: string
  order_desc?: number
  keyword?: string
}) {
  return request.get<any, ApiResponse<TableBrowseResult>>('/api/admin/db/table', { params })
}

export function createBackup(tables?: string[]) {
  return request.post<any, ApiResponse<BackupResult>>('/api/admin/db/backup', { tables })
}

export function getBackups() {
  return request.get<any, ApiResponse<BackupMeta[]>>('/api/admin/db/backups')
}

export function deleteBackup(filename: string) {
  return request.delete<any, ApiResponse>(
    `/api/admin/db/backups?file=${encodeURIComponent(filename)}&confirm=1`
  )
}

export function previewRestore(file: string, mode: 'merge' | 'replace') {
  return request.post<any, ApiResponse<RestorePreview>>('/api/admin/db/restore', {
    file,
    mode,
    dry_run: true
  })
}

export function restoreDatabase(file: string, mode: 'merge' | 'replace') {
  return request.post<any, ApiResponse<RestoreResult>>('/api/admin/db/restore', {
    file,
    mode,
    confirm: true
  })
}

export function runCleanup(actions: string[]) {
  return request.post<any, ApiResponse<CleanupResult[]>>('/api/admin/db/cleanup', {
    actions,
    confirm: true
  })
}

export function execSQL(sql: string, confirm: boolean = false) {
  return request.post<any, ApiResponse<SQLExecResult>>('/api/admin/db/sql', {
    sql,
    confirm
  })
}
