import request from '@/utils/request'
import type { ApiResponse } from '@/types'

export type BusinessDataType = 'text' | 'integer' | 'real' | 'boolean' | 'json'
export interface BusinessFieldInput {
  name: string
  label: string
  data_type: BusinessDataType
  required: boolean
  sort_order: number
}
export interface BusinessTypeField extends BusinessFieldInput { is_system: boolean }
export interface BusinessType {
  slug: string
  name: string
  description: string
  is_system: boolean
  writer: string
  key_field: string
  fields: BusinessTypeField[]
}
export interface BusinessRow {
  id?: number
  record_key?: string
  source_id: string
  target?: string
  key?: string
  payload?: Record<string, unknown>
  values?: Record<string, string>
  content_id?: number
  created_at?: string
  updated_at?: string
  [key: string]: unknown
}
export interface BusinessTypeInput { slug: string; name: string; description: string; fields: BusinessFieldInput[] }
const base = '/api/admin/business-types'
const path = (slug: string) => `${base}/${encodeURIComponent(slug)}`
export const listBusinessTypes = () => request.get<any, ApiResponse<BusinessType[]>>(base)
export const createBusinessType = (data: BusinessTypeInput) => request.post<any, ApiResponse<BusinessType>>(base, data)
export const updateBusinessType = (slug: string, data: { name: string; description: string }) => request.put<any, ApiResponse>(path(slug), data)
export const deleteBusinessType = (slug: string) => request.delete<any, ApiResponse>(path(slug))
export const listBusinessRows = (slug: string, page = 1, pageSize = 20) => request.get<any, ApiResponse<BusinessRow[]>>(`${path(slug)}/rows`, { params: { page, page_size: pageSize } })
export const deleteBusinessRow = (slug: string, params: { id?: number; source_id?: string; key?: string }) => request.delete<any, ApiResponse>(`${path(slug)}/rows`, { params })
export const addBusinessField = (slug: string, data: BusinessFieldInput) => request.post<any, ApiResponse>(`${path(slug)}/fields`, data)
export const updateBusinessField = (slug: string, name: string, data: { label: string; required: boolean }) => request.put<any, ApiResponse>(`${path(slug)}/fields/${encodeURIComponent(name)}`, data)
export const deleteBusinessField = (slug: string, name: string) => request.delete<any, ApiResponse>(`${path(slug)}/fields/${encodeURIComponent(name)}`)
export const newBusinessField = (): BusinessFieldInput => ({ name: '', label: '', data_type: 'text', required: false, sort_order: 0 })
