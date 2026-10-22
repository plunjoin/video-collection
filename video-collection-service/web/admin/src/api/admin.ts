import request from '@/utils/request'

export interface RAGChunk {
  id: number
  source_type: string
  source_id: string
  subject_id: number
  chunk_index: number
  text: string
  similarity: number
  metadata: Record<string, unknown>
}

export interface RAGAskResponse {
  query: string
  answer: string
  citations: RAGChunk[]
  model: string
  embedder: string
  top_k: number
  graph_note?: string
}

export interface RAGQuery {
  q?: string
  query?: string
  top_k?: number
  source_type?: string
}

export function ragRebuild() {
  return request.post<any, { code: number; chunks_indexed: number; embedder: string }>('/api/admin/rag/rebuild', {}, { timeout: 0 })
}

export function ragSearch(params: RAGQuery) {
  return request.get<any, ApiResponse<{ query: string; top_k: number; results: RAGChunk[] }>>('/api/admin/rag/search', { params, timeout: 0 })
}

export function ragAsk(data: RAGQuery) {
  return request.post<any, ApiResponse<RAGAskResponse>>('/api/admin/rag/ask', data, { timeout: 0 })
}
import type {
  ApiResponse,
  AdminStats,
  SourceConfig,
  CollectionTemplate,
  UserInfo,
  FeedbackItem,
  ThemeInfo,
  AnalyticsOverview,
  AutoCollectStatus,
  LogEntry,
  DBInfo,
  DBTableInfo,
  TableBrowseResult,
  DeleteRowsResult,
  ClearTableResult,
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

// 1.1 留存与功能渗透率看板
export function getRetention() {
  return request.get<any, ApiResponse<{ retention: any; penetration: any }>>('/api/admin/retention')
}

// 1.2 广告位管理
export function getAds(slot?: string) {
  return request.get<any, ApiResponse<any[]>>('/api/admin/ads', { params: slot ? { slot } : {} })
}
export function saveAd(data: any) {
  return request.post<any, ApiResponse<any>>('/api/admin/ads', data)
}
export function deleteAd(id: number) {
  return request.delete<any, ApiResponse>(`/api/admin/ads?id=${id}`)
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

export function getCollectionTemplates() {
  return request.get<any, ApiResponse<CollectionTemplate[]>>('/api/admin/sources/templates')
}

// 连通性探测测试
export function testSource(data: Partial<SourceConfig>) {
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

// 7. 埋点信息预览：网站 / App PV-UV 总览
export function getAnalyticsOverview() {
  return request.get<any, ApiResponse<AnalyticsOverview>>('/api/admin/analytics/overview')
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

// 按主键删除选中行（仅超级管理员）
export function deleteTableRows(table: string, rows: Record<string, any>[]) {
  return request.post<any, ApiResponse<DeleteRowsResult>>('/api/admin/db/table/rows/delete', {
    table,
    rows
  })
}

// 清空整表（仅超级管理员，不可逆）
export function clearTable(table: string) {
  return request.post<any, ApiResponse<ClearTableResult>>('/api/admin/db/table/clear', {
    table,
    confirm: true
  })
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

// 12. Wiki 知识库管理
export function getWikiSubjects(params?: { page?: number; page_size?: number; type?: string; sub_type?: string; keyword?: string }) {
  return request.get<any, ApiResponse<any[]>>('/api/wiki/subjects', { params })
}

export function getWikiSubjectDetail(id: number) {
  return request.get<any, ApiResponse<any>>('/api/wiki/subject', { params: { id } })
}

export function saveWikiSubject(data: any) {
  if (data.id) {
    return request.put<any, ApiResponse<any>>('/api/admin/wiki/subjects', data)
  }
  return request.post<any, ApiResponse<{ id: number }>>('/api/admin/wiki/subjects', data)
}

export function deleteWikiSubject(id: number) {
  return request.delete<any, ApiResponse>(`/api/admin/wiki/subjects?id=${id}`)
}

export function createWikiRelation(data: { source_id: number; target_id: number; relation_type: string; role_description?: string; sort_order?: number }) {
  return request.post<any, ApiResponse<{ id: number }>>('/api/admin/wiki/relations', data)
}

export function deleteWikiRelation(id: number) {
  return request.delete<any, ApiResponse>(`/api/admin/wiki/relations?id=${id}`)
}

export function getWikiGraph(id: number, depth: number = 1) {
  return request.get<any, ApiResponse<{ nodes: any[]; edges: any[] }>>('/api/wiki/graph', { params: { id, depth } })
}

export function syncVideoToWiki(videoId: number) {
  return request.post<any, ApiResponse<{ subject: any }>>('/api/admin/wiki/sync-video', { video_id: videoId })
}

