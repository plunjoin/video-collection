import request from '@/utils/request'
import type { ApiResponse, Category, VideoRecord } from '@/types'

// 获取所有分类
export function getCategories() {
  return request.get<any, ApiResponse<Category[]>>('/api/categories')
}

// 视频分页与模糊检索
export function getVideos(params: {
  page?: number
  page_size?: number
  type_id?: number
  keyword?: string
}) {
  return request.get<any, ApiResponse<VideoRecord[]>>('/api/videos', { params })
}

// 视频详情
export function getVideoDetail(id: number) {
  return request.get<any, ApiResponse<VideoRecord>>('/api/video', {
    params: { id }
  })
}

// 保存视频（新增或编辑）
export function saveVideo(data: Partial<VideoRecord>) {
  return request.post<any, ApiResponse<{ id: number }>>('/api/admin/videos/save', data)
}

// 删除单个视频
export function deleteVideo(id: number) {
  return request.delete<any, ApiResponse>(`/api/admin/videos?id=${id}`)
}

// 批量删除视频
export function batchDeleteVideos(ids: number[]) {
  return request.post<any, ApiResponse>('/api/admin/videos/batch-delete', { ids })
}
