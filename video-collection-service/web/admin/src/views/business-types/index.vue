<template>
  <div class="business-page" v-loading="loading">
    <header class="page-heading">
      <div><h1>业务类型</h1><p>为采集内容配置字段，在规则工坊和 Webhook 中选择业务类型。</p></div>
      <div class="actions"><r-button @click="load()">刷新</r-button><r-button type="primary" :disabled="!canManage" @click="openCreate">新建业务类型</r-button></div>
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
        <r-alert title="系统字段不可删除或改类型；名称、类型与必填语义保持不变。可添加自定义字段。" type="info" :closable="false" />
        <p v-if="selected.is_system" class="helper">自定义字段随采集记录保存，系统内容继续使用现有入库流程。</p>
        <p v-else class="helper">字段名和类型创建后不可修改。删除字段会永久移除该字段的已存数据；类型仅在没有采集源绑定或数据时可删除。</p>
        <div class="field-table"><r-table :data="selected.fields" border>
          <r-table-column label="字段名" min-width="140"><template #default="{ row }"><code>{{ row.name }}</code><r-tag v-if="row.is_system" size="small" type="info">系统</r-tag></template></r-table-column>
          <r-table-column prop="data_type" label="类型" width="110" />
          <r-table-column label="显示名称" min-width="150"><template #default="{ row }"><r-input v-model="row.label" :disabled="!canManage" /></template></r-table-column>
          <r-table-column label="必填" width="80"><template #default="{ row }"><r-checkbox v-model="row.required" :disabled="row.is_system || !canManage" :aria-label="`${row.name} 必填`" /></template></r-table-column>
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
          <r-input v-model="field.name" placeholder="字段名，例如 title" :aria-label="`字段 ${i + 1} 名称`" />
          <r-input v-model="field.label" placeholder="显示名称" :aria-label="`字段 ${i + 1} 显示名称`" />
          <r-select v-model="field.data_type" :aria-label="`字段 ${i + 1} 类型`"><r-option v-for="kind in dataTypes" :key="kind" :value="kind" :label="kind" /></r-select>
          <r-checkbox v-model="field.required">必填</r-checkbox><r-button type="danger" link @click="draft.fields.splice(i, 1)">移除</r-button>
        </div>
      </r-form>
      <template #footer><r-button @click="createVisible = false">取消</r-button><r-button type="primary" :loading="saving" @click="create">创建</r-button></template>
    </r-dialog>

    <r-dialog v-model="fieldVisible" title="添加字段" width="480px">
      <r-form label-position="top">
        <r-form-item label="字段名（创建后不可修改）" required><r-input v-model="fieldDraft.name" placeholder="小写字母、数字、下划线，以字母开头" maxlength="48" /></r-form-item>
        <r-form-item label="显示名称"><r-input v-model="fieldDraft.label" /></r-form-item>
        <r-form-item label="数据类型"><r-select v-model="fieldDraft.data_type"><r-option v-for="kind in dataTypes" :key="kind" :value="kind" :label="kind" /></r-select></r-form-item>
        <r-checkbox v-model="fieldDraft.required">必填（后续采集必须提供值）</r-checkbox>
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
import type { BusinessType, BusinessTypeField, BusinessTypeInput, BusinessDataType } from '@/api/businessTypes'

const user = useUserStore()
const canManage = computed(() => ['super_admin', 'admin'].includes(user.userInfo?.role || ''))
const types = ref<BusinessType[]>([]), selected = ref<BusinessType | null>(null)
const loading = ref(false), saving = ref(false), createVisible = ref(false), fieldVisible = ref(false)
const dataTypes: BusinessDataType[] = ['text', 'integer', 'real', 'boolean', 'json']
const draft = ref<BusinessTypeInput>({ slug: '', name: '', description: '', fields: [] })
const fieldDraft = ref(newBusinessField())
function select(item: BusinessType) { selected.value = JSON.parse(JSON.stringify(item)) }
async function load(slug = selected.value?.slug) {
  loading.value = true
  try {
    types.value = (await listBusinessTypes()).data || []
    const item = types.value.find(item => item.slug === slug) || types.value[0]
    selected.value = item ? JSON.parse(JSON.stringify(item)) : null
  } finally { loading.value = false }
}
function openCreate() { draft.value = { slug: '', name: '', description: '', fields: [] }; createVisible.value = true }
function openField() { fieldDraft.value = newBusinessField(); fieldDraft.value.sort_order = selected.value?.fields.length || 0; fieldVisible.value = true }
async function mutate(action: () => Promise<unknown>, slug = selected.value?.slug) {
  saving.value = true
  try { await action(); await load(slug); notify('已保存', 'success'); return true } catch { return false } finally { saving.value = false }
}
async function create() {
  if (!draft.value.name.trim() || !/^[a-z][a-z0-9_]{1,47}$/.test(draft.value.slug) || draft.value.slug.startsWith('biz_')) { notify('请填写名称与合法的类型标识', 'warning'); return }
  draft.value.fields.forEach((field, i) => { field.sort_order = i })
  if (await mutate(() => createBusinessType(draft.value), draft.value.slug)) createVisible.value = false
}
async function saveMetadata() { const b = selected.value; if (b) await mutate(() => updateBusinessType(b.slug, { name: b.name, description: b.description })) }
async function addField() { const b = selected.value; if (b && await mutate(() => addBusinessField(b.slug, fieldDraft.value))) fieldVisible.value = false }
async function saveField(field: BusinessTypeField) { const b = selected.value; if (b) await mutate(() => updateBusinessField(b.slug, field.name, { label: field.label, required: field.required })) }
async function removeField(field: BusinessTypeField) {
  const b = selected.value; if (!b) return
  try { await confirmAction(`删除字段“${field.name}”？该字段的已存数据将永久移除。`, '删除字段', { type: 'warning' }) } catch { return }
  await mutate(() => deleteBusinessField(b.slug, field.name))
}
async function removeType() {
  const b = selected.value; if (!b) return
  try { await confirmAction(`删除业务类型“${b.name}”？仅无采集源绑定、无数据的自定义类型可以删除。`, '删除业务类型', { type: 'warning' }) } catch { return }
  await mutate(() => deleteBusinessType(b.slug))
}
onMounted(() => { load() })
</script>

<style scoped>
.business-page { padding: 24px; }
.page-heading, .detail-heading, .actions { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
h1, h2, h3 { margin: 0; } h1 { font-size: 24px; } h2 { font-size: 20px; } h2 small { margin-left: 8px; font-size: 13px; color: var(--text-secondary); }
p, .helper { color: var(--text-secondary); font-size: 13px; line-height: 1.6; }
.registry-layout { display: grid; grid-template-columns: 245px minmax(0, 1fr); gap: 20px; margin-top: 24px; align-items: start; }
.type-list { display: grid; gap: 10px; }
.type-list button { display: flex; flex-wrap: wrap; gap: 10px; text-align: left; border: 1px solid var(--border-color); border-radius: 8px; padding: 16px; background: var(--bg-color); color: inherit; cursor: pointer; }
.type-list button.selected { border-color: var(--color-primary, #6366f1); background: var(--surface-hover); }
.type-list small { flex-basis: 100%; color: var(--text-secondary); }
.type-detail { min-width: 0; } .detail-heading { margin-bottom: 18px; }
.metadata { display: grid; grid-template-columns: 1fr 2fr; gap: 16px; }
.field-table { overflow-x: auto; margin-top: 16px; } code { margin-right: 8px; }
.initial-field { display: grid; grid-template-columns: 1fr 1fr 130px 65px 48px; gap: 12px; align-items: center; margin-bottom: 12px; }
@media (max-width: 900px) { .registry-layout, .metadata { grid-template-columns: 1fr; } .type-list { grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); } .page-heading { align-items: start; flex-wrap: wrap; } .initial-field { grid-template-columns: 1fr 1fr; } }
</style>
