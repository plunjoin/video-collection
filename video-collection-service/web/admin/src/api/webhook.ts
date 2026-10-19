import request from '@/utils/request'
import type { ApiResponse } from '@/types'

export interface Webhook {
  id: string
  name: string
  secret_hint: string
  target: 'video' | 'record'
  duplicate: 'update' | 'skip'
  events: string[]
  source_id: string
  tolerance_sec: number
  enabled: boolean
  created_at: string
  updated_at: string
}

export interface WebhookDelivery {
  id: number
  webhook_id: string
  webhook_name: string
  event: string
  status: 'accepted' | 'rejected' | 'duplicate' | 'error' | 'ignored'
  imported: number
  error_message: string
  remote_ip: string
  raw_body: string
  created_at: string
}

export interface WebhookStats {
  total: number
  accepted: number
  rejected: number
  duplicate: number
  error: number
  imported_total: number
  last_status: string
  last_delivery_at?: string
}

export interface WebhookCreatePayload {
  name: string
  target?: 'video' | 'record'
  duplicate?: 'update' | 'skip'
  events?: string[]
  source_id?: string
  tolerance_sec?: number
}

// 端点列表（含密钥掩码，不含明文）
export function listWebhooks() {
  return request.get<any, ApiResponse<Webhook[]>>('/api/admin/webhooks')
}

// 创建端点：data.secret 为明文密钥，仅本次返回
export function createWebhook(data: WebhookCreatePayload) {
  return request.post<any, ApiResponse<{ webhook: Webhook; secret: string }>>('/api/admin/webhooks', data)
}

// 轮换密钥：旧密钥立即失效，data.secret 仅本次返回
export function rotateWebhookSecret(id: string) {
  return request.post<any, ApiResponse<{ id: string; secret: string }>>(`/api/admin/webhooks/secret?id=${id}`)
}

// 投递日志（含原始报文）
export function listDeliveries(params: {
  id?: string
  status?: string
  keyword?: string
  page?: number
  page_size?: number
}) {
  return request.get<any, ApiResponse<WebhookDelivery[]>>('/api/admin/webhooks/deliveries', { params })
}

// 单端点统计
export function getWebhookStats(id: string) {
  return request.get<any, ApiResponse<WebhookStats>>('/api/admin/webhooks/stats', { params: { id } })
}

// 清理投递日志：days>0 按保留天数，0 清空全部
export function cleanupDeliveries(data: { id?: string; days: number }) {
  return request.post<any, ApiResponse<{ deleted: number }>>('/api/admin/webhooks/deliveries/cleanup', data)
}

// 前端辅助：生成采集入口地址
export function ingestUrl(id: string) {
  return `${window.location.origin}/api/webhooks/${id}/ingest`
}
