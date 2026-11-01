import request from '@/utils/request'

export interface MailTemplate {
  subject: string
  body: string
}

export interface MailConfig {
  enabled: boolean
  host: string
  port: string
  user: string
  /** 读取时恒为空串，保存时留空表示保持原密码 */
  pass: string
  pass_set?: boolean
  from: string
  from_name: string
  /** ssl | starttls | none */
  encryption: string
  template: MailTemplate
  configured?: boolean
}

export interface SMSConfig {
  enabled: boolean
  /** webhook | none */
  provider: string
  webhook_url: string
  /** 读取时恒为空串，保存时留空表示保持原令牌 */
  token: string
  token_set?: boolean
  template: string
  configured?: boolean
}

export interface StorageConfig {
  /** local | oss | s3 */
  provider: string
  endpoint: string
  region: string
  bucket: string
  access_key: string
  /** 读取时恒为空串，保存时留空表示保持原密钥 */
  secret_key: string
  secret_set?: boolean
  domain: string
  prefix: string
  path_style: boolean
  configured?: boolean
}

export interface IntegrationConfig {
  mail: MailConfig
  sms: SMSConfig
  storage: StorageConfig
}

export interface IntegrationResponse {
  code: number
  msg?: string
  data: IntegrationConfig
  dev_mode?: boolean
}

export interface StorageProbeResult {
  provider: string
  url: string
  deleted: boolean
}

export function getIntegrations() {
  return request.get<any, IntegrationResponse>('/api/admin/integrations')
}

export function saveIntegrations(data: IntegrationConfig) {
  return request.post<any, IntegrationResponse>('/api/admin/integrations', data)
}

/** 用已保存的配置发一封测试邮件 */
export function testMail(to: string) {
  return request.post<any, { code: number; msg: string }>('/api/admin/integrations/test/mail', { to }, { timeout: 0 })
}

/** 用已保存的配置发一条测试短信 */
export function testSMS(phone: string) {
  return request.post<any, { code: number; msg: string }>('/api/admin/integrations/test/sms', { phone }, { timeout: 0 })
}

/** 上传探针文件验证存储读写权限 */
export function testStorage() {
  return request.post<any, { code: number; msg: string; data: StorageProbeResult }>(
    '/api/admin/integrations/test/storage',
    {},
    { timeout: 0 }
  )
}
