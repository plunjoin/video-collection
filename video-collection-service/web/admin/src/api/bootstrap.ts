import request from '@/utils/request'
import type { ApiResponse } from '@/types'

export interface BootstrapConfigInfo {
  /** 基础配置 SQLite 文件路径 */
  path: string
  /** 掩码后的键值配置 */
  config: Record<string, string>
  /** 每一项的生效来源（env:XXX / bootstrap） */
  sources: Record<string, string>
  note?: string
}

// 读取基础配置（敏感字段以 ******** 回显）
export function getBootstrapConfig() {
  return request.get<any, ApiResponse<BootstrapConfigInfo>>('/api/admin/bootstrap')
}

// 保存基础配置（敏感字段传 ******** 表示不修改）
export function saveBootstrapConfig(data: Record<string, string>) {
  return request.put<any, ApiResponse<{ saved: boolean; note?: string }>>('/api/admin/bootstrap', data)
}

// 测试数据库连通性（保存前验证）
export function testBootstrapDB(data: Record<string, string>) {
  return request.post<any, ApiResponse<{ ok: boolean; message: string }>>('/api/admin/bootstrap/test-db', data)
}
