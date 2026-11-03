<template>
  <div class="integrations-page">
    <r-card shadow="never" class="main-card" v-loading="loading">
      <div class="page-header">
        <div class="header-copy">
          <span class="page-title">外部服务接入配置</span>
          <span class="sub-desc">
            SMTP 邮件、短信网关与对象存储的可视化配置；保存后立即生效，无需重启服务
          </span>
        </div>
        <div class="header-right">
          <r-button :icon="Refresh" :loading="loading" @click="loadData">重新读取</r-button>
          <r-button type="primary" :icon="Check" :loading="saving" :disabled="!canEdit" @click="handleSave">
            保存配置
          </r-button>
        </div>
      </div>

      <!-- 通道状态总览 -->
      <div class="status-strip">
        <div v-for="item in statusCards" :key="item.key" class="status-card" :class="`is-${item.tone}`">
          <div class="status-head">
            <span class="status-name">{{ item.name }}</span>
            <r-tag size="small" :type="item.tagType" effect="plain">{{ item.tagText }}</r-tag>
          </div>
          <span class="status-detail">{{ item.detail }}</span>
        </div>
      </div>

      <r-alert v-if="!canEdit" type="info" show-icon title="当前角色为只读" class="hint-alert">
        只有超级管理员可以修改集成配置，你可以查看脱敏后的当前配置。
      </r-alert>
      <r-alert v-else-if="devMode" type="warning" show-icon title="开发模式已开启" class="hint-alert">
        环境变量 <code>ACCOUNT_DEV_CODE=1</code> 生效中：验证码会直接随接口返回而不真正发送，
        仅用于本地联调，正式环境请去掉该变量。
      </r-alert>

      <r-tabs v-model="activeTab">
        <!-- ============================ 邮件通道 ============================ -->
        <r-tab-pane label="邮件通道 (SMTP)" name="mail">
          <r-form :model="form.mail" label-width="150px" class="integration-form">
            <r-divider content-position="left">发送开关</r-divider>

            <r-form-item label="启用邮件发送">
              <r-switch v-model="form.mail.enabled" :disabled="!canEdit" />
              <span class="inline-tip">
                关闭后验证码邮件不会发出，找回密码与邮箱绑定将不可用
              </span>
            </r-form-item>

            <r-divider content-position="left">SMTP 服务器</r-divider>

            <r-form-item label="服务器地址">
              <r-input
                v-model="form.mail.host"
                :disabled="!canEdit"
                placeholder="例如：smtp.exmail.qq.com / smtp.gmail.com"
                style="width: 340px"
              />
            </r-form-item>

            <r-form-item label="端口">
              <r-input
                v-model="form.mail.port"
                :disabled="!canEdit"
                placeholder="465 / 587 / 25"
                style="width: 160px"
              />
              <span class="inline-tip">SSL 常用 465，STARTTLS 常用 587</span>
            </r-form-item>

            <r-form-item label="加密方式">
              <r-select v-model="form.mail.encryption" :disabled="!canEdit" style="width: 340px">
                <r-option label="SSL / TLS（隐式加密，端口 465）" value="ssl" />
                <r-option label="STARTTLS（明文连接后升级，端口 587）" value="starttls" />
                <r-option label="不加密（仅内网 / 本地邮件中继）" value="none" />
              </r-select>
            </r-form-item>

            <r-form-item label="登录账号">
              <r-input
                v-model="form.mail.user"
                :disabled="!canEdit"
                placeholder="通常为完整邮箱地址"
                style="width: 340px"
                autocomplete="off"
              />
            </r-form-item>

            <r-form-item label="登录密码 / 授权码">
              <r-input
                v-model="form.mail.pass"
                type="password"
                show-password
                :disabled="!canEdit"
                :placeholder="form.mail.pass_set ? '已配置，留空表示保持不变' : '邮箱授权码或 SMTP 专用密码'"
                style="width: 340px"
                autocomplete="new-password"
              />
              <r-tag v-if="form.mail.pass_set" size="small" type="success" effect="plain" class="inline-tag">
                已保存
              </r-tag>
            </r-form-item>

            <r-form-item label="发件人邮箱">
              <r-input
                v-model="form.mail.from"
                :disabled="!canEdit"
                placeholder="例如：noreply@example.com"
                style="width: 340px"
              />
            </r-form-item>

            <r-form-item label="发件人显示名">
              <r-input
                v-model="form.mail.from_name"
                :disabled="!canEdit"
                placeholder="例如：某某站点"
                style="width: 340px"
              />
            </r-form-item>

            <r-divider content-position="left">邮件模板（占位符会被自动替换）</r-divider>

            <r-form-item label="可用占位符">
              <div class="placeholder-row">
                <r-tag v-for="p in mailPlaceholders" :key="p.key" size="small" effect="plain" class="mono-tag">
                  {{ p.key }}
                </r-tag>
                <span class="inline-tip">{{ mailPlaceholderHint }}</span>
              </div>
            </r-form-item>

            <r-form-item label="邮件主题">
              <r-input
                v-model="form.mail.template.subject"
                :disabled="!canEdit"
                :placeholder="defaultSubjectHint"
                style="width: 480px"
              />
            </r-form-item>

            <r-form-item label="邮件正文">
              <r-input
                v-model="form.mail.template.body"
                type="textarea"
                :rows="8"
                :disabled="!canEdit"
                :placeholder="defaultBodyHint"
                style="width: 560px"
              />
            </r-form-item>

            <r-form-item label="模板实时预览">
              <div class="preview-box">
                <div class="preview-subject">
                  <span class="preview-label">主题</span>
                  <span>{{ previewMailSubject }}</span>
                </div>
                <pre class="preview-body">{{ previewMailBody }}</pre>
              </div>
            </r-form-item>

            <r-divider content-position="left">连通性测试</r-divider>

            <r-form-item label="收件邮箱">
              <div class="test-row">
                <r-input
                  v-model="testMailTo"
                  :disabled="!canEdit"
                  placeholder="接收测试邮件的邮箱地址"
                  style="width: 300px"
                />
                <r-button
                  type="primary"
                  plain
                  :icon="Lightning"
                  :loading="testingMail"
                  :disabled="!canEdit || !mailReady"
                  @click="handleTestMail"
                >
                  发送测试邮件
                </r-button>
                <span v-if="!mailReady" class="inline-tip">
                  需先填写服务器地址与发件人邮箱并保存
                </span>
              </div>
            </r-form-item>

            <r-form-item label="常见服务商参数">
              <div class="provider-hints">
                <button
                  v-for="preset in mailPresets"
                  :key="preset.name"
                  type="button"
                  class="preset-chip"
                  :disabled="!canEdit"
                  @click="applyMailPreset(preset)"
                >
                  {{ preset.name }}
                </button>
                <span class="inline-tip">点击一键填入服务器、端口与加密方式</span>
              </div>
            </r-form-item>
          </r-form>
        </r-tab-pane>

        <!-- ============================ 短信通道 ============================ -->
        <r-tab-pane label="短信通道" name="sms">
          <r-form :model="form.sms" label-width="150px" class="integration-form">
            <r-divider content-position="left">发送开关</r-divider>

            <r-form-item label="启用短信发送">
              <r-switch v-model="form.sms.enabled" :disabled="!canEdit" />
              <span class="inline-tip">关闭后手机号绑定与短信验证码找回密码不可用</span>
            </r-form-item>

            <r-divider content-position="left">网关接入</r-divider>

            <r-form-item label="接入方式">
              <r-select v-model="form.sms.provider" :disabled="!canEdit" style="width: 340px">
                <r-option label="自建 HTTP 网关（POST JSON）" value="webhook" />
                <r-option label="不接入" value="none" />
              </r-select>
            </r-form-item>

            <r-form-item label="网关地址">
              <r-input
                v-model="form.sms.webhook_url"
                :disabled="!canEdit"
                placeholder="https://sms.example.com/api/send"
                style="width: 460px"
              />
            </r-form-item>

            <r-form-item label="接口令牌">
              <r-input
                v-model="form.sms.token"
                type="password"
                show-password
                :disabled="!canEdit"
                :placeholder="form.sms.token_set ? '已配置，留空表示保持不变' : '以 Authorization: Bearer <令牌> 发送'"
                style="width: 460px"
                autocomplete="new-password"
              />
              <r-tag v-if="form.sms.token_set" size="small" type="success" effect="plain" class="inline-tag">
                已保存
              </r-tag>
            </r-form-item>

            <r-form-item label="请求体格式">
              <pre class="code-block">{{ smsRequestPreview }}</pre>
              <span class="inline-tip">网关返回 HTTP 2xx 即视为发送成功，非 2xx 的响应体会作为错误提示</span>
            </r-form-item>

            <r-divider content-position="left">短信模板（占位符会被自动替换）</r-divider>

            <r-form-item label="可用占位符">
              <div class="placeholder-row">
                <r-tag v-for="p in smsPlaceholders" :key="p.key" size="small" effect="plain" class="mono-tag">
                  {{ p.key }}
                </r-tag>
                <span class="inline-tip">{{ smsPlaceholderHint }}</span>
              </div>
            </r-form-item>

            <r-form-item label="短信正文">
              <r-input
                v-model="form.sms.template"
                type="textarea"
                :rows="5"
                :disabled="!canEdit"
                :placeholder="defaultSMSHint"
                style="width: 560px"
              />
            </r-form-item>

            <r-form-item label="模板实时预览">
              <div class="preview-box">
                <pre class="preview-body">{{ previewSMS }}</pre>
                <span class="preview-meta">共 {{ previewSMS.length }} 字，约 {{ smsSegments }} 条计费</span>
              </div>
            </r-form-item>

            <r-divider content-position="left">连通性测试</r-divider>

            <r-form-item label="接收手机号">
              <div class="test-row">
                <r-input
                  v-model="testPhone"
                  :disabled="!canEdit"
                  placeholder="中国大陆手机号，如 13800000000"
                  style="width: 260px"
                />
                <r-button
                  type="primary"
                  plain
                  :icon="Lightning"
                  :loading="testingSMS"
                  :disabled="!canEdit || !smsReady"
                  @click="handleTestSMS"
                >
                  发送测试短信
                </r-button>
                <span v-if="!smsReady" class="inline-tip">需先填写网关地址并保存</span>
              </div>
            </r-form-item>
          </r-form>
        </r-tab-pane>

        <!-- ============================ 存储与上传 ============================ -->
        <r-tab-pane label="存储与上传" name="storage">
          <r-form :model="form.storage" label-width="150px" class="integration-form">
            <r-divider content-position="left">落地位置</r-divider>

            <r-form-item label="存储方式">
              <r-select v-model="form.storage.provider" :disabled="!canEdit" style="width: 420px">
                <r-option label="本地磁盘（服务端 uploads 目录，由 /uploads/ 直出）" value="local" />
                <r-option label="阿里云 OSS（V1 签名）" value="oss" />
                <r-option label="S3 兼容协议（COS / R2 / MinIO / AWS）" value="s3" />
              </r-select>
              <span class="inline-tip">头像等上传文件会写入这里；切换后历史文件仍按记录的来源分派删除</span>
            </r-form-item>

            <template v-if="form.storage.provider === 'local'">
              <r-alert type="info" show-icon class="hint-alert" title="本地磁盘模式">
                文件写入服务进程的工作目录下的 uploads 文件夹，通过 <code>/uploads/</code> 静态路由对外提供。
                该目录需可写，且建议纳入备份；多实例部署时请改用对象存储。
              </r-alert>
            </template>

            <template v-else>
              <r-form-item label="Endpoint">
                <r-input
                  v-model="form.storage.endpoint"
                  :disabled="!canEdit"
                  placeholder="https://oss-cn-hangzhou.aliyuncs.com"
                  style="width: 460px"
                />
                <span class="inline-tip">可省略协议，默认补 https://</span>
              </r-form-item>

              <r-form-item label="Region">
                <r-input
                  v-model="form.storage.region"
                  :disabled="!canEdit"
                  placeholder="cn-hangzhou / ap-guangzhou / auto"
                  style="width: 260px"
                />
                <span class="inline-tip">留空则尝试从 Endpoint 推断，推断失败回退 us-east-1</span>
              </r-form-item>

              <r-form-item label="Bucket">
                <r-input
                  v-model="form.storage.bucket"
                  :disabled="!canEdit"
                  placeholder="例如：my-bucket"
                  style="width: 320px"
                />
              </r-form-item>

              <r-form-item label="AccessKey ID">
                <r-input
                  v-model="form.storage.access_key"
                  :disabled="!canEdit"
                  placeholder="访问密钥 ID"
                  style="width: 320px"
                  autocomplete="off"
                />
              </r-form-item>

              <r-form-item label="AccessKey Secret">
                <r-input
                  v-model="form.storage.secret_key"
                  type="password"
                  show-password
                  :disabled="!canEdit"
                  :placeholder="form.storage.secret_set ? '已配置，留空表示保持不变' : '访问密钥 Secret'"
                  style="width: 320px"
                  autocomplete="new-password"
                />
                <r-tag v-if="form.storage.secret_set" size="small" type="success" effect="plain" class="inline-tag">
                  已保存
                </r-tag>
              </r-form-item>

              <r-form-item label="访问域名">
                <r-input
                  v-model="form.storage.domain"
                  :disabled="!canEdit"
                  placeholder="选填，如 https://cdn.example.com"
                  style="width: 460px"
                />
                <span class="inline-tip">填写后文件 URL 直接走该域名；留空则按下方规则拼接</span>
              </r-form-item>

              <r-form-item label="对象前缀">
                <r-input
                  v-model="form.storage.prefix"
                  :disabled="!canEdit"
                  placeholder="uploads/"
                  style="width: 260px"
                />
                <span class="inline-tip">会自动补末尾斜杠，避免与桶内其他业务混在一起</span>
              </r-form-item>

              <r-form-item label="寻址风格">
                <r-switch
                  v-model="form.storage.path_style"
                  :disabled="!canEdit"
                  active-text="Path Style：endpoint/bucket/key"
                  inactive-text="Virtual Host：bucket.endpoint/key"
                />
                <span class="inline-tip">阿里云 OSS、MinIO 一般用 Path Style；AWS、COS、R2 用 Virtual Host</span>
              </r-form-item>

              <r-form-item label="URL 预览">
                <pre class="code-block">{{ previewObjectURL }}</pre>
              </r-form-item>
            </template>

            <r-divider content-position="left">连通性测试</r-divider>

            <r-form-item label="读写探测">
              <div class="test-row">
                <r-button
                  type="primary"
                  plain
                  :icon="Upload"
                  :loading="testingStorage"
                  :disabled="!canEdit"
                  @click="handleTestStorage"
                >
                  上传探针文件并删除
                </r-button>
                <span class="inline-tip">
                  会用当前已保存的配置上传一个 probe/ 下的临时文件，校验写入与删除权限后立即删除
                </span>
              </div>
            </r-form-item>

            <r-form-item v-if="probeResult" label="上次探测结果">
              <div class="probe-box">
                <div class="probe-line">
                  <span class="preview-label">存储类型</span>
                  <r-tag size="small" type="primary" effect="plain">{{ probeResult.provider }}</r-tag>
                </div>
                <div class="probe-line">
                  <span class="preview-label">对象地址</span>
                  <span class="mono-text breakable">{{ probeResult.url }}</span>
                </div>
                <div class="probe-line">
                  <span class="preview-label">清理状态</span>
                  <r-tag size="small" :type="probeResult.deleted ? 'success' : 'warning'" effect="plain">
                    {{ probeResult.deleted ? '探针文件已删除' : '删除失败，请检查删除权限' }}
                  </r-tag>
                </div>
              </div>
            </r-form-item>
          </r-form>
        </r-tab-pane>
      </r-tabs>

      <r-divider />

      <div class="footer-bar">
        <r-button type="primary" :icon="Check" :loading="saving" :disabled="!canEdit" @click="handleSave">
          保存配置
        </r-button>
        <r-button :disabled="saving" @click="loadData">放弃修改</r-button>
        <span class="foot-tip">
          密钥类字段读取时不下发明文；输入框留空保存表示沿用已保存的值。
        </span>
      </div>
    </r-card>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import {
  getIntegrations,
  saveIntegrations,
  testMail,
  testSMS,
  testStorage,
  type IntegrationConfig,
  type StorageProbeResult
} from '@/api/integrations'
import { notify } from '@/components/radix/feedback'
import { Check, Lightning, Refresh, Upload } from '@/components/radix/icons'
import { useUserStore } from '@/store/user'

const userStore = useUserStore()
const canEdit = computed(() => userStore.userInfo?.role === 'super_admin')

const loading = ref(false)
const saving = ref(false)
const devMode = ref(false)
const activeTab = ref('mail')

const form = reactive<IntegrationConfig>({
  mail: {
    enabled: false,
    host: '',
    port: '587',
    user: '',
    pass: '',
    pass_set: false,
    from: '',
    from_name: '',
    encryption: 'starttls',
    template: { subject: '', body: '' },
    configured: false
  },
  sms: {
    enabled: false,
    provider: 'webhook',
    webhook_url: '',
    token: '',
    token_set: false,
    template: '',
    configured: false
  },
  storage: {
    provider: 'local',
    endpoint: '',
    region: '',
    bucket: '',
    access_key: '',
    secret_key: '',
    secret_set: false,
    domain: '',
    prefix: 'uploads/',
    path_style: true,
    configured: true
  }
})

const testMailTo = ref('')
const testPhone = ref('')
const testingMail = ref(false)
const testingSMS = ref(false)
const testingStorage = ref(false)
const probeResult = ref<StorageProbeResult | null>(null)

// ---------------------------------------------------------------- 状态总览

const statusCards = computed(() => {
  const mail = form.mail
  const sms = form.sms
  const storage = form.storage
  return [
    {
      key: 'mail',
      name: '邮件通道',
      tone: mail.configured ? 'ok' : mail.enabled ? 'warn' : 'off',
      tagType: mail.configured ? 'success' : mail.enabled ? 'warning' : 'info',
      tagText: mail.configured ? '可用' : mail.enabled ? '待补全' : '未启用',
      detail: mail.host ? `${mail.host}:${mail.port || '-'} · ${mail.encryption}` : '尚未填写 SMTP 服务器'
    },
    {
      key: 'sms',
      name: '短信通道',
      tone: sms.configured ? 'ok' : sms.enabled ? 'warn' : 'off',
      tagType: sms.configured ? 'success' : sms.enabled ? 'warning' : 'info',
      tagText: sms.configured ? '可用' : sms.enabled ? '待补全' : '未启用',
      detail: sms.webhook_url || '尚未填写网关地址'
    },
    {
      key: 'storage',
      name: '上传存储',
      tone: 'ok',
      tagType: 'success',
      tagText: storage.provider === 'local' ? '本地磁盘' : storage.provider.toUpperCase(),
      detail:
        storage.provider === 'local'
          ? '服务端 uploads 目录'
          : `${storage.bucket || '未填 Bucket'} · ${storage.endpoint || '未填 Endpoint'}`
    }
  ]
})

// 只要填了服务器地址和发件人就能测（不必先开启开关），测的是「已保存」的配置
const mailReady = computed(() => Boolean(form.mail.host.trim() && form.mail.from.trim()))
const smsReady = computed(() => Boolean(form.sms.webhook_url.trim()))

// ---------------------------------------------------------------- 模板占位符

const mailPlaceholders = [
  { key: '{{site}}', hint: '站点名称' },
  { key: '{{code}}', hint: '验证码' },
  { key: '{{purpose}}', hint: '用途' },
  { key: '{{expires}}', hint: '有效分钟数' },
  { key: '{{target}}', hint: '接收目标' },
  { key: '{{email}}', hint: '收件邮箱' }
]

const smsPlaceholders = [
  { key: '{{site}}', hint: '站点名称' },
  { key: '{{code}}', hint: '验证码' },
  { key: '{{purpose}}', hint: '用途' },
  { key: '{{expires}}', hint: '有效分钟数' },
  { key: '{{phone}}', hint: '接收手机号' }
]

const mailPlaceholderHint = computed(() =>
  mailPlaceholders.map((item) => `${item.key} = ${item.hint}`).join('，')
)
const smsPlaceholderHint = computed(() =>
  smsPlaceholders.map((item) => `${item.key} = ${item.hint}`).join('，')
)

// 输入框占位提示：后端未配置时实际生效的内置默认模板
const defaultSubjectHint = '站点名称 + 用途 + 验证码，例如：示例站点 找回密码验证码'
const defaultBodyHint =
  '支持换行。默认模板：您好，您正在进行找回密码操作，验证码为 246810，10 分钟内有效。占位符写作双花括号包住变量名。'
const defaultSMSHint =
  '单条建议不超过 70 字。默认模板：您正在进行找回密码操作，验证码 246810，10 分钟内有效。'

const sampleVars: Record<string, string> = {
  site: '示例站点',
  code: '246810',
  purpose: '找回密码',
  expires: '10',
  target: 'demo@example.com',
  email: 'demo@example.com',
  phone: '138****0000'
}

function render(tpl: string): string {
  return (tpl || '').replace(/\{\{\s*([a-zA-Z_]+)\s*\}\}/g, (match, name: string) => {
    const key = name.toLowerCase()
    return key in sampleVars ? sampleVars[key] : match
  })
}

const previewMailSubject = computed(
  () => render(form.mail.template.subject) || '（未填写主题，将使用内置默认模板）'
)
const previewMailBody = computed(
  () => render(form.mail.template.body) || '（未填写正文，将使用内置默认模板）'
)
const previewSMS = computed(() => render(form.sms.template) || '（未填写短信正文）')
// 运营商按 70 字一条计费（含签名），超过则按长短信拆分
const smsSegments = computed(() => Math.max(1, Math.ceil(previewSMS.value.length / 70)))

// 短信网关实际收到的请求长这样，直接展示给管理员核对
const smsRequestPreview = computed(() => {
  const url = form.sms.webhook_url.trim() || '<网关地址>'
  const auth = form.sms.token_set ? '******' : '<令牌>'
  return [
    `POST ${url}`,
    'Content-Type: application/json',
    `Authorization: Bearer ${auth}`,
    '',
    '{ "phone": "13800000000", "content": "渲染后的短信正文" }'
  ].join('\n')
})

// ---------------------------------------------------------------- 存储 URL 预览

const previewObjectURL = computed(() => {
  const s = form.storage
  const prefix = s.prefix.trim().replace(/^\/+/, '').replace(/\/*$/, '')
  const key = `${prefix ? `${prefix}/` : ''}avatars/example.png`
  if (s.provider === 'local') return `/uploads/${key}`
  const domain = s.domain.trim().replace(/\/+$/, '')
  if (domain) return `${domain}/${key}`
  const rawEndpoint = s.endpoint.trim().replace(/\/+$/, '')
  if (!rawEndpoint) return '（填写 Endpoint 后显示）'
  const withScheme = rawEndpoint.includes('://') ? rawEndpoint : `https://${rawEndpoint}`
  const scheme = withScheme.slice(0, withScheme.indexOf('://'))
  const host = withScheme.slice(withScheme.indexOf('://') + 3)
  const bucket = s.bucket.trim() || '<bucket>'
  if (s.path_style) return `${scheme}://${host}/${bucket}/${key}`
  return `${scheme}://${bucket}.${host}/${key}`
})

// ---------------------------------------------------------------- 服务商预设

interface MailPreset {
  name: string
  host: string
  port: string
  encryption: string
}

const mailPresets: MailPreset[] = [
  { name: '腾讯企业邮', host: 'smtp.exmail.qq.com', port: '465', encryption: 'ssl' },
  { name: 'QQ 邮箱', host: 'smtp.qq.com', port: '465', encryption: 'ssl' },
  { name: '163 邮箱', host: 'smtp.163.com', port: '465', encryption: 'ssl' },
  { name: '阿里云邮件推送', host: 'smtpdm.aliyun.com', port: '465', encryption: 'ssl' },
  { name: 'Gmail', host: 'smtp.gmail.com', port: '587', encryption: 'starttls' },
  { name: 'SendGrid', host: 'smtp.sendgrid.net', port: '587', encryption: 'starttls' }
]

function applyMailPreset(preset: MailPreset) {
  form.mail.host = preset.host
  form.mail.port = preset.port
  form.mail.encryption = preset.encryption
  notify(`已填入 ${preset.name} 的服务器参数，记得保存`, 'success')
}

// ---------------------------------------------------------------- 数据读写

function assignConfig(data: IntegrationConfig) {
  if (!data) return
  if (data.mail) {
    Object.assign(form.mail, data.mail)
    form.mail.template = {
      subject: data.mail.template?.subject || '',
      body: data.mail.template?.body || ''
    }
    // 脱敏字段每次重新读取都清空输入框，避免把占位值当明文回传
    form.mail.pass = ''
  }
  if (data.sms) {
    Object.assign(form.sms, data.sms)
    form.sms.token = ''
  }
  if (data.storage) {
    Object.assign(form.storage, data.storage)
    form.storage.secret_key = ''
  }
  if (!testMailTo.value) testMailTo.value = form.mail.from || form.mail.user || ''
}

const loadData = async () => {
  loading.value = true
  try {
    const res = await getIntegrations()
    if (res.code === 1 && res.data) {
      assignConfig(res.data)
      devMode.value = Boolean(res.dev_mode)
    }
  } finally {
    loading.value = false
  }
}

const handleSave = async () => {
  if (!canEdit.value) {
    notify('仅超级管理员可修改集成配置', 'warning')
    return
  }
  saving.value = true
  try {
    const res = await saveIntegrations({
      mail: {
        ...form.mail,
        host: form.mail.host.trim(),
        port: form.mail.port.trim(),
        user: form.mail.user.trim(),
        from: form.mail.from.trim(),
        from_name: form.mail.from_name.trim(),
        template: {
          subject: form.mail.template.subject.trim(),
          body: form.mail.template.body
        }
      },
      sms: {
        ...form.sms,
        provider: form.sms.provider,
        webhook_url: form.sms.webhook_url.trim(),
        template: form.sms.template
      },
      storage: {
        ...form.storage,
        endpoint: form.storage.endpoint.trim(),
        region: form.storage.region.trim(),
        bucket: form.storage.bucket.trim(),
        access_key: form.storage.access_key.trim(),
        domain: form.storage.domain.trim(),
        prefix: form.storage.prefix.trim()
      }
    })
    if (res.code === 1 && res.data) {
      assignConfig(res.data)
      notify(res.msg || '集成配置已保存并即时生效', 'success')
    }
  } finally {
    saving.value = false
  }
}

// ---------------------------------------------------------------- 连通性测试

const handleTestMail = async () => {
  const to = testMailTo.value.trim()
  if (!to) {
    notify('请填写接收测试邮件的邮箱', 'warning')
    return
  }
  testingMail.value = true
  try {
    const res = await testMail(to)
    if (res.code === 1) notify(res.msg || '测试邮件已发送', 'success')
  } finally {
    testingMail.value = false
  }
}

const handleTestSMS = async () => {
  const phone = testPhone.value.trim()
  if (!phone) {
    notify('请填写接收测试短信的手机号', 'warning')
    return
  }
  testingSMS.value = true
  try {
    const res = await testSMS(phone)
    if (res.code === 1) notify(res.msg || '测试短信已发送', 'success')
  } finally {
    testingSMS.value = false
  }
}

const handleTestStorage = async () => {
  testingStorage.value = true
  try {
    const res = await testStorage()
    if (res.code === 1) {
      probeResult.value = res.data
      notify(res.msg || '存储读写正常', res.data?.deleted === false ? 'warning' : 'success')
    }
  } finally {
    testingStorage.value = false
  }
}

onMounted(loadData)
</script>

<style scoped>
.integrations-page {
  .main-card {
    border-radius: 12px;
    border: 1px solid var(--border-color);
    max-width: 1040px;
    margin: 0 auto;

    .page-header {
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      gap: 16px;
      margin-bottom: 14px;

      .header-copy {
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .page-title {
        font-size: 13px;
        font-weight: 600;
        letter-spacing: 0;
        color: var(--text-primary);
      }

      .sub-desc {
        font-size: 10px;
        color: var(--text-secondary);
      }

      .header-right {
        display: flex;
        gap: 8px;
        flex-shrink: 0;
      }
    }

    .status-strip {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 10px;
      margin-bottom: 14px;

      .status-card {
        display: flex;
        flex-direction: column;
        gap: 4px;
        padding: 10px 12px;
        border: 1px solid var(--border-color);
        border-radius: 10px;
        background: var(--surface);
        min-width: 0;

        &.is-ok {
          border-color: var(--success);
        }
        &.is-warn {
          border-color: var(--warning);
        }

        .status-head {
          display: flex;
          justify-content: space-between;
          align-items: center;
          gap: 8px;
        }

        .status-name {
          font-size: 11px;
          font-weight: 600;
          color: var(--text-primary);
        }

        .status-detail {
          font-size: 10px;
          color: var(--text-secondary);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      }
    }

    .hint-alert {
      margin-bottom: 12px;
    }

    .integration-form {
      padding: 6px 0 2px;
    }

    .inline-tip {
      margin-left: 10px;
      font-size: 10px;
      color: var(--text-secondary);
      line-height: 1.6;
    }

    .inline-tag {
      margin-left: 8px;
    }

    .placeholder-row {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 6px;
    }

    .mono-tag {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    }

    .preview-box {
      width: 560px;
      max-width: 100%;
      padding: 10px 12px;
      border: 1px dashed var(--border-color);
      border-radius: 8px;
      background: var(--bg-color);

      .preview-subject {
        display: flex;
        gap: 8px;
        font-size: 11px;
        color: var(--text-primary);
        margin-bottom: 6px;
      }

      .preview-label {
        flex-shrink: 0;
        font-size: 10px;
        color: var(--text-secondary);
      }

      .preview-body {
        margin: 0;
        font-size: 11px;
        line-height: 1.7;
        color: var(--text-regular);
        white-space: pre-wrap;
        word-break: break-word;
        font-family: inherit;
      }

      .preview-meta {
        display: block;
        margin-top: 6px;
        font-size: 10px;
        color: var(--text-secondary);
      }
    }

    .code-block {
      margin: 0;
      padding: 10px 12px;
      border-radius: 8px;
      border: 1px solid var(--border-color);
      background: var(--bg-color);
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 11px;
      line-height: 1.7;
      color: var(--text-regular);
      white-space: pre-wrap;
      word-break: break-all;
      max-width: 620px;
    }

    .test-row {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 10px;
    }

    .provider-hints {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 8px;

      .preset-chip {
        padding: 4px 10px;
        font-size: 11px;
        color: var(--text-regular);
        background: var(--surface);
        border: 1px solid var(--border-color);
        border-radius: var(--radius-pill, 999px);
        cursor: pointer;
        transition: background 0.15s ease, border-color 0.15s ease, box-shadow 0.15s ease;

        &:hover:not(:disabled) {
          border-color: var(--brand);
          color: var(--brand);
        }

        &:disabled {
          cursor: not-allowed;
          opacity: 0.6;
        }
      }
    }

    .probe-box {
      display: flex;
      flex-direction: column;
      gap: 6px;
      padding: 10px 12px;
      border: 1px solid var(--border-color);
      border-radius: 8px;
      background: var(--bg-color);
      max-width: 620px;

      .probe-line {
        display: flex;
        align-items: center;
        gap: 8px;
        font-size: 11px;
        color: var(--text-regular);
      }
    }

    .mono-text {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    }

    .breakable {
      word-break: break-all;
    }

    .footer-bar {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 10px;
      padding-bottom: 4px;

      .foot-tip {
        font-size: 10px;
        color: var(--text-secondary);
      }
    }
  }
}

@media (max-width: 900px) {
  .integrations-page .main-card .status-strip {
    grid-template-columns: 1fr;
  }
}
</style>
