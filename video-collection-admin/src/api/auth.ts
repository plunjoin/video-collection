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
