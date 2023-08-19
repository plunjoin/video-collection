import request from '@/utils/request'
import type { ApiResponse } from '@/types'

export interface FieldRule {
  target: string; selector: string; attribute: string; default: string
  required: boolean; trim: boolean; strip_html: boolean; pattern: string; replacement: string
}
export interface PipelineRule {
  version: number; input: 'api' | 'html' | 'database' | 'file'; target: 'record' | 'article' | 'video'
  key_field: string; duplicate: 'update' | 'skip'; max_records: number
  request: { method: string; body: string; list_path: string; page_param: string; start_page: number }
  html: { item_selector: string; detail_selector: string; next_selector: string }
  database: { driver: string; dsn_env: string; query: string }
  file: { token: string; name: string; sheet: string; header_row: number }
  fields: FieldRule[]
}
export interface PipelineSource {
  id: string; name: string; type: 'pipeline'; api: string; active: boolean; enabled: boolean
  collect_hours: number; page_limit: number; timeout_sec: number; retry_count: number; interval_ms: number
  headers: Record<string, string>; custom_params: Record<string, string>; filter: { pipeline: PipelineRule }
}
export interface Sample { raw: Record<string, string>; values: Record<string, string>; errors: string[] }
export interface CollectedRecord { key: string; target: string; values: Record<string, string>; content_id: number; updated_at: string }
export const previewCollection = (source: PipelineSource) => request.post<any, ApiResponse<Sample[]>>('/api/admin/collection/preview', source)
export const uploadCollection = (file: File) => {
  const body = new FormData(); body.append('file', file)
  return request.post<any, ApiResponse<{ token: string; name: string }>>('/api/admin/collection/upload', body, { headers: { 'Content-Type': 'multipart/form-data' } })
}
export const collectionRecords = (id: string, page: number) => request.get<any, ApiResponse<CollectedRecord[]>>('/api/admin/collection/records', { params: { source_id: id, page, page_size: 20 } })

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
