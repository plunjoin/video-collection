import { getToken } from './auth';

export type CommentTarget = 'video' | 'news' | 'post';

export interface CommentItem {
  id: number;
  target_type: CommentTarget;
  target_id: number;
  parent_id: number;
  root_id: number;
  user_id: number;
  author_name: string;
  author_avatar: string;
  content: string;
  is_deleted: boolean;
  like_count: number;
  reply_count: number;
  liked: boolean;
  created_at: string;
}

export interface Page<T> {
  data: T[];
  total: number;
  page: number;
  page_size: number;
}

interface ApiResponse<T> {
  code: number;
  data: T;
  msg?: string;
  error?: string;
}

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = getToken();
  const response = await fetch(path, {
    ...options,
    headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...options.headers },
  });
  const result = await response.json() as T & { code: number; msg?: string; error?: string };
  if (!response.ok || result.code !== 1) throw new Error(result.msg || result.error || '请求失败，请稍后重试');
  return result;
}

export function listComments(targetType: CommentTarget, targetId: number, page = 1, pageSize = 20, rootId = 0): Promise<Page<CommentItem>> {
  const query = new URLSearchParams({ target_type: targetType, target_id: String(targetId), page: String(page), page_size: String(pageSize) });
  if (rootId) query.set('root_id', String(rootId));
  return request<Page<CommentItem>>(`/api/comments?${query}`);
}

export async function getComment(id: number): Promise<CommentItem> {
  const result = await request<ApiResponse<CommentItem>>(`/api/comments?id=${id}`);
  return result.data;
}

export async function createComment(targetType: CommentTarget, targetId: number, content: string, parentId = 0): Promise<CommentItem> {
  const result = await request<ApiResponse<CommentItem>>('/api/comments', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ target_type: targetType, target_id: targetId, parent_id: parentId, content }),
  });
  return result.data;
}

export function deleteComment(id: number): Promise<ApiResponse<unknown>> {
  return request<ApiResponse<unknown>>(`/api/comments?id=${id}`, { method: 'DELETE' });
}

export async function setCommentLike(id: number, liked: boolean): Promise<{ liked: boolean; like_count: number }> {
  const result = await request<ApiResponse<{ liked: boolean; like_count: number }>>(
    liked ? '/api/comments/likes' : `/api/comments/likes?comment_id=${id}`,
    liked ? { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ comment_id: id }) } : { method: 'DELETE' },
  );
  return result.data;
}
