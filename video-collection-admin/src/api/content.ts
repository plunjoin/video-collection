import request from '@/utils/request'
import type { ApiResponse, ContentItem, CommunityCommentItem } from '@/types'

// ==================== 资讯管理 (/api/admin/news) ====================

// 资讯列表 (支持关键词/分类/状态筛选与分页)
export function getNewsList(params?: {
  page?: number
  page_size?: number
  keyword?: string
  category?: string
  status?: string
}) {
  return request.get<any, ApiResponse<ContentItem[]>>('/api/admin/news', { params })
}

// 资讯详情
export function getNewsDetail(id: number) {
  return request.get<any, ApiResponse<ContentItem>>(`/api/admin/news?id=${id}`)
}

// 保存资讯 (id 为 0 时新增，否则编辑；管理员可设置 status 与 pinned)
export function saveNews(data: {
  id: number
  title: string
  summary: string
  content: string
  cover: string
  category: string
  status: string
  pinned: boolean
}) {
  return request.post<any, ApiResponse<ContentItem>>('/api/admin/news', data)
}

// 删除资讯
export function deleteNews(id: number) {
  return request.delete<any, ApiResponse>(`/api/admin/news?id=${id}`)
}

// ==================== 社区帖子管理 (/api/admin/community/posts) ====================

// 帖子列表 (支持关键词/分类/状态筛选与分页)
export function getPostList(params?: {
  page?: number
  page_size?: number
  keyword?: string
  category?: string
  status?: string
}) {
  return request.get<any, ApiResponse<ContentItem[]>>('/api/admin/community/posts', { params })
}

// 保存帖子 (id 为 0 时新增，否则编辑；管理员可设置 status 与 pinned)
export function savePost(data: {
  id: number
  title: string
  summary: string
  content: string
  cover: string
  category: string
  status: string
  pinned: boolean
}) {
  return request.post<any, ApiResponse<ContentItem>>('/api/admin/community/posts', data)
}

// 删除帖子
export function deletePost(id: number) {
  return request.delete<any, ApiResponse>(`/api/admin/community/posts?id=${id}`)
}

// ==================== 社区评论管理 (/api/admin/community/comments) ====================

// 帖子评论列表 (post_id 必填)
export function getCommentList(params: {
  post_id: number
  page?: number
  page_size?: number
}) {
  return request.get<any, ApiResponse<CommunityCommentItem[]>>('/api/admin/community/comments', {
    params
  })
}

// 删除评论
export function deleteComment(id: number) {
  return request.delete<any, ApiResponse>(`/api/admin/community/comments?id=${id}`)
}
