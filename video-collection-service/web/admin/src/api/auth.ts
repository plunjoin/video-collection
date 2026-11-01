import request from '@/utils/request'
import type { ApiResponse, UserInfo } from '@/types'

// 登录
export function login(data: { username: string; password: string }) {
  return request.post<any, ApiResponse<{ token: string; user: UserInfo }>>('/api/login', data)
}

// 登出
export function logout() {
  return request.post<any, ApiResponse>('/api/logout')
}

// 获取当前登录用户
export function getMe() {
  return request.get<any, ApiResponse<UserInfo>>('/api/me')
}

// 修改当前账号密码（成功后服务端会吊销其他设备会话）
export function changePassword(data: { old_password: string; new_password: string }) {
  return request.post<any, ApiResponse<{ revoked_sessions: number }>>('/api/me/password', data)
}

export interface LoginSession {
  id: string
  current: boolean
  ip: string
  user_agent: string
  created_at: string
  expires_at: string
}

// 当前账号的登录设备列表
export function getSessions() {
  return request.get<any, ApiResponse<LoginSession[]>>('/api/me/sessions')
}

// 下线指定设备
export function revokeSession(id: string) {
  return request.delete<any, ApiResponse>(`/api/me/sessions?id=${encodeURIComponent(id)}`)
}
