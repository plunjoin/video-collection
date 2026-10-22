<template>
  <r-card shadow="never" class="rows-card">
    <div class="table-header">
      <div>
        <h2>{{ businessType?.name || slug }}</h2>
        <p>{{ businessType?.description || '浏览该业务类型的采集数据。' }}</p>
      </div>
      <div class="header-actions">
        <r-button @click="loadRows" :loading="loading">刷新</r-button>
        <r-button v-if="isCustom" type="primary" :disabled="!canDelete || !businessType" @click="openCreate">新增</r-button>
      </div>
    </div>

    <r-form v-if="isCustom && filterFields.length" label-position="top" class="filter-bar" @submit="applyFilters">
      <r-form-item v-if="hasTextFilter" label="搜索" class="filter-item">
        <r-input v-model="filterDraft.q" placeholder="搜索可筛选文本" aria-label="搜索可筛选文本" />
      </r-form-item>
      <r-form-item v-for="field in filterFields" :key="field.name" :label="field.label || field.name" class="filter-item">
        <r-select v-if="field.data_type === 'enum'" v-model="filterDraft[field.name]" placeholder="全部" :aria-label="field.label || field.name">
          <r-option value="" label="全部" />
          <r-option v-for="option in field.options || []" :key="option" :value="option" :label="option" />
        </r-select>
        <r-select v-else-if="field.data_type === 'boolean'" v-model="filterDraft[field.name]" placeholder="全部" :aria-label="field.label || field.name">
          <r-option value="" label="全部" />
          <r-option value="true" label="是" />
          <r-option value="false" label="否" />
        </r-select>
        <div v-else-if="isNumeric(field)" class="number-range">
          <r-input v-model="filterDraft[`${field.name}_min`]" type="number" :step="field.data_type === 'integer' ? 1 : 'any'" placeholder="最小值" :aria-label="`${field.label || field.name} 最小值`" />
          <span>至</span>
          <r-input v-model="filterDraft[`${field.name}_max`]" type="number" :step="field.data_type === 'integer' ? 1 : 'any'" placeholder="最大值" :aria-label="`${field.label || field.name} 最大值`" />
        </div>
        <r-input v-else v-model="filterDraft[field.name]" placeholder="请输入筛选值" :aria-label="field.label || field.name" />
      </r-form-item>
      <div class="filter-actions">
        <r-button type="primary" native-type="submit" :loading="loading">筛选</r-button>
        <r-button @click="resetFilters">重置</r-button>
      </div>
    </r-form>

    <r-table :data="rows" :loading="loading" border stripe empty-text="还没有数据，可以点上方新增，或等采集写入">
      <r-table-column v-if="isCustom" prop="id" label="ID" width="75" align="center" />
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

    <r-dialog v-if="isCustom" v-model="createVisible" title="新增数据" width="min(600px, 95vw)">
      <r-form label-position="top" :disabled="saving" @submit="saveRow">
        <r-form-item v-for="field in fields" :key="field.name" :label="field.label || field.name" :required="field.required">
          <r-select v-if="field.data_type === 'enum'" v-model="rowDraft[field.name]" :aria-label="field.label || field.name" placeholder="请选择" clearable>
            <r-option v-for="option in field.options || []" :key="option" :value="option" :label="option" />
          </r-select>
          <r-select v-else-if="field.data_type === 'boolean'" v-model="rowDraft[field.name]" :aria-label="field.label || field.name" placeholder="请选择" clearable>
            <r-option value="true" label="是" />
            <r-option value="false" label="否" />
          </r-select>
          <r-input v-else-if="isNumeric(field)" v-model="rowDraft[field.name]" type="number" :step="field.data_type === 'integer' ? 1 : 'any'" :aria-label="field.label || field.name" />
          <r-input v-else-if="field.data_type === 'json'" v-model="rowDraft[field.name]" type="textarea" :rows="5" placeholder="请输入有效的 JSON" :aria-label="field.label || field.name" />
          <r-input v-else v-model="rowDraft[field.name]" :aria-label="field.label || field.name" />
        </r-form-item>
      </r-form>
      <template #footer>
        <r-button :disabled="saving" @click="createVisible = false">取消</r-button>
        <r-button type="primary" :loading="saving" @click="saveRow">保存</r-button>
      </template>
    </r-dialog>
  </r-card>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { deleteBusinessRow, listBusinessRows, listBusinessTypes, listSchemaRows, saveSchemaRow } from '@/api/businessTypes'
import type { BusinessRow, BusinessType, BusinessTypeField } from '@/api/businessTypes'
import { useUserStore } from '@/store/user'
import { confirmAction, notify } from '@/components/radix/feedback'

const route = useRoute()
const userStore = useUserStore()
const slug = computed(() => String(route.params.slug || 'record'))
const isCustom = computed(() => slug.value !== 'record')
const businessType = ref<BusinessType | null>(null)
const rows = ref<BusinessRow[]>([])
const total = ref(0)
const page = ref(1)
const pageSize = 20
const loading = ref(false)
const saving = ref(false)
const createVisible = ref(false)
const rowDraft = ref<Record<string, string>>({})
const filterDraft = ref<Record<string, string>>({})
const filters = ref<Record<string, string>>({})
let rowsRequest = 0
const canDelete = computed(() => ['super_admin', 'admin'].includes(userStore.userInfo?.role || ''))
const fields = computed<BusinessTypeField[]>(() => businessType.value?.fields || [])
const filterFields = computed(() => fields.value.filter(field => field.filterable === true && field.data_type !== 'json'))
const hasTextFilter = computed(() => filterFields.value.some(field => field.data_type === 'text'))

function isNumeric(field: BusinessTypeField) {
  return field.data_type === 'integer' || field.data_type === 'real'
}

function applyFilters() {
  filters.value = Object.fromEntries(Object.entries(filterDraft.value).filter(([, value]) => value !== ''))
  page.value = 1
  void loadRows()
}

function resetFilters() {
  filterDraft.value = {}
  applyFilters()
}

function openCreate() {
  rowDraft.value = Object.fromEntries(fields.value.map(field => [field.name, '']))
  createVisible.value = true
}

async function saveRow() {
  if (!isCustom.value || !canDelete.value || saving.value) return
  const body: Record<string, unknown> = {}
  for (const field of fields.value) {
    const value = rowDraft.value[field.name] ?? ''
    const label = field.label || field.name
    if (!value.trim()) {
      if (field.required) { notify(`请填写“${label}”`, 'warning'); return }
      continue
    }
    if (isNumeric(field)) {
      const number = Number(value)
      if (!Number.isFinite(number) || (field.data_type === 'integer' && !Number.isInteger(number))) {
        notify(`“${label}”请输入有效的${field.data_type === 'integer' ? '整数' : '数字'}`, 'warning')
        return
      }
      body[field.name] = number
    } else if (field.data_type === 'boolean') {
      body[field.name] = value === 'true'
    } else if (field.data_type === 'json') {
      try { JSON.parse(value) } catch { notify(`“${label}”请输入有效的 JSON`, 'warning'); return }
      // The save endpoint accepts JSON text, preserving JSON string values too.
      body[field.name] = value
    } else {
      body[field.name] = value
    }
  }
  const currentSlug = slug.value
  saving.value = true
  try {
    await saveSchemaRow(currentSlug, body)
    notify('记录已保存', 'success')
    if (currentSlug === slug.value) {
      createVisible.value = false
      await loadRows()
    }
  } catch { /* request interceptor displays the error */ } finally { saving.value = false }
}

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
  const request = ++rowsRequest
  const currentSlug = slug.value
  loading.value = true
  try {
    const response = isCustom.value
      ? await listSchemaRows(currentSlug, page.value, pageSize, filters.value)
      : await listBusinessRows(currentSlug, page.value, pageSize)
    if (request !== rowsRequest || currentSlug !== slug.value) return
    rows.value = response.data || []
    total.value = response.total ?? rows.value.length
    const lastPage = Math.max(1, Math.ceil(total.value / pageSize))
    if (page.value > lastPage) { page.value = lastPage; await loadRows() }
  } catch { /* request interceptor displays the error */ } finally {
    if (request === rowsRequest) loading.value = false
  }
}

async function loadType() {
  const currentSlug = slug.value
  try {
    const response = await listBusinessTypes()
    if (currentSlug === slug.value) businessType.value = (response.data || []).find((item) => item.slug === currentSlug) || null
  } catch { /* request interceptor displays the error */ }
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
  filterDraft.value = {}
  filters.value = {}
  createVisible.value = false
  rowDraft.value = {}
  businessType.value = null
  rows.value = []
  total.value = 0
  await Promise.all([loadType(), loadRows()])
}

watch(slug, load)
onMounted(load)
</script>

<style scoped>
.rows-card { min-width: 0; }
.table-header { display: flex; align-items: center; justify-content: space-between; gap: 16px; margin-bottom: 16px; }
.header-actions, .filter-actions { display: flex; gap: 8px; }
.filter-bar { display: flex; flex-wrap: wrap; align-items: flex-end; gap: 12px; margin-bottom: 20px; }
.filter-item { flex: 1 1 200px; min-width: 180px; margin-bottom: 0; }
.number-range { display: flex; align-items: center; gap: 8px; }
.number-range .r-input { min-width: 0; flex: 1; }
.filter-actions { padding-bottom: 2px; }
h2 { margin: 0; font-size: 18px; }
p { margin: 6px 0 0; color: var(--text-secondary); font-size: 13px; }
.pagination-wrap { display: flex; justify-content: flex-end; margin-top: 18px; }
@media (max-width: 720px) { .table-header { align-items: flex-start; flex-wrap: wrap; } .filter-item { flex-basis: 100%; } }
</style>
