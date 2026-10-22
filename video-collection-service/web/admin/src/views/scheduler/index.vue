<template>
  <div class="scheduler-page">
    <r-row :gutter="16">
      <!-- 状态概览卡片 -->
      <r-col :xs="24" :md="10">
        <r-card shadow="never" class="status-card">
          <template #header>
            <div class="card-header">
              <span class="card-title">Bllii-Familiar · 使魔调度状态</span>
              <r-tag :type="statusData.running ? 'danger' : 'success'">
                {{ statusData.running ? '使魔正在采集运行中' : '使魔空闲待命' }}
              </r-tag>
            </div>
          </template>

          <div class="status-content" v-loading="loading">
            <div class="status-item">
              <span class="label">使魔自动采集：</span>
              <r-tag :type="statusData.enabled ? 'success' : 'info'">
                {{ statusData.enabled ? '已开启' : '已暂停' }}
              </r-tag>
            </div>
            <div class="status-item">
              <span class="label">执行周期频率：</span>
              <span class="val font-bold">每 {{ statusData.interval_hours || 2 }} 小时自动执行</span>
            </div>
            <div class="status-item">
              <span class="label">下次调度时间：</span>
              <span class="val">{{ formatDate(statusData.next_run_time) }}</span>
            </div>
            <div class="status-item">
              <span class="label">上次完成时间：</span>
              <span class="val">{{ formatDate(statusData.last_run_time) }}</span>
            </div>

            <r-divider />

            <div class="quick-manual">
              <span class="manual-title">即时手动唤醒：</span>
              <div class="btns">
                <r-button type="primary" :loading="triggering" @click="handleManualTrigger(24)">
                  增量唤醒采集 (24h)
                </r-button>
                <r-button type="warning" plain :loading="triggering" @click="handleManualTrigger(0)">
                  全量唤醒采集 (0h)
                </r-button>
              </div>
            </div>
          </div>
        </r-card>
      </r-col>

      <!-- 调度配置表单 -->
      <r-col :xs="24" :md="14">
        <r-card shadow="never" class="config-card">
          <template #header>
            <span class="card-title">使魔自动巡回计划配置</span>
          </template>

          <r-form :model="form" label-width="140px" class="config-form">
            <r-form-item label="开启使魔定时巡回">
              <r-switch
                v-model="form.enabled"
                active-text="启用后台定时巡检"
                inactive-text="关闭"
              />
            </r-form-item>

            <r-form-item label="巡检执行周期">
              <r-input-number
                v-model="form.interval_hours"
                :min="1"
                :max="72"
                :step="1"
                style="width: 120px;"
              />
              <span class="unit-text">小时 / 次（推荐 2 小时）</span>
            </r-form-item>

            <r-form-item label="增量策略模式">
              <r-radio-group v-model="collectMode">
                <r-radio value="24">智能增量 (仅同步近24小时有更新的影视)</r-radio>
              </r-radio-group>
            </r-form-item>

            <r-form-item>
              <r-button type="primary" :loading="saving" @click="saveConfig">
                保存定时配置
              </r-button>
              <r-button @click="loadStatus">重置表单</r-button>
            </r-form-item>
          </r-form>
        </r-card>
      </r-col>
    </r-row>

    <!-- 独立区块：调度运行机制说明 -->
    <r-card shadow="never" class="mechanism-card">
      <template #header>
        <div class="card-header">
          <span class="card-title">调度运行机制说明</span>
          <span class="header-aux">后台常驻轮询 · 并发采集 · 自动清洗入库</span>
        </div>
      </template>

      <ul class="mechanism-list">
        <li class="mechanism-item">
          <span class="idx">01</span>
          <div class="copy">
            <strong>高精度定时轮询</strong>
            <p>系统在后台以轻量级 Goroutine 持续运行高精度定时轮询器，不依赖外部 Cron 服务。</p>
          </div>
        </li>
        <li class="mechanism-item">
          <span class="idx">02</span>
          <div class="copy">
            <strong>并发拉取增量数据</strong>
            <p>定时任务触发时，自动遍历所有处于「启用」状态的采集源，并发拉取最新增量数据。</p>
          </div>
        </li>
        <li class="mechanism-item">
          <span class="idx">03</span>
          <div class="copy">
            <strong>清洗合并后入库</strong>
            <p>采集过程中自动完成去重清洗、智能线路合并、剧集更新比对，并写入任务进程记录。</p>
          </div>
        </li>
      </ul>
    </r-card>

    <!-- 下半区：采集任务进程记录与实时日志控制台 -->
    <r-card shadow="never" class="runs-card" style="margin-top: 16px;">
      <template #header>
        <div class="runs-card-header">
          <div class="runs-title-group">
            <span class="card-title">采集进程记录与采集日志中心</span>
            <span v-if="runningCount > 0" class="running-indicator">
              <r-icon class="rotating-icon" :size="13"><Refresh /></r-icon>
              {{ runningCount }} 个采集任务正在进行中
            </span>
          </div>
          <div class="header-actions">
            <r-button size="small" :loading="tasksLoading" @click="refreshAll">
              <r-icon><Refresh /></r-icon> 刷新
            </r-button>
          </div>
        </div>
      </template>

      <r-tabs v-model="activeTab" class="runs-tabs">
        <!-- Tab 1: 任务进程记录与历史批次 -->
        <r-tab-pane label="采集任务进程与历史批次" name="tasks">
          <!-- 核心统计概览 -->
          <div class="metrics-row">
            <div class="metric-pill">
              <span class="pill-label">总执行批次</span>
              <strong class="pill-val">{{ tasksTotal }}</strong>
            </div>
            <div class="metric-pill running">
              <span class="pill-label">进行中任务</span>
              <strong class="pill-val">{{ runningCount }}</strong>
            </div>
            <div class="metric-pill success">
              <span class="pill-label">累计抓取条数</span>
              <strong class="pill-val">{{ totalFetchedSum }}</strong>
            </div>
            <div class="metric-pill highlight">
              <span class="pill-label">累计有效入库</span>
              <strong class="pill-val">{{ totalSavedSum }}</strong>
            </div>
          </div>

          <!-- 筛选工具栏 -->
          <div class="tasks-toolbar">
            <div class="filter-group">
              <r-select v-model="taskStatusFilter" placeholder="运行状态 (全部)" style="width: 140px;" clearable @change="loadTasks">
                <r-option label="全部状态" value="" />
                <r-option label="⏳ 正在采集中" value="running" />
                <r-option label="✅ 采集成功" value="success" />
                <r-option label="❌ 失败/中断" value="failed" />
              </r-select>
              <r-select v-model="taskTriggerFilter" placeholder="触发方式 (全部)" style="width: 140px;" clearable @change="loadTasks">
                <r-option label="全部方式" value="" />
                <r-option label="手动唤醒" value="manual" />
                <r-option label="定时巡回" value="cron" />
              </r-select>
            </div>
            <div class="toolbar-right">
              <span class="auto-refresh-label">
                <r-switch v-model="autoRefresh" size="small" /> 自动轮询 (5s)
              </span>
            </div>
          </div>

          <!-- 任务列表表格 -->
          <r-table :data="tasks" v-loading="tasksLoading" border style="width: 100%; margin-top: 12px;">
            <r-table-column label="任务批次" width="100" align="center">
              <template #default="{ row }">
                <span class="task-id-badge">#{{ row.id }}</span>
              </template>
            </r-table-column>
            <r-table-column label="采集来源 / 使魔" min-width="180">
              <template #default="{ row }">
                <div class="source-cell">
                  <strong>{{ row.source_name || row.source_id }}</strong>
                  <span class="source-id-sub">{{ row.source_id }}</span>
                </div>
              </template>
            </r-table-column>
            <r-table-column label="触发类型" width="110" align="center">
              <template #default="{ row }">
                <r-tag v-if="row.trigger_type === 'cron'" type="info" size="small">定时巡回</r-tag>
                <r-tag v-else type="primary" size="small">手动唤醒</r-tag>
              </template>
            </r-table-column>
            <r-table-column label="采集范围" width="110" align="center">
              <template #default="{ row }">
                <r-tag v-if="row.collect_hours === 0" type="warning" size="small">全量采集</r-tag>
                <r-tag v-else size="small">近 {{ row.collect_hours }}h 增量</r-tag>
              </template>
            </r-table-column>
            <r-table-column label="执行状态" width="130" align="center">
              <template #default="{ row }">
                <r-tag v-if="row.status === 'running'" type="warning" size="small" class="running-tag">
                  <r-icon class="rotating-icon" :size="11"><Refresh /></r-icon> 正在采集中...
                </r-tag>
                <r-tag v-else-if="row.status === 'success'" type="success" size="small">
                  <r-icon :size="11"><Check /></r-icon> 采集完成
                </r-tag>
                <r-tag v-else-if="row.status === 'failed'" type="danger" size="small" :title="row.error_message">
                  采集失败
                </r-tag>
                <r-tag v-else type="info" size="small">{{ row.status }}</r-tag>
              </template>
            </r-table-column>
            <r-table-column label="采集统计指标" min-width="210">
              <template #default="{ row }">
                <div class="stats-metric-line">
                  <span>抓取: <strong>{{ row.total_fetched }}</strong></span>
                  <span class="sep">|</span>
                  <span class="success-text">有效入库: <strong>{{ row.total_saved }}</strong></span>
                  <span class="sep">|</span>
                  <span class="mute-text">跳过: {{ row.total_skipped }}</span>
                </div>
              </template>
            </r-table-column>
            <r-table-column label="启动时间" width="165">
              <template #default="{ row }">
                <span class="time-text">{{ formatDate(row.started_at) }}</span>
              </template>
            </r-table-column>
            <r-table-column label="运行时长" width="105" align="center">
              <template #default="{ row }">
                <span class="duration-text">{{ formatDuration(row.duration_ms, row.status === 'running') }}</span>
              </template>
            </r-table-column>
            <r-table-column label="操作" width="120" fixed="right" align="center">
              <template #default="{ row }">
                <r-button type="primary" link size="small" @click="openTaskLogs(row)">
                  查看日志
                </r-button>
              </template>
            </r-table-column>
          </r-table>

          <!-- 任务列表分页 -->
          <div class="pagination-box" v-if="tasksTotal > 0">
            <r-pagination
              v-model:current-page="tasksPage"
              :page-size="20"
              :total="tasksTotal"
              layout="total, prev, pager, next"
              @current-change="loadTasks"
            />
          </div>
        </r-tab-pane>

        <!-- Tab 2: 实时与历史采集日志控制台 -->
        <r-tab-pane label="实时与全量采集日志" name="logs">
          <div class="logs-console-toolbar">
            <div class="toolbar-left">
              <r-select v-model="logLevelFilter" placeholder="日志级别 (全部)" style="width: 130px;" clearable @change="loadLogs">
                <r-option label="全部级别" value="" />
                <r-option label="🔵 INFO (信息)" value="INFO" />
                <r-option label="🟢 SUCCESS (成功)" value="SUCCESS" />
                <r-option label="🟡 WARN (警告)" value="WARN" />
                <r-option label="🔴 ERROR (异常)" value="ERROR" />
              </r-select>
              <r-input
                v-model="logKeyword"
                placeholder="按日志消息关键词搜索..."
                style="width: 240px;"
                clearable
                @keyup.enter="loadLogs"
              />
              <r-button size="small" type="primary" plain @click="loadLogs">
                <r-icon><Search /></r-icon> 检索
              </r-button>
            </div>
            <div class="toolbar-right">
              <r-button size="small" type="danger" plain @click="handleClearLogs">
                <r-icon><Trash2 /></r-icon> 清理15天前历史
              </r-button>
              <r-button size="small" @click="loadLogs">
                <r-icon><Refresh /></r-icon> 刷新日志
              </r-button>
            </div>
          </div>

          <!-- 终端风格日志盒 -->
          <div class="terminal-log-box" v-loading="logsLoading">
            <div v-if="!logs.length" class="empty-logs">
              暂无匹配的采集执行日志
            </div>
            <div v-for="item in logs" :key="item.id" class="log-line">
              <span class="log-time">{{ formatLogTime(item.created_at) }}</span>
              <span :class="['log-level-badge', item.level.toLowerCase()]">
                [{{ item.level }}]
              </span>
              <span v-if="item.task_id" class="log-task-tag">#{{ item.task_id }}</span>
              <span class="log-source">[{{ item.source_name || item.source_id }}]</span>
              <span class="log-msg">{{ item.message }}</span>
            </div>
          </div>

          <!-- 日志分页 -->
          <div class="pagination-box" v-if="logsTotal > 0">
            <r-pagination
              v-model:current-page="logsPage"
              :page-size="50"
              :total="logsTotal"
              layout="total, prev, pager, next"
              @current-change="loadLogs"
            />
          </div>
        </r-tab-pane>
      </r-tabs>
    </r-card>

    <!-- 单任务执行日志详情弹窗 -->
    <r-dialog
      v-model="taskDialogVisible"
      :title="`采集任务详情与完整执行日志 · #${currentTask?.id || ''}`"
      width="min(960px, 95vw)"
    >
      <div v-if="currentTask" class="task-detail-overview">
        <div class="detail-grid">
          <div class="detail-item"><span class="k">使魔节点：</span><strong>{{ currentTask.source_name }} ({{ currentTask.source_id }})</strong></div>
          <div class="detail-item"><span class="k">触发方式：</span><r-tag size="small">{{ currentTask.trigger_type === 'cron' ? '定时调度' : '手动唤醒' }}</r-tag></div>
          <div class="detail-item"><span class="k">运行状态：</span><r-tag :type="currentTask.status === 'success' ? 'success' : currentTask.status === 'running' ? 'warning' : 'danger'" size="small">{{ currentTask.status }}</r-tag></div>
          <div class="detail-item"><span class="k">耗时：</span><span>{{ formatDuration(currentTask.duration_ms, currentTask.status === 'running') }}</span></div>
          <div class="detail-item"><span class="k">启动时间：</span><span>{{ formatDate(currentTask.started_at) }}</span></div>
          <div class="detail-item"><span class="k">结束时间：</span><span>{{ currentTask.ended_at ? formatDate(currentTask.ended_at) : '进行中' }}</span></div>
          <div class="detail-item full"><span class="k">采集指标：</span><span>抓取总数: <strong>{{ currentTask.total_fetched }}</strong> 条 · 有效入库: <strong style="color: var(--brand);">{{ currentTask.total_saved }}</strong> 条 · 过滤跳过: {{ currentTask.total_skipped }} 条</span></div>
          <div v-if="currentTask.error_message" class="detail-item full error"><span class="k">异常信息：</span><span class="err-text">{{ currentTask.error_message }}</span></div>
        </div>
      </div>

      <div class="dialog-logs-terminal">
        <div class="terminal-header">
          <span>任务执行日志流水 (共 {{ taskLogs.length }} 行)</span>
          <r-button size="small" link @click="copyLogsText">复制日志文本</r-button>
        </div>
        <div class="terminal-body">
          <div v-if="!taskLogs.length" class="empty-logs">该任务尚无日志输出</div>
          <div v-for="l in taskLogs" :key="l.id" class="log-line">
            <span class="log-time">{{ formatLogTime(l.created_at) }}</span>
            <span :class="['log-level-badge', l.level.toLowerCase()]">[{{ l.level }}]</span>
            <span class="log-msg">{{ l.message }}</span>
          </div>
        </div>
      </div>

      <template #footer>
        <r-button @click="taskDialogVisible = false">关闭</r-button>
      </template>
    </r-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, computed, onMounted, onBeforeUnmount } from 'vue'
import { getAutoCollectStatus, saveAutoCollectConfig, triggerCollectAll } from '@/api/admin'
import {
  getCollectionTasks,
  getCollectionTaskDetail,
  getCollectionLogs,
  clearCollectionLogs
} from '@/api/collection'
import type { AutoCollectStatus } from '@/types'
import type { CollectionTask, CollectionLog } from '@/api/collection'
import { notify, confirmAction } from '@/components/radix/feedback'
import { Refresh, Check, Search, Trash2 } from '@/components/radix/icons'

const loading = ref(false)
const saving = ref(false)
const triggering = ref(false)
const collectMode = ref('24')

const statusData = ref<AutoCollectStatus>({
  enabled: false,
  interval_hours: 2,
  running: false
})

const form = reactive({
  enabled: false,
  interval_hours: 2
})

const activeTab = ref('tasks')

// 任务列表状态
const tasks = ref<CollectionTask[]>([])
const tasksTotal = ref(0)
const tasksPage = ref(1)
const tasksLoading = ref(false)
const taskStatusFilter = ref('')
const taskTriggerFilter = ref('')
const autoRefresh = ref(true)
let refreshTimer: any = null

const runningCount = computed(() => tasks.value.filter(t => t.status === 'running').length)
const totalFetchedSum = computed(() => tasks.value.reduce((sum, t) => sum + (t.total_fetched || 0), 0))
const totalSavedSum = computed(() => tasks.value.reduce((sum, t) => sum + (t.total_saved || 0), 0))

// 日志列表状态
const logs = ref<CollectionLog[]>([])
const logsTotal = ref(0)
const logsPage = ref(1)
const logsLoading = ref(false)
const logLevelFilter = ref('')
const logKeyword = ref('')

// 任务详情弹窗状态
const taskDialogVisible = ref(false)
const currentTask = ref<CollectionTask | null>(null)
const taskLogs = ref<CollectionLog[]>([])

const formatDate = (val?: string) => {
  if (!val) return '尚未调度或计算中'
  return val.replace('T', ' ').substring(0, 19)
}

const formatLogTime = (val?: string) => {
  if (!val) return ''
  const t = val.replace('T', ' ')
  return t.length > 23 ? t.substring(11, 23) : t.substring(11, 19)
}

const formatDuration = (ms?: number, isRunning?: boolean) => {
  if (isRunning) return '进行中...'
  if (!ms || ms <= 0) return '< 1s'
  const sec = Math.round(ms / 1000)
  if (sec < 60) return `${sec}秒`
  const min = Math.floor(sec / 60)
  const remainSec = sec % 60
  return `${min}分${remainSec}秒`
}

const loadStatus = async () => {
  loading.value = true
  try {
    const res = await getAutoCollectStatus()
    if (res.code === 1 && res.data) {
      statusData.value = res.data
      form.enabled = res.data.enabled
      form.interval_hours = res.data.interval_hours || 2
    }
  } finally {
    loading.value = false
  }
}

const loadTasks = async () => {
  tasksLoading.value = true
  try {
    const res = await getCollectionTasks({
      page: tasksPage.value,
      page_size: 20,
      status: taskStatusFilter.value,
      trigger_type: taskTriggerFilter.value
    })
    if (res.code === 1 && res.data) {
      tasks.value = res.data
      tasksTotal.value = res.total || 0
    }
  } finally {
    tasksLoading.value = false
  }
}

const loadLogs = async () => {
  logsLoading.value = true
  try {
    const res = await getCollectionLogs({
      page: logsPage.value,
      page_size: 50,
      level: logLevelFilter.value,
      keyword: logKeyword.value.trim()
    })
    if (res.code === 1 && res.data) {
      logs.value = res.data
      logsTotal.value = res.total || 0
    }
  } finally {
    logsLoading.value = false
  }
}

const refreshAll = async () => {
  await Promise.all([loadStatus(), loadTasks(), loadLogs()])
}

const saveConfig = async () => {
  saving.value = true
  try {
    const res = await saveAutoCollectConfig({
      enabled: form.enabled,
      interval_hours: form.interval_hours
    })
    if (res.code === 1) {
      notify('定时自动采集配置已成功更新', 'success')
      loadStatus()
    }
  } finally {
    saving.value = false
  }
}

const handleManualTrigger = async (hours: number) => {
  triggering.value = true
  try {
    const res = await triggerCollectAll(hours)
    if (res.code === 1) {
      notify(res.msg || '采集任务已在后台启动', 'success')
      await refreshAll()
    }
  } finally {
    triggering.value = false
  }
}

const openTaskLogs = async (task: CollectionTask) => {
  currentTask.value = task
  taskDialogVisible.value = true
  try {
    const res = await getCollectionTaskDetail(task.id)
    if (res.code === 1 && res.data) {
      currentTask.value = res.data.task
      taskLogs.value = res.data.logs || []
    }
  } catch (e: any) {
    notify(e.message || '加载任务日志失败', 'error')
  }
}

const copyLogsText = () => {
  if (!taskLogs.value.length) return
  const text = taskLogs.value.map(l => `[${formatLogTime(l.created_at)}] [${l.level}] ${l.message}`).join('\n')
  navigator.clipboard.writeText(text)
  notify('任务日志已复制到剪贴板', 'success')
}

const handleClearLogs = async () => {
  try {
    await confirmAction('确定清理 15 天前的历史采集日志吗？', '清理历史日志', { type: 'warning' })
    const res = await clearCollectionLogs(15)
    notify(res.msg || '历史日志清理成功', 'success')
    await loadLogs()
  } catch {
    // canceled
  }
}

onMounted(() => {
  refreshAll()
  refreshTimer = setInterval(() => {
    if (autoRefresh.value) {
      loadTasks()
      if (activeTab.value === 'logs') {
        loadLogs()
      }
    }
  }, 5000)
})

onBeforeUnmount(() => {
  if (refreshTimer) {
    clearInterval(refreshTimer)
  }
})
</script>

<style scoped lang="scss">
.scheduler-page {
  .status-card, .config-card, .mechanism-card, .runs-card {
    border-radius: 12px;
    border: 1px solid var(--border-color);

    .card-header, .runs-card-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
    }

    .card-title {
      font-size: 13px;
      font-weight: 650;
      color: var(--text-primary);
    }

    .header-aux {
      font-size: 10.5px;
      color: var(--text-secondary);
      white-space: nowrap;
    }
  }

  /* 上半区两张卡片等高对齐：内容纵向撑满，手动唤醒按钮吸底 */
  .status-card, .config-card {
    height: 100%;
    display: flex;
    flex-direction: column;

    :deep(.r-card__body) {
      flex: 1 1 auto;
      display: flex;
      flex-direction: column;
    }
  }

  /* 独立区块：调度运行机制说明 */
  .mechanism-card {
    margin-top: 16px;

    .mechanism-list {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
      gap: 12px;
      margin: 0;
      padding: 0;
      list-style: none;
    }

    .mechanism-item {
      display: flex;
      align-items: flex-start;
      gap: 10px;
      padding: 10px 12px;
      border-radius: 8px;
      background: rgba(20, 32, 57, 0.03);
      border: 1px solid var(--border-color);

      .idx {
        flex: none;
        width: 22px;
        height: 22px;
        display: grid;
        place-items: center;
        border-radius: 6px;
        background: rgba(79, 110, 242, 0.1);
        color: var(--brand);
        font-size: 10px;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
      }

      .copy {
        min-width: 0;

        strong {
          display: block;
          margin-bottom: 3px;
          font-size: 11.5px;
          font-weight: 650;
          color: var(--text-primary);
        }

        p {
          margin: 0;
          font-size: 10.5px;
          line-height: 1.65;
          color: var(--text-secondary);
        }
      }
    }
  }

  .runs-title-group {
    display: flex;
    align-items: center;
    gap: 12px;

    .running-indicator {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      font-size: 11.5px;
      color: #e6a23c;
      font-weight: 600;
      background: rgba(230, 162, 60, 0.12);
      padding: 3px 10px;
      border-radius: 20px;
    }
  }

  .status-content {
    flex: 1 1 auto;
    display: flex;
    flex-direction: column;
    gap: 12px;

    :deep(.r-divider) {
      margin-top: auto;
      margin-bottom: 0;
    }

    .status-item {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      font-size: 11.5px;

      .label {
        flex: none;
        white-space: nowrap;
        color: var(--text-secondary);
      }
      .val {
        min-width: 0;
        text-align: right;
        color: var(--text-primary);
      }
    }

    .quick-manual {
      .manual-title {
        font-size: 11.5px;
        font-weight: 600;
        color: var(--text-regular);
        margin-bottom: 8px;
        display: block;
      }
      .btns {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
      }
    }
  }

  .config-form {
    .unit-text {
      margin-left: 10px;
      font-size: 10px;
      color: var(--text-secondary);
      white-space: nowrap;
    }
  }

  /* 任务列表指标与工具栏 */
  .metrics-row {
    display: flex;
    gap: 12px;
    margin-bottom: 14px;
    flex-wrap: wrap;

    .metric-pill {
      flex: 1;
      min-width: 140px;
      padding: 10px 14px;
      border-radius: 8px;
      background: var(--bg-card-subtle, rgba(0,0,0,0.02));
      border: 1px solid var(--border-color);
      display: flex;
      flex-direction: column;
      gap: 4px;

      .pill-label {
        font-size: 11px;
        color: var(--text-secondary);
      }
      .pill-val {
        font-size: 18px;
        font-weight: 700;
        color: var(--text-primary);
      }

      &.running .pill-val {
        color: #e6a23c;
      }
      &.success .pill-val {
        color: #67c23a;
      }
      &.highlight .pill-val {
        color: var(--brand);
      }
    }
  }

  .tasks-toolbar, .logs-console-toolbar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 12px;
    flex-wrap: wrap;

    .filter-group, .toolbar-left {
      display: flex;
      align-items: center;
      gap: 10px;
      flex-wrap: wrap;
    }

    .auto-refresh-label {
      font-size: 11.5px;
      color: var(--text-secondary);
      display: flex;
      align-items: center;
      gap: 6px;
    }
  }

  .task-id-badge {
    font-family: monospace;
    font-weight: 600;
    color: var(--brand);
    background: rgba(79, 110, 242, 0.08);
    padding: 2px 6px;
    border-radius: 4px;
  }

  .source-cell {
    display: flex;
    flex-direction: column;
    gap: 2px;

    .source-id-sub {
      font-size: 10.5px;
      color: var(--text-secondary);
      font-family: monospace;
    }
  }

  .stats-metric-line {
    font-size: 11.5px;
    display: flex;
    align-items: center;
    gap: 6px;

    .sep {
      color: var(--border-color);
    }
    .success-text {
      color: #67c23a;
    }
    .mute-text {
      color: var(--text-secondary);
    }
  }

  .time-text {
    font-size: 11px;
    color: var(--text-secondary);
  }
  .duration-text {
    font-size: 11px;
    font-weight: 600;
    color: var(--text-primary);
  }

  .rotating-icon {
    animation: spin 1.8s linear infinite;
  }

  @keyframes spin {
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
  }

  /* 终端风格日志视窗 */
  .terminal-log-box {
    margin-top: 12px;
    background: #18191c;
    color: #e4e7ed;
    border-radius: 8px;
    padding: 12px 14px;
    font-family: Consolas, Monaco, 'Courier New', monospace;
    font-size: 11.5px;
    line-height: 1.6;
    max-height: 480px;
    min-height: 240px;
    overflow-y: auto;
    border: 1px solid #2d3035;

    .empty-logs {
      color: #909399;
      text-align: center;
      padding: 40px 0;
    }

    .log-line {
      display: flex;
      gap: 8px;
      align-items: baseline;
      padding: 2px 0;
      border-bottom: 1px solid rgba(255,255,255,0.03);

      .log-time {
        color: #858b97;
        font-size: 11px;
        flex-shrink: 0;
      }
      .log-level-badge {
        font-weight: 700;
        font-size: 10.5px;
        flex-shrink: 0;

        &.info { color: #409eff; }
        &.success { color: #67c23a; }
        &.warn { color: #e6a23c; }
        &.error { color: #f56c6c; }
      }
      .log-task-tag {
        color: #909399;
        font-size: 10.5px;
        flex-shrink: 0;
      }
      .log-source {
        color: #a0a6b5;
        font-weight: 500;
        flex-shrink: 0;
      }
      .log-msg {
        color: #dcdfe6;
        word-break: break-all;
      }
    }
  }

  .pagination-box {
    margin-top: 14px;
    display: flex;
    justify-content: flex-end;
  }

  /* 弹窗中的任务概览与日志 */
  .task-detail-overview {
    background: var(--bg-card-subtle, rgba(0,0,0,0.02));
    border: 1px solid var(--border-color);
    border-radius: 8px;
    padding: 12px 14px;
    margin-bottom: 14px;

    .detail-grid {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 8px 16px;
      font-size: 11.5px;

      .detail-item {
        display: flex;
        align-items: center;
        gap: 6px;

        .k {
          color: var(--text-secondary);
        }

        &.full {
          grid-column: span 2;
        }
        &.error {
          color: #f56c6c;
        }
      }
    }
  }

  .dialog-logs-terminal {
    border: 1px solid #2d3035;
    border-radius: 8px;
    overflow: hidden;

    .terminal-header {
      background: #232529;
      color: #c0c4cc;
      padding: 6px 12px;
      font-size: 11.5px;
      font-weight: 600;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .terminal-body {
      background: #18191c;
      color: #e4e7ed;
      padding: 12px;
      max-height: 380px;
      overflow-y: auto;
      font-family: Consolas, Monaco, monospace;
      font-size: 11px;
      line-height: 1.6;

      .empty-logs {
        color: #909399;
        text-align: center;
        padding: 24px 0;
      }

      .log-line {
        display: flex;
        gap: 8px;
        padding: 2px 0;

        .log-time { color: #858b97; flex-shrink: 0; }
        .log-level-badge {
          font-weight: 700;
          flex-shrink: 0;
          &.info { color: #409eff; }
          &.success { color: #67c23a; }
          &.warn { color: #e6a23c; }
          &.error { color: #f56c6c; }
        }
        .log-msg { color: #dcdfe6; word-break: break-all; }
      }
    }
  }
}
</style>
