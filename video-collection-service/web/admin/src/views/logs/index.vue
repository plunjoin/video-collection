<template>
  <div class="logs-page">
    <r-card shadow="never" class="table-card">
      <div class="table-header">
        <div class="header-left">
          <span class="page-title">系统日志</span>
          <span class="sub-desc">后台登录、管理操作与重要系统事件（与使魔采集日志分开）</span>
        </div>
        <div class="header-right">
          <r-select v-model="filters.level" clearable placeholder="级别" style="width: 120px" @change="reload">
            <r-option label="全部级别" value="" />
            <r-option label="信息" value="info" />
            <r-option label="警告" value="warn" />
            <r-option label="错误" value="error" />
          </r-select>
          <r-select v-model="filters.category" clearable placeholder="分类" style="width: 140px" @change="reload">
            <r-option label="全部分类" value="" />
            <r-option label="登录鉴权" value="auth" />
            <r-option label="后台管理" value="admin" />
            <r-option label="采集触发" value="collect" />
            <r-option label="内容运营" value="content" />
            <r-option label="系统" value="system" />
          </r-select>
          <r-input
            v-model="filters.q"
            clearable
            placeholder="搜索内容或操作人"
            style="width: 200px"
            @keyup.enter="reload"
            @clear="reload"
          />
          <r-button @click="reload" :loading="loading">刷新</r-button>
        </div>
      </div>

      <r-table :data="tableData" v-loading="loading" border stripe style="width: 100%" empty-text="暂时还没有系统日志">
        <r-table-column prop="level" label="级别" width="90" align="center">
          <template #default="{ row }">
            <r-tag :type="levelTag(row.level)" size="small">{{ levelLabel(row.level) }}</r-tag>
          </template>
        </r-table-column>
        <r-table-column prop="category" label="分类" width="110" align="center">
          <template #default="{ row }">
            {{ categoryLabel(row.category) }}
          </template>
        </r-table-column>
        <r-table-column prop="message" label="内容" min-width="280" show-overflow-tooltip />
        <r-table-column prop="actor_name" label="操作人" width="120" align="center">
          <template #default="{ row }">
            <span>{{ row.actor_name || '系统' }}</span>
          </template>
        </r-table-column>
        <r-table-column prop="created_at" label="时间" width="180" align="center">
          <template #default="{ row }">
            <span class="date-text">{{ formatDate(row.created_at) }}</span>
          </template>
        </r-table-column>
      </r-table>

      <div class="pagination-box" v-if="total > 0">
        <r-pagination
          v-model:current-page="page"
          v-model:page-size="pageSize"
          :total="total"
          layout="total, prev, pager, next"
          @current-change="loadData"
          @size-change="reload"
        />
      </div>
    </r-card>
  </div>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { getSystemLogs } from '@/api/admin'
import type { SystemLogEntry } from '@/types'

const loading = ref(false)
const tableData = ref<SystemLogEntry[]>([])
const total = ref(0)
const page = ref(1)
const pageSize = ref(20)
const filters = reactive({
  level: '',
  category: '',
  q: '',
})

function levelLabel(level: string) {
  return ({ info: '信息', warn: '警告', error: '错误' } as Record<string, string>)[level] || level
}

function levelTag(level: string) {
  return ({ info: 'info', warn: 'warning', error: 'danger' } as Record<string, string>)[level] || 'info'
}

function categoryLabel(category: string) {
  return ({
    auth: '登录鉴权',
    admin: '后台管理',
    collect: '采集触发',
    content: '内容运营',
    system: '系统',
  } as Record<string, string>)[category] || category
}

function formatDate(value?: string) {
  if (!value) return '-'
  const d = new Date(value)
  if (Number.isNaN(d.getTime())) return value
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
}

function reload() {
  page.value = 1
  loadData()
}

async function loadData() {
  loading.value = true
  try {
    const res = await getSystemLogs({
      page: page.value,
      page_size: pageSize.value,
      level: filters.level || undefined,
      category: filters.category || undefined,
      q: filters.q.trim() || undefined,
    })
    tableData.value = (res as any)?.data || []
    total.value = (res as any)?.total || 0
  } catch {
    tableData.value = []
    total.value = 0
  } finally {
    loading.value = false
  }
}

onMounted(loadData)
</script>

<style scoped>
.logs-page { padding: 0; }
.table-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
  margin-bottom: 16px;
}
.header-right { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; }
.page-title { font-size: 18px; font-weight: 600; margin-right: 12px; }
.sub-desc { color: #94a3b8; font-size: 13px; }
.date-text { color: #64748b; font-size: 13px; }
.pagination-box { display: flex; justify-content: flex-end; margin-top: 16px; }
</style>
