<template>
  <div class="webhooks-page">
    <r-card shadow="never" class="table-card">
      <div class="table-header">
        <div class="header-left">
          <span class="page-title">Webhook 回调采集</span>
          <span class="sub-desc">外部系统实时推送影片数据：HMAC-SHA256 验签、时间戳防重放、原始报文留痕、密钥加密托管</span>
        </div>
        <div class="header-right">
          <r-button type="primary" @click="openCreate">
            <r-icon><Plus /></r-icon>新建回调端点
          </r-button>
          <r-button @click="loadList" :loading="loading">
            <r-icon><RefreshRight /></r-icon>刷新
          </r-button>
        </div>
      </div>

      <r-table :data="list" v-loading="loading" border stripe style="width: 100%">
        <r-table-column prop="name" label="端点名称" min-width="150">
          <template #default="{ row }">
            <span class="font-bold">{{ row.name }}</span>
            <div class="id-hint">{{ row.id }}</div>
          </template>
        </r-table-column>
        <r-table-column prop="secret_hint" label="密钥" width="130" align="center">
          <template #default="{ row }">
            <r-tag type="info" effect="plain">{{ row.secret_hint || '****' }}</r-tag>
          </template>
        </r-table-column>
        <r-table-column prop="target" label="入库目标" width="100" align="center">
          <template #default="{ row }">
            <r-tag :type="row.target === 'video' ? 'success' : 'warning'">
              {{ row.target === 'video' ? '视频库' : '采集记录' }}
            </r-tag>
          </template>
        </r-table-column>
        <r-table-column prop="duplicate" label="重复策略" width="100" align="center">
          <template #default="{ row }">
            {{ row.duplicate === 'skip' ? '跳过' : '覆盖' }}
          </template>
        </r-table-column>
        <r-table-column prop="events" label="事件白名单" min-width="140">
          <template #default="{ row }">
            <span v-if="!row.events?.length" class="text-gray-400">不限制</span>
            <r-tag v-else v-for="e in row.events" :key="e" size="small" effect="plain" class="event-tag">{{ e }}</r-tag>
          </template>
        </r-table-column>
        <r-table-column prop="tolerance_sec" label="时间戳窗口" width="110" align="center">
          <template #default="{ row }">
            {{ row.tolerance_sec > 0 ? row.tolerance_sec + ' 秒' : '不校验' }}
          </template>
        </r-table-column>
        <r-table-column prop="enabled" label="状态" width="90" align="center">
          <template #default="{ row }">
            <r-tag :type="row.enabled ? 'success' : 'danger'">
              {{ row.enabled ? '启用' : '停用' }}
            </r-tag>
          </template>
        </r-table-column>
        <r-table-column label="操作" width="220" align="center" fixed="right">
          <template #default="{ row }">
            <r-button size="small" type="primary" plain @click="openDeliveries(row)">投递日志</r-button>
            <r-button size="small" type="warning" plain @click="openRotate(row)">轮换密钥</r-button>
          </template>
        </r-table-column>
      </r-table>
    </r-card>

    <!-- 创建端点 -->
    <r-dialog v-model="createVisible" title="新建 Webhook 回调端点" width="560px">
      <r-form :model="createForm" label-width="110px">
        <r-form-item label="端点名称" required>
          <r-input v-model="createForm.name" maxlength="64" show-word-limit placeholder="如：苹果CMS 内容源回调" />
        </r-form-item>
        <r-form-item label="入库目标">
          <r-radio-group v-model="createForm.target">
            <r-radio value="video">视频库（直接可播放）</r-radio>
            <r-radio value="record">采集记录（需人工校正）</r-radio>
          </r-radio-group>
        </r-form-item>
        <r-form-item label="重复策略">
          <r-radio-group v-model="createForm.duplicate">
            <r-radio value="update">覆盖更新</r-radio>
            <r-radio value="skip">已存在则跳过</r-radio>
          </r-radio-group>
        </r-form-item>
        <r-form-item label="事件白名单">
          <r-input v-model="eventsInput" placeholder="多条用逗号分隔，留空表示不限制，如：video.upsert,video.update" />
        </r-form-item>
        <r-form-item label="来源标识">
          <r-input v-model="createForm.source_id" placeholder="留空默认为 webhook:<id>，用于视频库来源归属" />
        </r-form-item>
        <r-form-item label="时间戳窗口">
          <r-input-number v-model="createForm.tolerance_sec" :min="0" :max="86400" :step="60" />
          <span class="form-hint">秒；&gt;0 时强制校验 X-Webhook-Timestamp 防重放，0 表示不校验</span>
        </r-form-item>
      </r-form>
      <template #footer>
        <r-button @click="createVisible = false">取消</r-button>
        <r-button type="primary" :loading="saving" @click="submitCreate">创建并生成密钥</r-button>
      </template>
    </r-dialog>

    <!-- 密钥仅展示一次 -->
    <r-dialog v-model="secretVisible" :title="secretTitle" width="520px">
      <r-alert type="warning" :closable="false" show-icon class="secret-alert">
        明文密钥仅本次显示，刷新或关闭后无法再次查看；请立即复制并妥善保管。
      </r-alert>
      <div class="secret-box">
        <span class="secret-text">{{ generatedSecret }}</span>
        <r-button size="small" @click="copySecret">复制</r-button>
      </div>
      <div class="secret-usage">
        <p>采集入口：<code>{{ currentIngestUrl }}</code></p>
        <p>签名示例：<code>X-Webhook-Signature: sha256={{ '{' }}HMAC_SHA256(secret, 原始请求体){{ '}' }}</code></p>
      </div>
      <template #footer>
        <r-button type="primary" @click="secretVisible = false">我已保存</r-button>
      </template>
    </r-dialog>

    <!-- 投递日志 -->
    <r-dialog v-model="deliveriesVisible" :title="`投递日志 · ${current?.name || ''}`" width="860px">
      <div class="deliveries-toolbar">
        <r-select v-model="deliveryStatus" placeholder="状态筛选" style="width: 140px" @change="loadDeliveries">
          <r-option label="全部状态" value="" />
          <r-option label="已入库" value="accepted" />
          <r-option label="验签拒绝" value="rejected" />
          <r-option label="事件忽略" value="ignored" />
          <r-option label="处理异常" value="error" />
        </r-select>
        <r-input v-model="deliveryKeyword" placeholder="按事件 / 错误 / 报文内容检索" style="width: 240px" clearable @clear="loadDeliveries" @keyup.enter="loadDeliveries" />
        <r-button @click="loadDeliveries" :loading="deliveryLoading">查询</r-button>
        <r-button type="danger" plain @click="runCleanup">清理日志</r-button>
      </div>

      <div class="stats-row" v-if="stats">
        <r-tag>总计 {{ stats.total }}</r-tag>
        <r-tag type="success">入库 {{ stats.accepted }}</r-tag>
        <r-tag type="danger">拒绝 {{ stats.rejected }}</r-tag>
        <r-tag type="info">忽略 {{ stats.total - stats.accepted - stats.rejected - stats.error }}</r-tag>
        <r-tag type="warning">异常 {{ stats.error }}</r-tag>
        <r-tag type="info" effect="plain">累计入库 {{ stats.imported_total }} 条</r-tag>
      </div>

      <r-table :data="deliveries" v-loading="deliveryLoading" border stripe max-height="420" style="width: 100%">
        <r-table-column prop="id" label="ID" width="64" align="center" />
        <r-table-column prop="status" label="结果" width="90" align="center">
          <template #default="{ row }">
            <r-tag :type="statusTag(row.status)">{{ statusLabel(row.status) }}</r-tag>
          </template>
        </r-table-column>
        <r-table-column prop="event" label="事件" width="130" show-overflow-tooltip />
        <r-table-column prop="imported" label="入库" width="60" align="center" />
        <r-table-column prop="remote_ip" label="来源 IP" width="120" align="center" />
        <r-table-column prop="error_message" label="说明" min-width="150" show-overflow-tooltip />
        <r-table-column prop="created_at" label="时间" width="160" align="center">
          <template #default="{ row }">
            <span class="date-text">{{ formatDate(row.created_at) }}</span>
          </template>
        </r-table-column>
        <r-table-column label="原始报文" width="90" align="center">
          <template #default="{ row }">
            <r-button size="small" link type="primary" @click="showRawBody(row)">查看</r-button>
          </template>
        </r-table-column>
      </r-table>

      <div class="wb-pagination-bar">
        <r-pagination
          v-model:current-page="deliveryPage"
          v-model:page-size="deliveryPageSize"
          :page-sizes="[10, 20, 50, 100]"
          :total="deliveryTotal"
          @current-change="loadDeliveries"
          @size-change="loadDeliveries"
        />
      </div>
    </r-dialog>

    <!-- 原始报文查看 -->
    <r-dialog v-model="rawVisible" title="原始请求报文" width="640px">
      <pre class="raw-body-box">{{ currentRawBody || '（空）' }}</pre>
      <template #footer>
        <r-button @click="copyRawBody">复制报文</r-button>
        <r-button type="primary" @click="rawVisible = false">关闭</r-button>
      </template>
    </r-dialog>
  </div>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import {
  listWebhooks,
  createWebhook,
  rotateWebhookSecret,
  listDeliveries,
  getWebhookStats,
  cleanupDeliveries,
  ingestUrl,
  type Webhook,
  type WebhookDelivery,
  type WebhookStats,
} from '@/api/webhook'
import { notify, confirmAction } from '@/components/radix/feedback'
import { Plus, RefreshRight } from '@/components/radix/icons'

const loading = ref(false)
const saving = ref(false)
const list = ref<Webhook[]>([])

const loadList = async () => {
  loading.value = true
  try {
    const res = await listWebhooks()
    if (res.code === 1) list.value = res.data || []
  } finally {
    loading.value = false
  }
}

// ---------- 创建 ----------
const createVisible = ref(false)
const eventsInput = ref('')
const createForm = reactive({
  name: '',
  target: 'video' as 'video' | 'record',
  duplicate: 'update' as 'update' | 'skip',
  source_id: '',
  tolerance_sec: 300,
})

const openCreate = () => {
  createForm.name = ''
  createForm.target = 'video'
  createForm.duplicate = 'update'
  createForm.source_id = ''
  createForm.tolerance_sec = 300
  eventsInput.value = ''
  createVisible.value = true
}

const parseEvents = () =>
  eventsInput.value
    .split(/[,，]/)
    .map((s) => s.trim())
    .filter(Boolean)

const submitCreate = async () => {
  if (!createForm.name.trim()) {
    notify('请填写端点名称', 'warning')
    return
  }
  saving.value = true
  try {
    const res = await createWebhook({
      name: createForm.name.trim(),
      target: createForm.target,
      duplicate: createForm.duplicate,
      events: parseEvents(),
      source_id: createForm.source_id.trim() || undefined,
      tolerance_sec: createForm.tolerance_sec,
    })
    if (res.code === 1 && res.data) {
      createVisible.value = false
      currentIngestUrl.value = ingestUrl(res.data.webhook.id)
      generatedSecret.value = res.data.secret
      secretTitle.value = '端点已创建 · 密钥仅本次显示'
      secretVisible.value = true
      loadList()
    }
  } finally {
    saving.value = false
  }
}

// ---------- 密钥展示 / 轮换 ----------
const secretVisible = ref(false)
const secretTitle = ref('密钥')
const generatedSecret = ref('')
const currentIngestUrl = ref('')

const copySecret = async () => {
  try {
    await navigator.clipboard.writeText(generatedSecret.value)
    notify('密钥已复制到剪贴板', 'success')
  } catch {
    notify('复制失败，请手动选择复制', 'warning')
  }
}

const openRotate = (row: Webhook) => {
  confirmAction(
    `轮换后「${row.name}」的旧密钥立即失效，使用旧密钥的推送方将验签失败。新密钥同样只显示一次。`,
    '轮换密钥确认',
    { confirmButtonText: '生成新密钥', cancelButtonText: '取消', type: 'warning' }
  )
    .then(async () => {
      const res = await rotateWebhookSecret(row.id)
      if (res.code === 1 && res.data) {
        currentIngestUrl.value = ingestUrl(row.id)
        generatedSecret.value = res.data.secret
        secretTitle.value = `密钥已轮换 · ${row.name}`
        secretVisible.value = true
        loadList()
      }
    })
    .catch(() => {})
}

// ---------- 投递日志 ----------
const deliveriesVisible = ref(false)
const current = ref<Webhook | null>(null)
const deliveries = ref<WebhookDelivery[]>([])
const deliveryLoading = ref(false)
const deliveryStatus = ref('')
const deliveryKeyword = ref('')
const deliveryPage = ref(1)
const deliveryPageSize = ref(20)
const deliveryTotal = ref(0)
const stats = ref<WebhookStats | null>(null)

const openDeliveries = (row: Webhook) => {
  current.value = row
  deliveryStatus.value = ''
  deliveryKeyword.value = ''
  deliveryPage.value = 1
  deliveriesVisible.value = true
  loadDeliveries()
  getWebhookStats(row.id).then((res) => {
    if (res.code === 1 && res.data) stats.value = res.data
  })
}

const loadDeliveries = async () => {
  if (!current.value) return
  deliveryLoading.value = true
  try {
    const res = await listDeliveries({
      id: current.value.id,
      status: deliveryStatus.value || undefined,
      keyword: deliveryKeyword.value || undefined,
      page: deliveryPage.value,
      page_size: deliveryPageSize.value,
    })
    if (res.code === 1) {
      deliveries.value = res.data || []
      deliveryTotal.value = res.total || 0
    }
  } finally {
    deliveryLoading.value = false
  }
}

const runCleanup = () => {
  if (!current.value) return
  confirmAction('清理后投递日志不可恢复（端点与密钥不受影响）。', '清理投递日志', {
    confirmButtonText: '清理',
    type: 'warning',
  })
    .then(async () => {
      const res = await cleanupDeliveries({ id: current.value?.id, days: 0 })
      if (res.code === 1) {
        notify(`已清理 ${res.data?.deleted ?? 0} 条日志`, 'success')
        loadDeliveries()
        if (current.value) {
          const s = await getWebhookStats(current.value.id)
          if (s.code === 1 && s.data) stats.value = s.data
        }
      }
    })
    .catch(() => {})
}

// ---------- 原始报文 ----------
const rawVisible = ref(false)
const currentRawBody = ref('')

const showRawBody = (row: WebhookDelivery) => {
  try {
    currentRawBody.value = JSON.stringify(JSON.parse(row.raw_body), null, 2)
  } catch {
    currentRawBody.value = row.raw_body
  }
  rawVisible.value = true
}

const copyRawBody = async () => {
  try {
    await navigator.clipboard.writeText(currentRawBody.value)
    notify('报文已复制', 'success')
  } catch {
    notify('复制失败，请手动选择复制', 'warning')
  }
}

// ---------- 展示辅助 ----------
const formatDate = (val?: string) => (val ? val.replace('T', ' ').substring(0, 19) : '-')

const statusTag = (s: string) =>
  ({ accepted: 'success', rejected: 'danger', ignored: 'info', error: 'warning', duplicate: 'info' }[s] || 'info')

const statusLabel = (s: string) =>
  ({ accepted: '已入库', rejected: '验签拒绝', ignored: '事件忽略', error: '处理异常', duplicate: '重复' }[s] || s)

onMounted(loadList)
</script>

<style scoped>
.webhooks-page {
  .table-card {
    border-radius: 12px;
    border: 1px solid var(--border-color);

    .table-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 12px;
      flex-wrap: wrap;
      gap: 12px;

      .header-left {
        display: flex;
        flex-direction: column;
        gap: 3px;

        .page-title {
          font-size: 13px;
          font-weight: 700;
          color: var(--text-primary);
        }

        .sub-desc {
          font-size: 10px;
          color: var(--text-secondary);
        }
      }

      .header-right {
        display: flex;
        gap: 8px;
      }
    }
  }

  .id-hint {
    font-size: 10px;
    color: var(--text-secondary);
  }

  .event-tag {
    margin: 0 4px 2px 0;
  }

  .form-hint {
    margin-left: 10px;
    font-size: 10px;
    color: var(--text-secondary);
  }

  .secret-alert {
    margin-bottom: 12px;
  }

  .secret-box {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 10px 12px;
    border-radius: 8px;
    border: 1px dashed var(--border-color);
    background: var(--fill-color-light, rgba(0, 0, 0, 0.02));

    .secret-text {
      font-family: monospace;
      font-size: 13px;
      word-break: break-all;
    }
  }

  .secret-usage {
    margin-top: 12px;
    font-size: 11px;
    color: var(--text-secondary);

    code {
      font-size: 10px;
      word-break: break-all;
    }
  }

  .deliveries-toolbar {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
    margin-bottom: 10px;
  }

  .stats-row {
    display: flex;
    gap: 6px;
    flex-wrap: wrap;
    margin-bottom: 10px;
  }

  .raw-body-box {
    max-height: 420px;
    overflow: auto;
    padding: 12px;
    border-radius: 8px;
    background: rgba(0, 0, 0, 0.04);
    font-size: 11px;
    line-height: 1.6;
  }

  .date-text {
    font-size: 10px;
    color: var(--text-secondary);
  }
}
</style>
