import request from '@/utils/request'
import type { ApiResponse } from '@/types'

export interface FieldRule {
  target: string; selector: string; attribute: string; default: string
  required: boolean; trim: boolean; strip_html: boolean; pattern: string; replacement: string
}
export interface PipelineRule {
  version: number; input: 'api' | 'rss' | 'html' | 'database' | 'file' | 'webhook'; target: 'record' | 'article' | 'video'
  key_field: string; duplicate: 'update' | 'skip'; max_records: number
  request: { method: string; body: string; list_path: string; page_param: string; start_page: number }
  html: { item_selector: string; detail_selector: string; next_selector: string }
  database: { driver: string; dsn_env: string; query: string }
  file: { token: string; name: string; sheet: string; header_row: number }
  fields: FieldRule[]
}
export interface PipelineSource {
  id: string; name: string; type: 'pipeline' | 'webhook'; api: string; active: boolean; enabled: boolean
  collect_hours: number; page_limit: number; timeout_sec: number; retry_count: number; interval_ms: number
  headers: Record<string, string>; custom_params: Record<string, string>; filter: { pipeline: PipelineRule }
}
export interface Sample { raw: Record<string, string>; values: Record<string, string>; errors: string[] }
export interface CollectedRecord { key: string; target: string; values: Record<string, string>; content_id: number; updated_at: string }
export interface CollectionTask {
  id: number
  source_id: string
  source_name: string
  trigger_type: string // "manual" | "cron"
  collect_hours: number
  status: 'running' | 'success' | 'failed' | 'stopped'
  total_fetched: number
  total_saved: number
  total_skipped: number
  error_message: string
  started_at: string
  ended_at?: string
  duration_ms: number
  created_at: string
  updated_at: string
}
export interface CollectionLog {
  id: number
  task_id: number
  source_id: string
  source_name: string
  level: 'INFO' | 'WARN' | 'SUCCESS' | 'ERROR'
  message: string
  created_at: string
}

export const previewCollection = (source: PipelineSource) => request.post<any, ApiResponse<Sample[]>>('/api/admin/collection/preview', source)
export const uploadCollection = (file: File) => {
  const body = new FormData(); body.append('file', file)
  return request.post<any, ApiResponse<{ token: string; name: string }>>('/api/admin/collection/upload', body, { headers: { 'Content-Type': 'multipart/form-data' } })
}
export const collectionRecords = (id: string, page: number) => request.get<any, ApiResponse<CollectedRecord[]>>('/api/admin/collection/records', { params: { source_id: id, page, page_size: 20 } })
export const updateCollectionRecord = (data: { source_id: string; target?: string; key: string; values: Record<string, string> }) => request.put<any, ApiResponse>('/api/admin/collection/records', data)
export const deleteCollectionRecord = (params: { source_id: string; target?: string; key: string }) => request.delete<any, ApiResponse>('/api/admin/collection/records', { params })
export const rectifyRecordToWiki = (data: { source_id: string; target?: string; key: string; subject: any }) => request.post<any, ApiResponse<any>>('/api/admin/collection/records/to-wiki', data)
export const rectifyRecordToVideo = (data: { source_id: string; target?: string; key: string; play_url?: string; play_from?: string; video: any }) => request.post<any, ApiResponse<{ id: number }>>('/api/admin/collection/records/to-video', data)
export const batchRectifyRecords = (data: { source_id?: string; target?: string }) => request.post<any, ApiResponse<{ rectified_count: number }>>('/api/admin/collection/records/batch-rectify', data)
export const importSampleRecords = (source_id: string, target = 'record') => request.post<any, ApiResponse<{ count: number }>>('/api/admin/collection/records/sample', { source_id, target })

export const getCollectionTasks = (params?: { page?: number; page_size?: number; source_id?: string; status?: string; trigger_type?: string }) => request.get<any, ApiResponse<CollectionTask[]>>('/api/admin/collection/tasks', { params })
export const getCollectionTaskDetail = (id: number) => request.get<any, ApiResponse<{ task: CollectionTask; logs: CollectionLog[] }>>('/api/admin/collection/tasks/detail', { params: { id } })
export const getCollectionLogs = (params?: { page?: number; page_size?: number; task_id?: number; source_id?: string; level?: string; keyword?: string }) => request.get<any, ApiResponse<CollectionLog[]>>('/api/admin/collection/logs', { params })
export const clearCollectionLogs = (days = 15) => request.post<any, ApiResponse<{ deleted: number }>>('/api/admin/collection/logs/cleanup', { days })


export function field(target = '', selector = ''): FieldRule {
  return { target, selector, attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' }
}
export function newRule(input: PipelineRule['input'] = 'api'): PipelineSource {
  return {
    id: 'rule_' + crypto.randomUUID(), name: '', type: 'pipeline', api: '', active: false, enabled: false,
    collect_hours: 0, page_limit: 5, timeout_sec: 15, retry_count: 1, interval_ms: 300, headers: {}, custom_params: {},
    filter: { pipeline: {
      version: 1, input, target: 'record', key_field: 'id', duplicate: 'update', max_records: 1000,
      request: { method: 'GET', body: '', list_path: 'data.items', page_param: '', start_page: 1 },
      html: { item_selector: '.item', detail_selector: '', next_selector: '' },
      database: { driver: 'postgres', dsn_env: 'IMPORT_DATABASE_DSN', query: 'SELECT id, title, content FROM articles' },
      file: { token: '', name: '', sheet: '', header_row: 1 },
      fields: input === 'html' ? [field('id', 'a'), field('title', 'h2'), field('content', '.content')] : [field('id', 'id'), field('title', 'title'), field('content', 'content')]
    } }
  }
}

export function newTMDBPopularActorsPreset(): PipelineSource {
  return {
    id: 'rule_' + crypto.randomUUID(),
    name: 'TMDB 热门影人与演职员档案库',
    type: 'pipeline',
    api: 'https://api.themoviedb.org/3/person/popular',
    active: false,
    enabled: false,
    collect_hours: 0,
    page_limit: 5,
    timeout_sec: 15,
    retry_count: 2,
    interval_ms: 500,
    headers: { Accept: 'application/json' },
    custom_params: { api_key: 'YOUR_TMDB_API_KEY', language: 'zh-CN' },
    filter: {
      pipeline: {
        version: 1,
        input: 'api',
        target: 'record',
        key_field: 'actor_id',
        duplicate: 'update',
        max_records: 100,
        request: { method: 'GET', body: '', list_path: 'results', page_param: 'page', start_page: 1 },
        html: { item_selector: '', detail_selector: '', next_selector: '' },
        database: { driver: 'postgres', dsn_env: '', query: '' },
        file: { token: '', name: '', sheet: '', header_row: 1 },
        fields: [
          { target: 'actor_id', selector: 'id', attribute: 'text', default: '', required: true, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'name', selector: 'name', attribute: 'text', default: '', required: true, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'gender', selector: 'gender', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'popularity', selector: 'popularity', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'avatar', selector: 'profile_path', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '^(/.*)$', replacement: 'https://image.tmdb.org/t/p/w500$1' },
          { target: 'known_for', selector: 'known_for.0.title', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' }
        ]
      }
    }
  }
}

export function newTMDBSearchPersonPreset(): PipelineSource {
  return {
    id: 'rule_' + crypto.randomUUID(),
    name: 'TMDB 演员名称精准搜索',
    type: 'pipeline',
    api: 'https://api.themoviedb.org/3/search/person',
    active: false,
    enabled: false,
    collect_hours: 0,
    page_limit: 1,
    timeout_sec: 15,
    retry_count: 2,
    interval_ms: 500,
    headers: { Accept: 'application/json' },
    custom_params: { api_key: 'YOUR_TMDB_API_KEY', language: 'zh-CN', query: '张译' },
    filter: {
      pipeline: {
        version: 1,
        input: 'api',
        target: 'record',
        key_field: 'actor_id',
        duplicate: 'update',
        max_records: 20,
        request: { method: 'GET', body: '', list_path: 'results', page_param: 'page', start_page: 1 },
        html: { item_selector: '', detail_selector: '', next_selector: '' },
        database: { driver: 'postgres', dsn_env: '', query: '' },
        file: { token: '', name: '', sheet: '', header_row: 1 },
        fields: [
          { target: 'actor_id', selector: 'id', attribute: 'text', default: '', required: true, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'name', selector: 'name', attribute: 'text', default: '', required: true, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'gender', selector: 'gender', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'popularity', selector: 'popularity', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'avatar', selector: 'profile_path', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '^(/.*)$', replacement: 'https://image.tmdb.org/t/p/w500$1' },
          { target: 'known_for', selector: 'known_for.0.title', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' }
        ]
      }
    }
  }
}

export function newTMDBMoviePreset(): PipelineSource {
  return {
    id: 'rule_' + crypto.randomUUID(),
    name: 'TMDB 热门影视作品全量',
    type: 'pipeline',
    api: 'https://api.themoviedb.org/3/discover/movie',
    active: false,
    enabled: false,
    collect_hours: 0,
    page_limit: 5,
    timeout_sec: 15,
    retry_count: 2,
    interval_ms: 500,
    headers: { Accept: 'application/json' },
    custom_params: { api_key: 'YOUR_TMDB_API_KEY', language: 'zh-CN', sort_by: 'popularity.desc' },
    filter: {
      pipeline: {
        version: 1,
        input: 'api',
        target: 'video',
        key_field: 'title',
        duplicate: 'update',
        max_records: 100,
        request: { method: 'GET', body: '', list_path: 'results', page_param: 'page', start_page: 1 },
        html: { item_selector: '', detail_selector: '', next_selector: '' },
        database: { driver: 'postgres', dsn_env: '', query: '' },
        file: { token: '', name: '', sheet: '', header_row: 1 },
        fields: [
          { target: 'title', selector: 'title', attribute: 'text', default: '', required: true, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'cover', selector: 'poster_path', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '^(/.*)$', replacement: 'https://image.tmdb.org/t/p/w500$1' },
          { target: 'content', selector: 'overview', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'year', selector: 'release_date', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'remarks', selector: 'vote_average', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'category', selector: 'genre_ids.0', attribute: 'text', default: '电影', required: false, trim: true, strip_html: false, pattern: '', replacement: '' }
        ]
      }
    }
  }
}

export function newMacCMSVideoPreset(): PipelineSource {
  return {
    id: 'rule_' + crypto.randomUUID(),
    name: 'MacCMS · 标准影视 JSON 采集（自动分集与多线路）',
    type: 'pipeline',
    api: 'https://example.com/api.php/provide/vod/',
    active: false,
    enabled: false,
    collect_hours: 24,
    page_limit: 10,
    timeout_sec: 15,
    retry_count: 2,
    interval_ms: 300,
    headers: { 'User-Agent': 'Mozilla/5.0 BlliiFamiliar/1.0' },
    custom_params: { ac: 'detail', h: '{hours}' },
    filter: {
      pipeline: {
        version: 1,
        input: 'api',
        target: 'video',
        key_field: 'title',
        duplicate: 'update',
        max_records: 200,
        request: { method: 'GET', body: '', list_path: 'list', page_param: 'pg', start_page: 1 },
        html: { item_selector: '', detail_selector: '', next_selector: '' },
        database: { driver: 'postgres', dsn_env: '', query: '' },
        file: { token: '', name: '', sheet: '', header_row: 1 },
        fields: [
          { target: 'title', selector: 'vod_name', attribute: 'text', default: '', required: true, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'play_url', selector: 'vod_play_url', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'play_from', selector: 'vod_play_from', attribute: 'text', default: 'm3u8', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'cover', selector: 'vod_pic', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'category', selector: 'type_name', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'year', selector: 'vod_year', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'remarks', selector: 'vod_remarks', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'actor', selector: 'vod_actor', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'director', selector: 'vod_director', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'area', selector: 'vod_area', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'content', selector: 'vod_content', attribute: 'text', default: '', required: false, trim: true, strip_html: true, pattern: '', replacement: '' }
        ]
      }
    }
  }
}

export function newAGIHuntPreset(): PipelineSource {
  return {
    id: 'rule_' + crypto.randomUUID(),
    name: 'AGI Hunt · AI 实时快讯 / 日报',
    type: 'pipeline',
    api: 'https://agihunt.info/feed.xml',
    active: false,
    enabled: true,
    collect_hours: 0,
    page_limit: 1,
    timeout_sec: 15,
    retry_count: 2,
    interval_ms: 300,
    headers: { 'User-Agent': 'Mozilla/5.0 (compatible; BlliiFamiliar/1.0; +https://bllii.fun)' },
    custom_params: {},
    filter: {
      pipeline: {
        version: 1,
        input: 'rss',
        target: 'article',
        key_field: 'link',
        duplicate: 'skip',
        max_records: 50,
        request: { method: 'GET', body: '', list_path: '', page_param: '', start_page: 1 },
        html: { item_selector: '', detail_selector: '', next_selector: '' },
        database: { driver: 'postgres', dsn_env: '', query: '' },
        file: { token: '', name: '', sheet: '', header_row: 1 },
        fields: [
          { target: 'title', selector: 'title', attribute: 'text', default: '', required: true, trim: true, strip_html: true, pattern: '', replacement: '' },
          { target: 'content', selector: 'description', attribute: 'text', default: '', required: true, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'summary', selector: 'summary', attribute: 'text', default: '', required: false, trim: true, strip_html: true, pattern: '', replacement: '' },
          { target: 'link', selector: 'link', attribute: 'text', default: '', required: true, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'category', selector: 'category', attribute: 'text', default: 'AI快讯', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'cover', selector: 'cover', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'author', selector: 'creator', attribute: 'text', default: 'AGI Hunt', required: false, trim: true, strip_html: false, pattern: '', replacement: '' }
        ]
      }
    }
  }
}


