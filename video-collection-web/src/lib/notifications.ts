import { getToken } from './auth';

export interface NotificationItem {
  id: number;
  type: 'system' | 'comment' | 'like';
  title: string;
  content: string;
  target_type: string;
  target_id: number;
  comment_id: number;
  parent_comment_id: number;
  is_read: boolean;
  created_at: string;
}

interface Response<T> { code: number; data: T; msg?: string; error?: string; }

async function notificationRequest<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = getToken();
  if (!token) throw new Error('请先登录');
  const response = await fetch(path, {
    ...options,
    headers: { Authorization: `Bearer ${token}`, ...options.headers },
  });
  const result = await response.json() as T & { code: number; msg?: string; error?: string };
  if (!response.ok || result.code !== 1) throw new Error(result.msg || result.error || '请求失败');
  return result;
}

export function listNotifications(page = 1, unreadOnly = false): Promise<{ data: NotificationItem[]; total: number; unread_count: number }> {
  const query = new URLSearchParams({ page: String(page), page_size: '20' });
  if (unreadOnly) query.set('unread_only', 'true');
  return notificationRequest(`/api/user/notifications?${query}`);
}

export async function getUnreadCount(): Promise<number> {
  const result = await notificationRequest<Response<{ unread_count: number }>>('/api/user/notifications/unread-count');
  return result.data.unread_count;
}

export function markNotificationsRead(ids?: number[]): Promise<unknown> {
  return notificationRequest('/api/user/notifications/read', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(ids ? { ids } : { all: true }),
  });
}

export function deleteNotification(id: number): Promise<unknown> {
  return notificationRequest(`/api/user/notifications?id=${id}`, { method: 'DELETE' });
}

export function notificationLink(item: NotificationItem): string | null {
  if (item.target_id < 1) return null;
  const base = item.target_type === 'post' ? `/community/${item.target_id}`
    : item.target_type === 'news' ? `/news/${item.target_id}`
    : item.target_type === 'video' ? `/anime/${item.target_id}` : null;
  if (!base) return null;
  return item.comment_id ? `${base}?comment_id=${item.comment_id}#comments` : base;
}
