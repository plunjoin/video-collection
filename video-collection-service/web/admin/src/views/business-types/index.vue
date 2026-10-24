<template>
  <div class="business-page" v-loading="loading">
    <header class="page-heading">
      <div><h1>业务类型</h1><p>为采集内容设置字段和填写方式，之后可以在资源库里按需要筛选。</p></div>
      <div class="actions"><r-button @click="load">刷新</r-button><r-button type="primary" :disabled="!canManage" @click="openCreate">新建业务类型</r-button></div>
    </header>
    <div class="registry-layout">
      <aside class="type-list" aria-label="业务类型列表">
        <button v-for="item in types" :key="item.slug" type="button" :class="{ selected: selected?.slug === item.slug }" @click="select(item)">
          <strong>{{ item.name }}</strong><r-tag :type="item.is_system ? 'info' : 'success'" size="small">{{ item.is_system ? '系统' : '自定义' }}</r-tag>
          <small>{{ item.slug }} · {{ item.fields.length }} 个字段</small>
        </button>
        <r-empty v-if="!types.length" description="暂无业务类型" />
      </aside>
      <r-card v-if="selected" class="type-detail" shadow="never">
        <div class="detail-heading"><h2>{{ selected.name }} <small>{{ selected.slug }}</small></h2><r-button v-if="!selected.is_system" type="danger" plain :disabled="!canManage || saving" @click="removeType">删除类型</r-button></div>
        <r-form label-position="top">
          <div class="metadata"><r-form-item label="名称"><r-input v-model="selected.name" :disabled="!canManage" /></r-form-item><r-form-item label="说明"><r-input v-model="selected.description" :disabled="!canManage" /></r-form-item></div>
          <r-button :disabled="!canManage" :loading="saving" @click="saveMetadata">保存名称与说明</r-button>
        </r-form>
        <r-divider />
        <div class="detail-heading"><h3>字段配置</h3><r-button :disabled="!canManage" @click="openField">添加字段</r-button></div>
        <r-alert title="系统字段不能删除或改类型；可以补充自定义字段和列表筛选设置。" type="info" :closable="false" />
        <p v-if="selected.is_system" class="helper">系统字段不能删除或改类型；可以补充自定义字段和列表筛选设置。</p>
        <p v-else class="helper">字段名和类型创建后不可修改。删除字段会移除该字段已有的数据。</p>
        <div class="field-table"><r-table :data="selected.fields" border>
          <r-table-column label="显示名称" min-width="190"><template #default="{ row }"><div class="field-name-cell"><r-input v-model="row.label" :disabled="!canManage" /><small><code>{{ row.name }}</code><r-tag v-if="row.is_system" size="small" type="info">系统</r-tag></small></div></template></r-table-column>
          <r-table-column label="类型" min-width="220"><template #default="{ row }"><div>{{ typeLabel(row.data_type) }}</div><div v-if="row.data_type === 'enum'" class="options-editor compact"><div class="options-tags"><r-tag v-for="option in row.options" :key="option" size="small">{{ option }}</r-tag></div><div v-for="(_, i) in row.options" :key="`edit-${i}`" class="option-line"><r-input v-model="row.options![i]" placeholder="例如：上架 / 下架" /><r-button type="danger" link size="small" :disabled="!canManage" @click="removeOption(row, i)">移除</r-button></div><r-button size="small" link :disabled="!canManage" @click="addOption(row)">+ 添加选项</r-button></div></template></r-table-column>
          <r-table-column label="必填" width="80"><template #default="{ row }"><r-checkbox v-model="row.required" :disabled="row.is_system || !canManage" :aria-label="`${row.name} 必填`" /></template></r-table-column>
          <r-table-column label="可筛选" width="95"><template #default="{ row }"><r-checkbox v-model="row.filterable" :disabled="row.data_type === 'json' || !canManage" :aria-label="`${row.name} 可筛选`" /><small v-if="row.data_type === 'json'" class="muted">不可筛选</small></template></r-table-column>
          <r-table-column label="默认值" min-width="140"><template #default="{ row }"><r-select v-if="row.data_type === 'enum'" v-model="row.default" clearable placeholder="无" :disabled="!canManage" :aria-label="`${row.name} 默认值`"><r-option v-for="option in row.options || []" :key="option" :value="option" :label="option" /></r-select><r-input v-else v-model="row.default" :disabled="!canManage || row.data_type === 'json'" :placeholder="row.data_type === 'json' ? 'JSON 不设默认' : '采集缺省时使用'" :aria-label="`${row.name} 默认值`" /></template></r-table-column>
          <r-table-column label="操作" width="145"><template #default="{ row }"><r-button size="small" :disabled="!canManage || saving" @click="saveField(row)">保存</r-button><r-button v-if="!row.is_system" size="small" type="danger" link :disabled="!canManage || saving" @click="removeField(row)">删除</r-button></template></r-table-column>
        </r-table></div>
      </r-card>
    </div>

    <r-dialog v-model="createVisible" title="新建业务类型" width="min(900px, 95vw)">
      <r-form label-position="top">
        <div class="metadata"><r-form-item label="类型标识（创建后不可修改）" required><r-input v-model="draft.slug" placeholder="例如 wiki_entry" maxlength="48" /><p class="helper">2–48 位小写字母、数字或下划线，以字母开头，不得以 biz_ 开头。</p></r-form-item><r-form-item label="名称" required><r-input v-model="draft.name" placeholder="例如 词条资料" /></r-form-item></div>
        <r-form-item label="说明"><r-input v-model="draft.description" type="textarea" :rows="2" /></r-form-item>
        <div class="detail-heading"><h3>初始字段（可稍后添加）</h3><r-button @click="draft.fields.push(newBusinessField())">添加字段</r-button></div>
        <div v-for="(field, i) in draft.fields" :key="i" class="initial-field">
          <r-input v-model="field.name" placeholder="字段名，例如 title" :aria-label="`字段 ${i + 1} 名称`" maxlength="48" />
          <r-input v-model="field.label" placeholder="显示名称" :aria-label="`字段 ${i + 1} 显示名称`" />
          <div><r-select v-model="field.data_type" :aria-label="`字段 ${i + 1} 类型`" @change="handleTypeChange(field)"><r-option v-for="kind in dataTypes" :key="kind" :value="kind" :label="typeLabel(kind)" /></r-select><small class="helper">{{ typeHelper(field.data_type) }}</small></div>
          <div class="initial-flags"><r-checkbox v-model="field.required">必填</r-checkbox><r-checkbox v-model="field.filterable" :disabled="field.data_type === 'json'">允许筛选</r-checkbox><small v-if="field.data_type === 'json'" class="helper">这种类型不能用来筛选</small></div>
          <r-input v-model="field.default" :disabled="field.data_type === 'json'" :placeholder="field.data_type === 'enum' ? '默认选项（须在选项中）' : '默认值（可选）'" :aria-label="`字段 ${i + 1} 默认值`" />
          <div v-if="field.data_type === 'enum'" class="options-editor"><div v-for="(_, optionIndex) in field.options" :key="optionIndex" class="option-line"><r-input v-model="field.options![optionIndex]" placeholder="例如：上架 / 下架" /><r-button type="danger" link size="small" @click="removeOption(field, optionIndex)">移除</r-button></div><r-button size="small" link @click="addOption(field)">+ 添加选项</r-button></div>
          <r-button type="danger" link @click="draft.fields.splice(i, 1)">移除</r-button>
        </div>
      </r-form>
      <template #footer><r-button @click="createVisible = false">取消</r-button><r-button type="primary" :loading="saving" @click="create">创建</r-button></template>
    </r-dialog>

    <r-dialog v-model="fieldVisible" title="添加字段" width="min(560px, 95vw)">
      <r-form label-position="top">
        <r-form-item label="字段名（创建后不可修改）" required><r-input v-model="fieldDraft.name" placeholder="小写字母、数字、下划线，以字母开头" maxlength="48" /></r-form-item>
        <r-form-item label="显示名称"><r-input v-model="fieldDraft.label" /></r-form-item>
        <r-form-item label="数据类型"><r-select v-model="fieldDraft.data_type" @change="handleTypeChange(fieldDraft)"><r-option v-for="kind in dataTypes" :key="kind" :value="kind" :label="typeLabel(kind)" /></r-select><p class="helper type-helper">{{ typeHelper(fieldDraft.data_type) }}</p></r-form-item>
        <r-checkbox v-model="fieldDraft.required">必填（后续采集必须提供值）</r-checkbox>
        <r-checkbox v-model="fieldDraft.filterable" :disabled="fieldDraft.data_type === 'json'">允许在列表里筛选</r-checkbox><p class="helper">{{ fieldDraft.data_type === 'json' ? '这种类型不能用来筛选' : '勾选后，资源库/数据列表可以用这个字段做筛选' }}</p>
        <r-form-item label="默认值（采集未提供时自动填入）"><r-select v-if="fieldDraft.data_type === 'enum'" v-model="fieldDraft.default" clearable placeholder="无"><r-option v-for="option in fieldDraft.options || []" :key="option" :value="option" :label="option" /></r-select><r-input v-else v-model="fieldDraft.default" :disabled="fieldDraft.data_type === 'json'" :placeholder="fieldDraft.data_type === 'json' ? 'JSON 不设默认' : '可选'" /></r-form-item>
        <div v-if="fieldDraft.data_type === 'enum'" class="options-editor"><strong>固定选项</strong><div v-for="(_, i) in fieldDraft.options" :key="i" class="option-line"><r-input v-model="fieldDraft.options![i]" placeholder="例如：上架 / 下架" /><r-button type="danger" link size="small" @click="removeOption(fieldDraft, i)">移除</r-button></div><r-button size="small" link @click="addOption(fieldDraft)">+ 添加选项</r-button></div>
      </r-form>
      <template #footer><r-button @click="fieldVisible = false">取消</r-button><r-button type="primary" :loading="saving" @click="addField">添加</r-button></template>
    </r-dialog>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { notify, confirmAction } from '@/components/radix/feedback'
import { useUserStore } from '@/store/user'
import { listBusinessTypes, createBusinessType, updateBusinessType, deleteBusinessType, addBusinessField, updateBusinessField, deleteBusinessField, newBusinessField } from '@/api/businessTypes'
import type { BusinessType, BusinessTypeField, BusinessTypeInput, BusinessDataType, BusinessFieldInput } from '@/api/businessTypes'

const user = useUserStore()
const canManage = computed(() => ['super_admin', 'admin'].includes(user.userInfo?.role || ''))
const types = ref<BusinessType[]>([]), selected = ref<BusinessType | null>(null)
const loading = ref(false), saving = ref(false), createVisible = ref(false), fieldVisible = ref(false)
const dataTypes: BusinessDataType[] = ['text', 'integer', 'real', 'boolean', 'enum', 'json']
const typeInfo: Record<BusinessDataType, { label: string; helper: string }> = {
  text: { label: '文本', helper: '普通文字，适合标题、名称' }, integer: { label: '整数', helper: '只能填整数，适合数量、编号' }, real: { label: '小数', helper: '可以有小数，适合评分、价格' }, boolean: { label: '是/否', helper: '只有是或否两种情况' }, enum: { label: '固定选项（下拉）', helper: '只能从你设好的几个值里选，适合状态、分类' }, json: { label: '高级数据（一般不用筛）', helper: '存复杂内容，列表里通常不筛' },
}
const draft = ref<BusinessTypeInput>({ slug: '', name: '', description: '', fields: [] })
const fieldDraft = ref(newBusinessField())
const fieldNamePattern = /^[a-z][a-z0-9_]{0,47}$/

function typeLabel(kind: BusinessDataType) { return typeInfo[kind].label }
function typeHelper(kind: BusinessDataType) { return typeInfo[kind].helper }
function normalizedField(field: BusinessTypeField): BusinessTypeField { return { ...field, filterable: field.data_type === 'json' ? false : field.filterable !== false, options: field.data_type === 'enum' ? [...(field.options || [])] : [], default: field.default || '' } }
function cloneType(item: BusinessType): BusinessType { return { ...item, fields: item.fields.map(normalizedField) } }
function select(item: BusinessType) { selected.value = cloneType(item) }
async function load(slug = selected.value?.slug) {
  loading.value = true
  try { types.value = (await listBusinessTypes()).data || []; const item = types.value.find(item => item.slug === slug) || types.value[0]; selected.value = item ? cloneType(item) : null } finally { loading.value = false }
}
function openCreate() { draft.value = { slug: '', name: '', description: '', fields: [] }; createVisible.value = true }
function openField() { fieldDraft.value = newBusinessField(); fieldDraft.value.sort_order = selected.value?.fields.length || 0; fieldVisible.value = true }
function handleTypeChange(field: BusinessFieldInput) { if (field.data_type !== 'enum') field.options = []; if (field.data_type === 'json') field.filterable = false; else if (field.filterable === undefined) field.filterable = true }
function addOption(field: BusinessFieldInput) { if (!field.options) field.options = []; field.options.push('') }
function removeOption(field: BusinessFieldInput, index: number) { field.options?.splice(index, 1) }
function cleanOptions(field: BusinessFieldInput) { return (field.options || []).map(option => option.trim()).filter(Boolean) }
function validateField(field: BusinessFieldInput, seen: Set<string>) {
  if (!fieldNamePattern.test(field.name) || seen.has(field.name)) { notify(`请填写合法且不重复的字段名：${field.name || '未命名字段'}`, 'warning'); return false }
  seen.add(field.name)
  if (field.data_type === 'enum') { field.options = cleanOptions(field); if (!field.options.length) { notify(`字段“${field.label || field.name}”至少需要一个固定选项`, 'warning'); return false } } else field.options = []
  if (field.data_type === 'json') { field.filterable = false; field.default = '' }
  else if (field.filterable === undefined) field.filterable = true
  field.default = (field.default || '').trim()
  if (field.default && field.data_type === 'enum' && !(field.options || []).includes(field.default)) { notify(`字段“${field.label || field.name}”的默认值必须是固定选项之一`, 'warning'); return false }
  return true
}
async function mutate(action: () => Promise<unknown>, slug = selected.value?.slug) { saving.value = true; try { await action(); await load(slug); notify('已保存', 'success'); return true } catch { return false } finally { saving.value = false } }
async function create() {
  if (!draft.value.name.trim() || !/^[a-z][a-z0-9_]{1,47}$/.test(draft.value.slug) || draft.value.slug.startsWith('biz_')) { notify('请填写名称与合法的类型标识', 'warning'); return }
  const seen = new Set<string>(); if (!draft.value.fields.every((field, i) => { field.sort_order = i; return validateField(field, seen) })) return
  if (await mutate(() => createBusinessType(draft.value), draft.value.slug)) createVisible.value = false
}
async function saveMetadata() { const b = selected.value; if (b) await mutate(() => updateBusinessType(b.slug, { name: b.name, description: b.description })) }
async function addField() { const b = selected.value; if (!b || !validateField(fieldDraft.value, new Set())) return; if (await mutate(() => addBusinessField(b.slug, fieldDraft.value))) fieldVisible.value = false }
async function saveField(field: BusinessTypeField) {
  const b = selected.value; if (!b || !validateField(field, new Set())) return
  await mutate(() => updateBusinessField(b.slug, field.name, { label: field.label, required: field.required, filterable: field.data_type === 'json' ? false : field.filterable !== false, default: field.default || '', ...(field.data_type === 'enum' ? { options: field.options } : {}) }))
}
async function removeField(field: BusinessTypeField) { const b = selected.value; if (!b) return; try { await confirmAction(`删除字段“${field.name}”？该字段的已存数据将永久移除。`, '删除字段', { type: 'warning' }) } catch { return }; await mutate(() => deleteBusinessField(b.slug, field.name)) }
async function removeType() { const b = selected.value; if (!b) return; try { await confirmAction(`删除业务类型“${b.name}”？仅无采集源绑定、无数据的自定义类型可以删除。`, '删除业务类型', { type: 'warning' }) } catch { return }; await mutate(() => deleteBusinessType(b.slug)) }
onMounted(() => { load() })
</script>

<style scoped>
.business-page { padding: 24px; }
.page-heading, .detail-heading, .actions { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
h1, h2, h3 { margin: 0; } h1 { font-size: 24px; } h2 { font-size: 20px; } h2 small { margin-left: 8px; font-size: 13px; color: var(--text-secondary); }
p, .helper { color: var(--text-secondary); font-size: 13px; line-height: 1.6; } .type-helper { margin: 6px 0 0; }
.registry-layout { display: grid; grid-template-columns: 245px minmax(0, 1fr); gap: 20px; margin-top: 24px; align-items: start; } .type-list { display: grid; gap: 10px; }
.type-list button { display: flex; flex-wrap: wrap; gap: 10px; text-align: left; border: 1px solid var(--border-color); border-radius: 8px; padding: 16px; background: var(--bg-color); color: inherit; cursor: pointer; } .type-list button.selected { border-color: var(--color-primary, #6366f1); background: var(--surface-hover); } .type-list small { flex-basis: 100%; color: var(--text-secondary); }
.type-detail { min-width: 0; } .detail-heading { margin-bottom: 18px; } .metadata { display: grid; grid-template-columns: 1fr 2fr; gap: 16px; }
.field-table { overflow-x: auto; margin-top: 16px; } code { margin-right: 8px; } .field-name-cell small { display: block; margin-top: 4px; color: var(--text-secondary); } .muted { display: block; color: var(--text-secondary); font-size: 11px; }
.options-editor { margin-top: 8px; } .options-editor.compact { min-width: 190px; } .options-tags { display: flex; flex-wrap: wrap; gap: 4px; margin-bottom: 6px; } .option-line { display: flex; align-items: center; gap: 6px; margin: 5px 0; } .option-line .r-input { min-width: 0; flex: 1; } .initial-flags { display: flex; flex-wrap: wrap; gap: 10px; align-items: center; }
.initial-field { display: grid; grid-template-columns: 1fr 1fr 170px minmax(160px, 1fr) minmax(140px, 1fr) auto; gap: 12px; align-items: start; margin-bottom: 14px; } .initial-field > .options-editor { grid-column: 1 / -2; }
@media (max-width: 900px) { .registry-layout, .metadata { grid-template-columns: 1fr; } .type-list { grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); } .page-heading { align-items: start; flex-wrap: wrap; } .initial-field { grid-template-columns: 1fr 1fr; } .initial-field > .options-editor { grid-column: 1 / -1; } }
</style>
