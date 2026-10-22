<template>
  <r-card shadow="never" class="rows-card">
    <div class="table-header">
      <div>
        <h2>{{ businessType?.name || slug }}</h2>
        <p>{{ businessType?.description || '浏览该业务类型的采集数据。' }}</p>
      </div>
      <r-button @click="loadRows" :loading="loading">刷新</r-button>
    </div>

    <r-table :data="rows" :loading="loading" border stripe empty-text="暂无数据">
      <r-table-column v-if="slug !== 'record'" prop="id" label="ID" width="75" align="center" />
      <r-table-column label="来源" prop="source_id" min-width="130" show-overflow-tooltip />
      <r-table-column label="记录标识" min-width="150" show-overflow-tooltip>
        <template #default="{ row }">{{ row.key || row.record_key || '-' }}</template>
      </r-table-column>
      <r-table-column v-for="field in fields" :key="field.name" :label="field.label || field.name" :min-width="field.data_type === 'json' ? 180 : 130" show-overflow-tooltip>
        <template #default="{ row }">{{ displayValue(valueFor(row, field.name)) }}</template>
      </r-table-column>
      <r-table-column label="更新时间" prop="updated_at" width="170" align="center">
        <template #default="{ row }">{{ formatDate(row.updated_at) }}</template>
      </r-table-column>
      <r-table-column v-if="canDelete" label="操作" width="90" align="center" fixed="right">
        <template #default="{ row }"><r-button type="danger" link size="small" @click="removeRow(row)">删除</r-button></template>
      </r-table-column>
    </r-table>

    <div v-if="total > pageSize" class="pagination-wrap">
      <r-pagination v-model:current-page="page" :total="total" :page-size="pageSize" layout="total, prev, pager, next" @current-change="loadRows" />
    </div>
  </r-card>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { deleteBusinessRow, listBusinessRows, listBusinessTypes } from '@/api/businessTypes'
import type { BusinessRow, BusinessType, BusinessTypeField } from '@/api/businessTypes'
import { useUserStore } from '@/store/user'
import { confirmAction, notify } from '@/components/radix/feedback'

const route = useRoute()
const userStore = useUserStore()
const slug = computed(() => String(route.params.slug || 'record'))
const businessType = ref<BusinessType | null>(null)
const rows = ref<BusinessRow[]>([])
const total = ref(0)
const page = ref(1)
const pageSize = 20
const loading = ref(false)
const canDelete = computed(() => ['super_admin', 'admin'].includes(userStore.userInfo?.role || ''))
const fields = computed<BusinessTypeField[]>(() => businessType.value?.fields || [])

function valueFor(row: BusinessRow, name: string) {
  if (slug.value === 'record') return row.values?.[name] ?? row.payload?.[name]
  return row[name]
}

function displayValue(value: unknown) {
  if (value === undefined || value === null || value === '') return '-'
  return typeof value === 'object' ? JSON.stringify(value) : String(value)
}

function formatDate(value?: string) {
  return value ? value.replace('T', ' ').slice(0, 19) : '-'
}

async function loadRows() {
  loading.value = true
  try {
    const response = await listBusinessRows(slug.value, page.value, pageSize)
    rows.value = response.data || []
    total.value = response.total ?? rows.value.length
    const lastPage = Math.max(1, Math.ceil(total.value / pageSize))
    if (page.value > lastPage) { page.value = lastPage; await loadRows() }
  } finally {
    loading.value = false
  }
}

async function loadType() {
  const response = await listBusinessTypes()
  businessType.value = (response.data || []).find((item) => item.slug === slug.value) || null
}

async function removeRow(row: BusinessRow) {
  if (!canDelete.value) return
  const identity = row.key || row.record_key || String(row.id)
  try { await confirmAction(`确定删除记录“${identity}”？删除后无法恢复。`, '删除数据', { type: 'warning' }) } catch { return }
  try {
    if (slug.value === 'record') await deleteBusinessRow(slug.value, { source_id: row.source_id, key: row.key || row.record_key })
    else await deleteBusinessRow(slug.value, { id: Number(row.id) })
    notify('记录已删除', 'success')
    await loadRows()
  } catch { /* request interceptor displays the error */ }
}

async function load() {
  page.value = 1
  await Promise.all([loadType(), loadRows()])
}

watch(slug, load)
onMounted(load)
</script>

<style scoped>
.rows-card { min-width: 0; }
.table-header { display: flex; align-items: center; justify-content: space-between; gap: 16px; margin-bottom: 16px; }
h2 { margin: 0; font-size: 18px; }
p { margin: 6px 0 0; color: var(--text-secondary); font-size: 13px; }
.pagination-wrap { display: flex; justify-content: flex-end; margin-top: 18px; }
@media (max-width: 720px) { .table-header { align-items: flex-start; } }
</style>
