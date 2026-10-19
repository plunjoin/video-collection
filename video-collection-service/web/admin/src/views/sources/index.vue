<template>
  <div class="sources-page">
    <r-card shadow="never" class="table-card">
      <!-- 头部操作区 -->
      <div class="table-header">
        <div class="header-left">
          <span class="page-title">Bllii-Familiar · 使魔节点管理</span>
          <span class="sub-desc">追番使魔多协议与自定义映射节点，支持全网新番感知与通用采集</span>
        </div>
        <div class="header-right">
          <r-button @click="$router.push('/collection-rules')">使魔规则工坊</r-button>
          <r-button type="primary" @click="openEditDialog()">
            <r-icon><Plus /></r-icon>新增使魔节点
          </r-button>
          <r-dropdown trigger="click" @command="handleCollectAll">
            <r-button type="success">
              <r-icon><Refresh /></r-icon>一键唤醒使魔采集<r-icon class="r-icon--right"><ArrowDown /></r-icon>
            </r-button>
            <template #dropdown>
              <r-dropdown-menu>
                <r-dropdown-item :command="24">近 24 小时增量同步</r-dropdown-item>
                <r-dropdown-item :command="0" divided style="color: #e6a23c;">全量历史补全 (耗时较长)</r-dropdown-item>
              </r-dropdown-menu>
            </template>
          </r-dropdown>
          <r-button @click="loadData" :loading="loading">
            <r-icon><RefreshRight /></r-icon>刷新
          </r-button>
        </div>
      </div>

      <!-- 表格内容 -->
      <r-table :data="tableData" v-loading="loading" border stripe style="width: 100%">
        <r-table-column prop="id" label="标识 ID" width="130" />
        <r-table-column prop="name" label="节点名称 (采集源)" min-width="150">
          <template #default="{ row }">
            <span class="font-bold">{{ row.name }}</span>
          </template>
        </r-table-column>
        <r-table-column prop="api" label="接口地址" min-width="260" show-overflow-tooltip>
          <template #default="{ row }">
            <span v-if="isWebhookRow(row)" class="font-mono">{{ row.api }}</span>
            <r-link v-else :href="row.api" target="_blank" type="primary" :underline="false">
              {{ row.api }}
            </r-link>
          </template>
        </r-table-column>
        <r-table-column prop="type" label="协议类型" width="100" align="center">
          <template #default="{ row }">
            <r-tag :type="getTypeTag(row.filter?.collector?.format || row.type)">{{ row.filter?.collector?.format || row.type }}</r-tag>
          </template>
        </r-table-column>
        <r-table-column prop="collect_hours" label="增量策略" width="110" align="center">
          <template #default="{ row }">
            <span>{{ row.collect_hours === 0 ? '全量' : `${row.collect_hours ?? 24} 小时` }}</span>
          </template>
        </r-table-column>
        <r-table-column prop="active" label="状态" width="90" align="center">
          <template #default="{ row }">
            <r-switch
              v-model="row.active"
              @change="handleStatusChange(row)"
              inline-prompt
              active-text="开"
              inactive-text="关"
            />
          </template>
        </r-table-column>
        <r-table-column label="快捷采集" width="180" align="center">
          <template #default="{ row }">
            <template v-if="isWebhookRow(row)">
              <r-tag type="info" size="small">仅接收推送</r-tag>
            </template>
            <template v-else>
              <r-button size="small" type="primary" plain @click="handleCollect(row, row.collect_hours ?? 24)">
                按配置
              </r-button>
              <r-button size="small" type="warning" plain @click="handleCollect(row, 0)">
                全量补全
              </r-button>
            </template>
          </template>
        </r-table-column>
        <r-table-column label="管理操作" width="200" align="center" fixed="right">
          <template #default="{ row }">
            <r-button v-if="!isWebhookRow(row)" size="small" type="info" plain @click="handleTest(row)">测试</r-button>
            <r-button size="small" type="primary" @click="openEditDialog(row)">编辑</r-button>
            <r-button size="small" type="danger" @click="handleDelete(row)">删除</r-button>
          </template>
        </r-table-column>
      </r-table>
    </r-card>

    <!-- 新增/编辑采集点模态框 -->
    <r-dialog
      v-model="dialogVisible"
      :title="editingId ? '编辑采集节点' : '新增采集节点'"
      width="min(900px, 95vw)"
      destroy-on-close
    >
      <r-form ref="formRef" :model="form" :rules="formRules" label-width="110px">
        <r-form-item label="节点名称" prop="name">
          <r-input v-model="form.name" placeholder="例如：自有片库 / 已授权数据源" />
        </r-form-item>
        <r-form-item label="协议类型" prop="type">
          <r-select v-model="form.type" placeholder="选择协议" @change="onProtocolChange">
            <r-option label="规则采集 (HTTP)" value="rule" />
            <r-option label="Webhook 推送" value="webhook" />
          </r-select>
          <p class="config-hint">Webhook 与其它采集源一样在节点里配密钥；关闭节点或密钥过期即可停收。</p>
        </r-form-item>

        <template v-if="form.type === 'webhook'">
          <r-form-item label="API 标识" prop="api">
            <r-input v-model="form.api" placeholder="webhook://collector" />
          </r-form-item>
          <r-form-item label="推送地址">
            <r-input :model-value="'/api/webhooks/collector'" disabled />
            <p class="config-hint">对外完整 URL = 你的公网域名 + 上述路径；请求头可带 X-Collector-Id / X-ACG-Collector-Id（默认 acg-news）。</p>
          </r-form-item>
          <r-form-item label="Webhook 密钥">
            <div class="webhook-secret-row">
              <r-input
                v-model="webhookSecret"
                :type="webhookSecretVisible ? 'text' : 'password'"
                class="webhook-secret-input"
                placeholder="HMAC 验签密钥（与推送方一致）"
              />
              <r-button @click="webhookSecretVisible = !webhookSecretVisible" :disabled="!webhookSecret">
                {{ webhookSecretVisible ? '隐藏' : '显示' }}
              </r-button>
              <r-button @click="copyWebhookSecret" :disabled="!webhookSecret.trim()">复制</r-button>
              <r-button @click="generateWebhookSecret">生成</r-button>
            </div>
            <p class="config-hint">签名：X-ACG-Signature: sha256=&lt;hex(HMAC_SHA256(secret, raw_body))&gt;。生成后会自动显示明文，便于立刻复制给推送方。</p>
          </r-form-item>
          <r-form-item label="密钥过期">
            <r-input v-model="webhookExpiresAt" placeholder="可选，RFC3339，如 2026-12-31T23:59:59Z；留空表示不过期" />
            <p class="config-hint">临时接收：开启节点 + 填密钥 + 可选过期时间；到期或关闭节点即停收。</p>
          </r-form-item>
        </template>

        <template v-else>
          <r-form-item label="规则模板">
            <r-select v-model="templateID" placeholder="选择模板作为起点" @change="applyTemplate">
              <r-option v-for="item in templates" :key="item.id" :label="item.name" :value="item.id" />
            </r-select>
            <p class="config-hint">{{ templates.find(t => t.id === templateID)?.description || '现有规则可直接编辑；模板只在选择时复制。' }}</p>
          </r-form-item>
          <r-form-item label="API 接口地址" prop="api">
            <r-input
              v-model="form.api"
              placeholder="例如：https://api.example.com/api.php/provide/vod/"
            />
          </r-form-item>
          <r-form-item label="默认增量周期" prop="collect_hours">
            <r-input-number v-model="form.collect_hours" :min="0" :max="168" />
            <span style="margin-left: 10px; color: #94a3b8; font-size: 12px;">小时</span>
          </r-form-item>
          <r-form-item label="页数上限"><r-input-number v-model="form.page_limit" :min="1" :max="10000" /><span class="config-hint">全量采集也遵守此上限；旧配置 0 表示不限页数。</span></r-form-item>
          <r-form-item label="请求超时"><r-input-number v-model="form.timeout_sec" :min="1" :max="60" /><span class="config-hint">秒</span></r-form-item>
          <r-form-item label="失败重试"><r-input-number v-model="form.retry_count" :min="0" :max="3" /></r-form-item>
          <r-form-item label="请求间隔"><r-input-number v-model="form.interval_ms" :min="0" :max="10000" /><span class="config-hint">毫秒</span></r-form-item>
          <r-form-item label="请求头"><r-input v-model="headersText" type="textarea" :rows="3" placeholder='{"Authorization":"Bearer ..."}' /></r-form-item>
          <r-form-item label="固定参数"><r-input v-model="paramsText" type="textarea" :rows="3" placeholder='{"limit":"50"}' /></r-form-item>
          <r-form-item label="采集规则">
            <r-input v-model="ruleText" type="textarea" :rows="12" />
            <p class="config-hint">支持 GET / POST、body、query 和 mapping。query 支持 {page}、{hours}、{action}、{type_id}、{keyword}、{ids}；mapping 支持 data.items、images.0.url 等路径。未配置的参数不会自动添加。</p>
          </r-form-item>
          <r-collapse><r-collapse-item title="分类绑定与清洗规则" name="advanced">
            <r-form-item label="分类绑定"><r-input v-model="categoriesText" type="textarea" :rows="4" /></r-form-item>
            <r-form-item label="过滤与清洗"><r-input v-model="filterText" type="textarea" :rows="6" /></r-form-item>
          </r-collapse-item></r-collapse>
        </template>

        <r-form-item label="启用状态">
          <r-switch v-model="form.active" />
          <p v-if="form.type === 'webhook'" class="config-hint">关闭后推送方会收到 403「采集源已关闭」。</p>
        </r-form-item>
      </r-form>
      <template #footer>
        <r-button @click="dialogVisible = false">取消</r-button>
        <r-button v-if="form.type !== 'webhook'" type="info" :loading="testing" @click="testCurrentForm">连通性测试</r-button>
        <r-button type="primary" :loading="submitting" @click="submitForm">保存节点配置</r-button>
      </template>
    </r-dialog>

    <!-- 连通性测试结果弹窗 -->
    <r-dialog v-model="testResultVisible" title="采集点连通性测试结果" width="550px">
      <div v-loading="testing" class="test-result-box">
        <r-result
          :icon="testSuccess ? 'success' : 'error'"
          :title="testSuccess ? '连接探测成功' : '探测失败'"
          :sub-title="testMsg"
        >
          <template #extra v-if="testSuccess">
            <div class="result-details">
              <div class="detail-item">
                <span class="label">识别到分类数：</span>
                <r-tag type="success">{{ testData.classes_total || 0 }} 个</r-tag>
              </div>
              <div class="detail-item" v-if="testData.samples && testData.samples.length">
                <span class="label">抓取样本片名：</span>
                <div class="sample-tags">
                  <r-tag
                    v-for="(name, idx) in testData.samples"
                    :key="idx"
                    size="small"
                    type="info"
                  >
                    {{ name }}
                  </r-tag>
                </div>
              </div>
            </div>
          </template>
        </r-result>
      </div>
    </r-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import {
  getSources,
  getCollectionTemplates,
  saveSource,
  deleteSource,
  testSource,
  triggerCollect,
  triggerCollectAll
} from '@/api/admin'
import type { SourceConfig, CollectionTemplate } from '@/types'
import { notify, confirmAction } from '@/components/radix/feedback'
import type { FormInstance, FormRules }  from '@/components/radix/types'
import { Plus, Refresh, ArrowDown, RefreshRight } from '@/components/radix/icons'

const templates = ref<CollectionTemplate[]>([])
const templateID = ref('')
const ruleText = ref('{}'), headersText = ref('{}'), paramsText = ref('{}'), filterText = ref('{}'), categoriesText = ref('[]')
const stringify = (value: unknown) => JSON.stringify(value, null, 2)
function applyTemplate(id: string) {
  const template = templates.value.find(t => t.id === id)
  if (!template) return
  ruleText.value = stringify(template.rule)
  form.type = 'rule'
}
function mapJSON(value: string, label: string) {
  const data = JSON.parse(value)
  if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error(label + ' 必须是 JSON 对象')
  return data
}
const webhookSecret = ref('')
const webhookExpiresAt = ref('')
const webhookSecretVisible = ref(false)
function isWebhookRow(row: any) {
  return row?.type === 'webhook' || String(row?.api || '').startsWith('webhook://')
}
function onProtocolChange(type: string) {
  if (type === 'webhook') {
    if (!form.api || !String(form.api).startsWith('http')) form.api = 'webhook://collector'
    form.page_limit = form.page_limit || 1
    form.timeout_sec = form.timeout_sec || 15
  }
}
function generateWebhookSecret() {
  const bytes = new Uint8Array(32)
  crypto.getRandomValues(bytes)
  webhookSecret.value = Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('')
  webhookSecretVisible.value = true
}
async function copyWebhookSecret() {
  const secret = webhookSecret.value.trim()
  if (!secret) {
    notify('还没有可复制的密钥', 'warning')
    return
  }
  try {
    await navigator.clipboard.writeText(secret)
    notify('Webhook 密钥已复制到剪贴板', 'success')
  } catch {
    // fallback for non-secure contexts / older browsers
    const ta = document.createElement('textarea')
    ta.value = secret
    ta.style.position = 'fixed'
    ta.style.left = '-9999px'
    document.body.appendChild(ta)
    ta.select()
    try {
      document.execCommand('copy')
      notify('Webhook 密钥已复制到剪贴板', 'success')
    } catch {
      notify('复制失败，请手动选中密钥后复制', 'error')
    } finally {
      document.body.removeChild(ta)
    }
  }
}
function payload(): Partial<SourceConfig> {
  if (form.type === 'webhook') {
    const params: Record<string, string> = {}
    const secret = webhookSecret.value.trim()
    if (secret) params.webhook_secret = secret
    const exp = webhookExpiresAt.value.trim()
    if (exp) params.webhook_secret_expires_at = exp
    return {
      ...form,
      id: form.id,
      name: form.name,
      api: form.api || 'webhook://collector',
      type: 'webhook',
      headers: {},
      custom_params: params,
      category_mappings: [],
      filter: {},
      enabled: form.active,
      active: form.active,
      page_limit: form.page_limit || 1,
      timeout_sec: form.timeout_sec || 15,
      collect_hours: 0
    }
  }
  const headers = mapJSON(headersText.value, '请求头'), params = mapJSON(paramsText.value, '固定参数')
  if ([...Object.values(headers), ...Object.values(params)].some(v => typeof v !== 'string')) throw new Error('请求头和固定参数的值必须为字符串')
  const categories = JSON.parse(categoriesText.value)
  if (!Array.isArray(categories)) throw new Error('分类绑定必须是 JSON 数组')
  const filter = mapJSON(filterText.value, '清洗规则')
  return { ...form, type: 'rule', headers, custom_params: params, category_mappings: categories, filter: { ...filter, collector: mapJSON(ruleText.value, '采集规则') }, enabled: form.active }
}
const loading = ref(false)
const tableData = ref<SourceConfig[]>([])
const dialogVisible = ref(false)
const submitting = ref(false)
const editingId = ref<string | null>(null)
const formRef = ref<FormInstance>()

const testing = ref(false)
const testResultVisible = ref(false)
const testSuccess = ref(false)
const testMsg = ref('')
const testData = ref<any>({})

const form = reactive<Partial<SourceConfig>>({
  id: '',
  name: '',
  api: '',
  type: 'json',
  collect_hours: 24,
  active: true
})

const formRules: FormRules = {
  name: [{ required: true, message: '请输入采集点名称', trigger: 'blur' }],
  api: [{ required: true, message: '请输入有效的API地址', trigger: 'blur' }],
  type: [{ required: true, message: '请选择接口协议类型', trigger: 'change' }]
}

const getTypeTag = (type: string) => {
  switch (type) {
    case 'json':
    case 'video_json':
    case 'standard_json':
    case 'maccms_json':
      return 'primary'
    case 'xml':
    case 'video_xml':
    case 'standard_xml':
    case 'maccms_xml':
      return 'success'
    case 'rss':
    case 'rss_feed':
      return 'warning'
    case 'webhook':
      return 'danger'
    default:
      return 'info'
  }
}

const loadData = async () => {
  loading.value = true
  try {
    const res = await getSources()
    if (res.code === 1 && res.data) {
      tableData.value = res.data.filter(item => item.type !== 'pipeline').map((item: any) => ({
        ...item,
        active: item.active !== undefined ? item.active : item.enabled !== false
      }))
    }
  } finally {
    loading.value = false
  }
}

const openEditDialog = (row?: any) => {
  webhookSecret.value = ''
  webhookExpiresAt.value = ''
  webhookSecretVisible.value = false
  if (row) {
    Object.keys(form).forEach(key => delete (form as any)[key])
    Object.assign(form, JSON.parse(JSON.stringify(row)))
    editingId.value = row.id
    form.id = row.id
    form.name = row.name
    form.api = row.api
    form.type = isWebhookRow(row) ? 'webhook' : 'rule'
    form.collect_hours = row.collect_hours ?? 24
    form.active = row.active !== undefined ? row.active : row.enabled !== false
    if (form.type === 'webhook') {
      const p = row.custom_params || {}
      webhookSecret.value = p.webhook_secret || ''
      webhookExpiresAt.value = p.webhook_secret_expires_at || ''
    }
  } else {
    Object.keys(form).forEach(key => delete (form as any)[key])
    editingId.value = null
    form.id = 'src_' + Date.now()
    form.name = ''
    form.api = ''
    form.type = 'rule'
    form.page_limit = 100
    form.timeout_sec = 15
    form.retry_count = 0
    form.interval_ms = 300
    form.collect_hours = 24
    form.active = true
  }
  templateID.value = ''
  headersText.value = stringify(row?.headers || {})
  paramsText.value = stringify(row?.custom_params || {})
  categoriesText.value = stringify(row?.category_mappings || [])
  const { collector, headers, custom_params, custom_mapping, ...cleaning } = row?.filter || {}
  filterText.value = stringify(cleaning)
  const template = templates.value.find(t => t.aliases.includes(row?.type))
  const rule = collector || (template ? { ...template.rule, ...(row?.type === 'custom_json' || row?.type === 'custom' ? { mapping: row.custom_mapping || template.rule.mapping } : {}) } : undefined)
  ruleText.value = stringify(rule || {})
  if (template) templateID.value = template.id
  dialogVisible.value = true
}

const handleStatusChange = async (row: any) => {
  try {
    await saveSource({
      ...row,
      active: row.active,
      enabled: row.active
    } as any)
    notify(`节点 [${row.name}] 状态已更新`, 'success')
  } catch (e) {
    row.active = !row.active
  }
}

const submitForm = async () => {
  if (!formRef.value) return
  await formRef.value.validate(async (valid) => {
    if (!valid) return
    submitting.value = true
    try {
      await saveSource(payload())
      notify('节点配置保存成功，关联视频节点名称已同步更新', 'success')
      dialogVisible.value = false
      loadData()
    } catch (err) {
      if (err instanceof SyntaxError) notify('JSON 格式错误，请检查规则、请求头和参数', 'error')
      else if (err instanceof Error && !('response' in err)) notify(err.message, 'error')
    } finally {
      submitting.value = false
    }
  })
}

const handleCollect = async (row: SourceConfig, hours: number) => {
  const modeText = hours === 0 ? '全量历史' : `近 ${hours} 小时增量`
  try {
    const res = await triggerCollect(row.id, hours)
    if (res.code === 1) {
      notify(`已为 [${row.name}] 启动 ${modeText} 采集任务`, 'success')
    }
  } catch (e) {}
}

const handleCollectAll = async (hours: number) => {
  const modeText = hours === 0 ? '全量历史' : '近24小时增量'
  confirmAction(
    `确定要触发所有已启用采集点的 ${modeText} 并发采集任务吗？`,
    '采集调度确认',
    {
      confirmButtonText: '立即启动',
      cancelButtonText: '取消',
      type: 'warning'
    }
  ).then(async () => {
    const res = await triggerCollectAll(hours)
    if (res.code === 1) {
      notify(res.msg || '全网并发采集任务已启动', 'success')
    }
  }).catch(() => {})
}

const handleTest = async (row: SourceConfig) => {
  testSuccess.value = false
  testMsg.value = '正在探测中...'
  testData.value = {}
  testResultVisible.value = true
  testing.value = true
  try {
    const res = await testSource(row)
    if (res.code === 1) {
      testSuccess.value = true
      testMsg.value = res.msg || '接口响应正常，解析顺利'
      testData.value = res
    } else {
      testSuccess.value = false
      testMsg.value = res.error || '探测失败'
    }
  } catch (err: any) {
    testSuccess.value = false
    testMsg.value = err.message || '连接失败'
  } finally {
    testing.value = false
  }
}

const testCurrentForm = async () => {
  if (!form.api) {
    notify('请先填写 API 接口地址', 'warning')
    return
  }
  try { await handleTest(payload() as SourceConfig) } catch (err) { notify(err instanceof Error ? err.message : '配置格式错误', 'error') }
}

const handleDelete = (row: SourceConfig) => {
  confirmAction(`确定要删除采集点 [${row.name}] 吗？删除后将不再同步此源。`, '删除确认', {
    confirmButtonText: '确定删除',
    cancelButtonText: '取消',
    type: 'error'
  }).then(async () => {
    await deleteSource(row.id)
    notify('已删除采集点', 'success')
    loadData()
  }).catch(() => {})
}

onMounted(async () => {
  await Promise.all([loadData(), getCollectionTemplates().then(res => { templates.value = res.data || [] })])
})
</script>

<style scoped lang="scss">
.config-hint { margin: 6px 10px; color: var(--text-secondary); font-size: 12px; line-height: 1.6; }
.webhook-secret-row { display: flex; gap: 8px; width: 100%; align-items: center; flex-wrap: wrap; }
.webhook-secret-row .webhook-secret-input { flex: 1; min-width: 220px; }
.webhook-secret-row .webhook-secret-input :deep(.r-input),
.webhook-secret-row .webhook-secret-input :deep(input) { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size: 12px; }
.font-mono { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size: 12px; }
.sources-page {
  .table-card {
    border-radius: 12px;
    border: 1px solid var(--border-color);

    .table-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 12px;
      flex-wrap: wrap;
      gap: 8px;

      .header-left {
        display: flex;
        flex-direction: column;
        gap: 4px;

        .page-title {
          font-size: 13px;
          font-weight: 700;
          letter-spacing: -0.02em;
          color: var(--text-primary);
        }
        .sub-desc {
          font-size: 10px;
          color: var(--text-secondary);
        }
      }

      .header-right {
        display: flex;
        gap: 10px;
      }
    }
  }

  .test-result-box {
    .result-details {
      margin-top: 12px;
      text-align: left;
      font-size: 13px;
      display: flex;
      flex-direction: column;
      gap: 10px;

      .detail-item {
        display: flex;
        align-items: center;
        gap: 8px;

        .label {
          font-weight: 600;
          color: var(--text-regular);
        }

        .sample-tags {
          display: flex;
          flex-wrap: wrap;
          gap: 6px;
        }
      }
    }
  }
}
</style>
