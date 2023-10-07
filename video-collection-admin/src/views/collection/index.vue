<template>
  <div class="collection-studio">
    <header class="studio-header">
      <div><span class="eyebrow">COLLECTION STUDIO</span><h1>采集规则工作台</h1><p>从数据来源到内容入库，一套规则，逐步验证。</p></div>
      <div class="actions"><el-button @click="$router.push('/sources')">视频协议节点</el-button><el-button @click="$router.push('/scheduler')">定时调度</el-button><el-button @click="$router.push('/logs')">运行日志</el-button><el-button type="primary" @click="createRule('api')">新建规则</el-button></div>
    </header>
    <div class="studio-layout">
      <aside class="rule-library">
        <div class="library-title"><strong>我的规则</strong><el-button text :loading="loading" @click="loadRules">刷新</el-button></div>
        <el-input v-model="search" placeholder="搜索规则名称" clearable />
        <el-empty v-if="!filteredRules.length" description="从右侧模板开始配置" :image-size="70" />
        <button v-for="rule in filteredRules" :key="rule.id" class="rule-item" :class="{ selected: form.id === rule.id }" @click="editRule(rule)">
          <span>{{ rule.name }}</span><small>{{ inputLabel(rule.filter.pipeline.input) }} · {{ targetLabel(rule.filter.pipeline.target) }}</small>
          <small :class="{ enabled: rule.enabled }">{{ rule.enabled ? '已加入自动调度' : '仅手动运行' }}</small>
        </button>
        <el-divider /><p class="helper">旧 MacCMS / XML / RSS 节点在“视频协议节点”中管理。这里配置可复用的通用规则。</p>
      </aside>
      <main class="workspace">
        <div class="editor-heading"><div><h2>{{ form.name || '未命名采集规则' }}</h2><span class="helper">{{ isSaved ? '已保存规则' : '新规则' }} · {{ dirty ? '有未保存修改' : '配置已同步' }}</span></div><div class="actions"><el-button :disabled="!isSaved" @click="cloneRule">复制</el-button><el-button :disabled="!isSaved" @click="showRecords">查看结果</el-button><el-button :disabled="!isSaved" type="danger" plain @click="removeRule">删除</el-button></div></div>
        <el-steps :active="step" finish-status="success" simple class="steps"><el-step title="选择来源" /><el-step title="连接与提取" /><el-step title="映射与清洗" /><el-step title="预览与运行" /></el-steps>

        <section v-show="step === 0">
          <h3>数据从哪里来？</h3><p class="helper">来源与内容类型独立配置。先选来源，再决定保存为什么内容。</p>
          <div class="source-cards"><button v-for="item in sourceOptions" :key="item.value" :class="{ chosen: pipeline.input === item.value }" @click="pipeline.input = item.value"><span>{{ item.icon }}</span><strong>{{ item.label }}</strong><small>{{ item.description }}</small></button></div>
          <el-form label-position="top" class="basics">
            <el-form-item label="规则名称"><el-input v-model="form.name" placeholder="例如：产品资讯 / 旧站文章迁移" maxlength="100" /></el-form-item>
            <el-form-item label="内容类型"><el-radio-group v-model="pipeline.target"><el-radio-button value="record">通用数据</el-radio-button><el-radio-button value="article">文章</el-radio-button><el-radio-button value="video">视频</el-radio-button></el-radio-group></el-form-item>
          </el-form>
          <el-alert :title="targetHint" type="info" :closable="false" show-icon />
        </section>

        <section v-show="step === 1">
          <h3>{{ inputLabel(pipeline.input) }}配置</h3>
          <el-form label-position="top">
            <template v-if="pipeline.input === 'api' || pipeline.input === 'html'">
              <el-form-item :label="pipeline.input === 'api' ? '请求地址' : '列表页地址'"><el-input v-model="form.api" placeholder="https://example.com/articles" /></el-form-item>
              <template v-if="pipeline.input === 'api'">
                <div class="form-grid"><el-form-item label="请求方式"><el-select v-model="pipeline.request.method"><el-option label="GET" value="GET" /><el-option label="POST" value="POST" /></el-select></el-form-item><el-form-item label="列表在 JSON 中的路径"><el-input v-model="pipeline.request.list_path" placeholder="data.items；根数组填写 $" /></el-form-item></div>
                <el-form-item v-if="pipeline.request.method === 'POST'" label="请求体"><el-input v-model="pipeline.request.body" type="textarea" :rows="4" placeholder='{"category": "news"}' /></el-form-item>
              </template>
              <template v-else>
                <el-alert title="静态 HTML 采集：支持列表 → 详情 → 翻页；暂不执行网页 JavaScript。" :closable="false" />
                <div class="form-grid"><el-form-item label="列表条目 CSS"><el-input v-model="pipeline.html.item_selector" placeholder=".article-list .item" /></el-form-item><el-form-item label="详情链接 CSS（可选，相对每个条目）"><el-input v-model="pipeline.html.detail_selector" placeholder="a.title；留空则直接从列表提取" /></el-form-item><el-form-item label="下一页 CSS（可选）"><el-input v-model="pipeline.html.next_selector" placeholder="a.next" /></el-form-item></div>
                <p class="helper">配置详情链接后，字段从详情页提取。详情与翻页链接支持相对路径，须与列表同主机。</p>
              </template>
              <div class="form-grid"><el-form-item label="页码参数名（可选）"><el-input v-model="pipeline.request.page_param" placeholder="page；留空不按页码翻页" /></el-form-item><el-form-item label="起始页码"><el-input-number v-model="pipeline.request.start_page" :min="1" /></el-form-item></div>
              <p class="helper">页码参数追加到 URL；网页配置了“下一页 CSS”时优先跟随链接。</p>
              <el-collapse><el-collapse-item title="请求头与固定参数" name="request"><div class="form-grid"><el-form-item label="Headers（JSON 对象）"><el-input v-model="headersText" type="textarea" :rows="5" placeholder='{"Authorization":"Bearer ..."}' /></el-form-item><el-form-item label="Query 参数（JSON 对象）"><el-input v-model="paramsText" type="textarea" :rows="5" placeholder='{"limit":"50"}' /></el-form-item></div></el-collapse-item></el-collapse>
            </template>
            <template v-else-if="pipeline.input === 'database'">
              <div class="form-grid"><el-form-item label="数据库类型"><el-select v-model="pipeline.database.driver"><el-option v-for="driver in ['postgres', 'mysql', 'sqlite', 'sqlserver']" :key="driver" :label="dbNames[driver]" :value="driver" /></el-select></el-form-item><el-form-item label="服务端连接串环境变量"><el-input v-model="pipeline.database.dsn_env" placeholder="IMPORT_DATABASE_DSN" /></el-form-item></div>
              <el-alert title="连接串保存在后端环境变量中，规则只保存变量名。外部数据库请使用只读账号。" :closable="false" type="info" />
              <p class="helper">{{ dsnHint }}</p>
              <el-form-item label="读取 SQL（单条 SELECT，不带分号）"><el-input v-model="pipeline.database.query" type="textarea" :rows="6" placeholder="SELECT id, title, content FROM articles" /></el-form-item>
              <p class="helper">查询会作为子查询执行并限制记录数。需要排序时，请使用数据库允许放入子查询的语法。</p>
            </template>
            <template v-else>
              <label class="upload-zone"><strong>{{ uploading ? '正在上传…' : (pipeline.file.name || '选择 Excel / CSV 文件') }}</strong><span>.xlsx 或 UTF-8 .csv，最大 20 MB。旧 .xls 请先另存为 .xlsx。</span><input type="file" accept=".xlsx,.csv" :disabled="uploading" @change="onUpload" /></label>
              <div class="form-grid"><el-form-item label="工作表名称（Excel）"><el-input v-model="pipeline.file.sheet" placeholder="留空使用第一张工作表" /></el-form-item><el-form-item label="表头所在行"><el-input-number v-model="pipeline.file.header_row" :min="1" :max="100" /></el-form-item></div>
              <p class="helper">以表头列名映射字段，自动跳过空行。上传文件保留在服务端，重复运行使用同一份文件。</p>
            </template>
          </el-form>
        </section>

        <section v-show="step === 2">
          <div class="section-title"><div><h3>字段映射与清洗</h3><p class="helper">{{ mappingHint }}</p></div><el-button @click="pipeline.fields.push(field())">添加字段</el-button></div>
          <el-alert v-if="pipeline.target !== 'record'" :title="pipeline.target === 'article' ? '文章字段：title、content 必填；可选 summary、cover、category。文章保存为草稿。' : '视频字段：title 必填；可选 play_url、cover、content、category、year、actor、director、area、remarks。'" :closable="false" />
          <div class="mapping-table"><el-table :data="pipeline.fields" border>
            <el-table-column type="expand"><template #default="{ row }"><div class="cleaning"><div class="form-grid"><el-form-item label="空值默认值"><el-input v-model="row.default" /></el-form-item><el-form-item label="正则替换表达式（Go RE2）"><el-input v-model="row.pattern" placeholder="例如：广告词|推广词" /></el-form-item><el-form-item label="替换为"><el-input v-model="row.replacement" placeholder="留空表示删除匹配内容" /></el-form-item></div><el-checkbox v-model="row.trim">去除首尾空白</el-checkbox><el-checkbox v-model="row.strip_html">移除 HTML 标签</el-checkbox></div></template></el-table-column>
            <el-table-column label="目标字段" min-width="150"><template #default="{ row }"><el-input v-model="row.target" placeholder="title" /></template></el-table-column>
            <el-table-column :label="pipeline.input === 'html' ? 'CSS 选择器' : (pipeline.input === 'api' ? 'JSON 路径' : '来源列名')" min-width="180"><template #default="{ row }"><el-input v-model="row.selector" :placeholder="pipeline.input === 'html' ? 'h1 / $url' : 'title'" /></template></el-table-column>
            <el-table-column v-if="pipeline.input === 'html'" label="提取内容" min-width="140"><template #default="{ row }"><el-select v-model="row.attribute" filterable allow-create default-first-option><el-option v-for="attr in ['text', 'html', 'href', 'src', 'content']" :key="attr" :label="attr" :value="attr" /></el-select></template></el-table-column>
            <el-table-column label="必填" width="65"><template #default="{ row }"><el-checkbox v-model="row.required" :aria-label="`${row.target} 必填`" /></template></el-table-column>
            <el-table-column width="70"><template #default="{ $index }"><el-button type="danger" link @click="pipeline.fields.splice($index, 1)">删除</el-button></template></el-table-column>
          </el-table></div>
          <p class="helper">展开每行设置清洗规则，按“默认值 → 去 HTML → 正则替换 → 去空白 → 必填校验”执行。</p>
          <div class="form-grid"><el-form-item label="唯一标识字段"><el-select v-model="pipeline.key_field"><el-option v-for="f in pipeline.fields.filter(f => f.target)" :key="f.target" :label="f.target" :value="f.target" /></el-select></el-form-item><el-form-item label="遇到重复记录"><el-select v-model="pipeline.duplicate"><el-option label="更新已有记录" value="update" /><el-option label="跳过已有记录" value="skip" /></el-select></el-form-item></div>
          <p class="helper">同一规则、同一内容类型按唯一标识去重。建议使用来源 ID 或详情 URL。文章已发布或已隐藏时保留编辑结果；视频库仍按现有片名聚合。</p>
        </section>

        <section v-show="step === 3">
          <div class="section-title"><div><h3>先看样本，再运行</h3><p class="helper">最多读取 10 条样本，预览不写入内容库。</p></div><el-button type="primary" plain :loading="previewing" @click="preview">测试并预览</el-button></div>
          <el-alert v-if="previewError" :title="previewError" type="error" :closable="false" />
          <el-alert v-else-if="previewed" :title="`预览 ${samples.length} 条 · ${samples.filter(s => s.errors.length).length} 条校验失败`" :type="samples.some(s => s.errors.length) ? 'warning' : 'success'" :closable="false" />
          <el-empty v-if="!samples.length" :description="previewed ? '未提取到记录，请检查路径、选择器或来源数据' : '点击测试并预览，检查提取结果'" :image-size="70" />
          <template v-else><el-segmented v-model="sampleMode" :options="[{ label: '清洗结果', value: 'values' }, { label: '原始提取值', value: 'raw' }]" class="sample-mode" /><el-table :data="samples" border max-height="320"><el-table-column v-for="f in pipeline.fields" :key="f.target" :label="f.target" min-width="170" show-overflow-tooltip><template #default="{ row }">{{ row[sampleMode][f.target] }}</template></el-table-column><el-table-column label="校验" min-width="210"><template #default="{ row }"><span :class="{ invalid: row.errors.length }">{{ row.errors.join('；') || '通过' }}</span></template></el-table-column></el-table></template>
          <h3>运行策略</h3><div class="form-grid limits"><el-form-item label="每次最多记录"><el-input-number v-model="pipeline.max_records" :min="1" :max="10000" /></el-form-item><el-form-item label="每次最多页数"><el-input-number v-model="form.page_limit" :min="1" :max="100" /></el-form-item><el-form-item label="请求超时 / 秒"><el-input-number v-model="form.timeout_sec" :min="1" :max="60" /></el-form-item><el-form-item label="请求间隔 / 毫秒"><el-input-number v-model="form.interval_ms" :min="0" :max="10000" :step="100" /></el-form-item><el-form-item label="失败重试次数"><el-input-number v-model="form.retry_count" :min="0" :max="3" /></el-form-item><el-form-item label="加入全局自动调度"><el-switch v-model="form.enabled" /></el-form-item></div>
          <p class="helper">页数、重试、间隔仅作用于 HTTP 来源。数据库和文件按记录上限读取。通用规则每次按配置重新读取并去重，不使用旧视频接口的 h=24 参数。全局调度须在“定时调度”中开启。</p>
        </section>
        <footer class="editor-footer"><el-button :disabled="step === 0" @click="step--">上一步</el-button><div class="actions"><el-button :loading="saving" @click="save">保存规则</el-button><el-button v-if="step < 3" type="primary" @click="step++">下一步</el-button><el-button v-else type="primary" :loading="running" @click="run">保存并运行</el-button></div></footer>
      </main>
    </div>
    <el-dialog v-model="recordsVisible" title="采集结果" width="min(1100px, 95vw)"><p class="helper">通用数据保存在采集结果中；文章同步到资讯草稿，视频同步到视频仓库。</p><el-table :data="records" v-loading="recordsLoading" border><el-table-column prop="key" label="来源唯一标识" min-width="140" show-overflow-tooltip /><el-table-column v-for="key in recordColumns" :key="key" :label="key" min-width="180" show-overflow-tooltip><template #default="{ row }">{{ row.values[key] }}</template></el-table-column><el-table-column prop="content_id" label="内容 ID" width="100" /><el-table-column prop="updated_at" label="采集时间" min-width="190" /></el-table><el-pagination v-model:current-page="recordsPage" :page-size="20" :total="recordsTotal" layout="prev, pager, next, total" @current-change="loadRecords" /></el-dialog>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, onBeforeUnmount, ref, watch } from 'vue'
import { onBeforeRouteLeave } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import { getSources, saveSource, deleteSource, triggerCollect } from '@/api/admin'
import { collectionRecords, field, newRule, previewCollection, uploadCollection } from '@/api/collection'
import type { CollectedRecord, PipelineRule, PipelineSource, Sample } from '@/api/collection'

const sourceOptions: { value: PipelineRule['input']; label: string; icon: string; description: string }[] = [
  { value: 'api', label: '接口采集', icon: '{ }', description: 'JSON · GET / POST · 字段路径' },
  { value: 'html', label: '网页采集', icon: '</>', description: '列表 / 详情 · CSS · 翻页' },
  { value: 'database', label: '数据库导入', icon: 'DB', description: 'PostgreSQL / MySQL / SQLite / SQL Server' },
  { value: 'file', label: 'Excel / CSV', icon: '▦', description: '上传文件 · 工作表 · 按列映射' }
]
const dbNames: Record<string, string> = { postgres: 'PostgreSQL', mysql: 'MySQL', sqlite: 'SQLite', sqlserver: 'SQL Server' }
const form = ref<PipelineSource>(newRule())
const pipeline = computed(() => form.value.filter.pipeline)
const rules = ref<PipelineSource[]>([])
const step = ref(0), search = ref(''), loading = ref(false), saving = ref(false), running = ref(false), uploading = ref(false)
const headersText = ref('{}'), paramsText = ref('{}')
const snapshot = () => JSON.stringify([form.value, headersText.value, paramsText.value])
const savedSnapshot = ref(snapshot())
const dirty = computed(() => snapshot() !== savedSnapshot.value)
const isSaved = computed(() => rules.value.some(r => r.id === form.value.id))
const filteredRules = computed(() => rules.value.filter(r => r.name.toLowerCase().includes(search.value.toLowerCase())))
const inputLabel = (input: string) => sourceOptions.find(o => o.value === input)?.label || input
const targetLabel = (target: string) => ({ record: '通用数据', article: '文章', video: '视频' }[target] || target)
const targetHint = computed(() => ({ record: '保留自定义字段，保存到采集结果，适合爬虫数据与后续业务扩展。', article: '映射标题和正文，采集后生成资讯草稿，可通过资讯管理接口审核发布。', video: '映射片名、封面和播放链接，接入现有视频仓库与片名聚合逻辑。' }[pipeline.value.target]))
const mappingHint = computed(() => pipeline.value.input === 'html' ? '填写 CSS 选择器；$url 表示当前页面地址。href / src 会自动补全相对地址。' : pipeline.value.input === 'api' ? '支持 data.title 等点分路径与数组下标（如 images.0.url）。' : '来源列名必须与数据库列名或文件表头完全一致，可使用中文列名。')
const dsnHint = computed(() => ({ postgres: '格式：postgres://user:password@host:5432/database?sslmode=require', mysql: '格式：user:password@tcp(host:3306)/database', sqlite: '格式：file:/absolute/path/source.db?mode=ro', sqlserver: '格式：sqlserver://user:password@host:1433?database=database' }[pipeline.value.database.driver]))
const samples = ref<Sample[]>([]), previewed = ref(false), previewing = ref(false), previewError = ref('')
const sampleMode = ref('values')
let previewRevision = 0
watch([form, headersText, paramsText], () => { previewRevision++; samples.value = []; previewed.value = false; previewError.value = '' }, { deep: true, flush: 'sync' })

async function discardChanges() {
  if (!dirty.value) return true
  try { await ElMessageBox.confirm('当前修改尚未保存，确定放弃这些修改吗？', '未保存修改', { type: 'warning', confirmButtonText: '放弃修改', cancelButtonText: '继续编辑' }); return true } catch { return false }
}
function selectRule(rule: PipelineSource) {
  form.value = JSON.parse(JSON.stringify(rule))
  headersText.value = JSON.stringify(rule.headers || {}, null, 2)
  paramsText.value = JSON.stringify(rule.custom_params || {}, null, 2)
  step.value = 0; savedSnapshot.value = snapshot()
}
async function createRule(input: PipelineRule['input']) { if (await discardChanges()) selectRule(newRule(input)) }
async function editRule(rule: PipelineSource) { if (rule.id === form.value.id) return; if (await discardChanges()) selectRule(rule) }
function cloneRule() { form.value.id = 'rule_' + crypto.randomUUID(); form.value.name += '（副本）'; form.value.enabled = false; form.value.active = false; ElMessage.success('副本已创建，保存后可独立运行') }
async function loadRules() {
  loading.value = true
  try { const res = await getSources(); rules.value = (res.data || []).filter(s => s.type === 'pipeline') as unknown as PipelineSource[] } finally { loading.value = false }
}
function stringMap(text: string, label: string): Record<string, string> {
  const obj: unknown = JSON.parse(text || '{}')
  if (!obj || Array.isArray(obj) || typeof obj !== 'object' || Object.values(obj).some(v => typeof v !== 'string')) throw new Error(label + ' 必须是值为字符串的 JSON 对象')
  return obj as Record<string, string>
}
function payload() {
  const data = JSON.parse(JSON.stringify(form.value)) as PipelineSource
  data.headers = stringMap(headersText.value, 'Headers'); data.custom_params = stringMap(paramsText.value, 'Query 参数')
  data.active = data.enabled
  return data
}
async function save() {
  if (!form.value.name.trim()) { ElMessage.warning('请填写规则名称'); step.value = 0; return false }
  saving.value = true
  try { const data = payload(); await saveSource(data); form.value = data; savedSnapshot.value = snapshot(); await loadRules(); ElMessage.success('规则已保存'); return true }
  catch (e) { if (e instanceof SyntaxError) ElMessage.error('请求头或参数 JSON 格式不正确'); else if (e instanceof Error && e.message.includes('JSON 对象')) ElMessage.error(e.message); return false }
  finally { saving.value = false }
}
async function preview() {
  previewing.value = true; previewError.value = ''; const revision = previewRevision
  try { const res = await previewCollection(payload()); if (revision === previewRevision) { samples.value = res.data || []; previewed.value = true } }
  catch (e: any) { if (revision === previewRevision) previewError.value = e.response?.data?.error || e.message || '预览失败' }
  finally { previewing.value = false }
}
async function run() {
  running.value = true
  try { if (await save()) { await triggerCollect(form.value.id, 0); ElMessage.success('已启动采集，可在运行日志查看进度，完成后点击“查看结果”') } } finally { running.value = false }
}
async function removeRule() {
  try { await ElMessageBox.confirm(`删除规则“${form.value.name}”？已采集内容会保留。`, '删除规则', { type: 'warning' }) } catch { return }
  await deleteSource(form.value.id); await loadRules(); selectRule(newRule()); ElMessage.success('规则已删除')
}
async function onUpload(event: Event) {
  const input = event.target as HTMLInputElement; const file = input.files?.[0]; if (!file) return
  if (file.size > 20 * 1024 * 1024) { ElMessage.error('文件不能超过 20 MB'); input.value = ''; return }
  uploading.value = true; const ruleID = form.value.id
  try { const res = await uploadCollection(file); if (res.data && form.value.id === ruleID) Object.assign(pipeline.value.file, res.data) } finally { uploading.value = false; input.value = '' }
}
const recordsVisible = ref(false), recordsLoading = ref(false), records = ref<CollectedRecord[]>([]), recordsPage = ref(1), recordsTotal = ref(0)
const recordColumns = computed(() => [...new Set(records.value.flatMap(r => Object.keys(r.values)))])
async function loadRecords() { recordsLoading.value = true; try { const res = await collectionRecords(form.value.id, recordsPage.value); records.value = res.data || []; recordsTotal.value = res.total || 0 } finally { recordsLoading.value = false } }
async function showRecords() { recordsPage.value = 1; records.value = []; recordsVisible.value = true; await loadRecords() }
function beforeUnload(e: BeforeUnloadEvent) { if (dirty.value) { e.preventDefault(); e.returnValue = '' } }
onBeforeRouteLeave(discardChanges)
onMounted(() => { loadRules(); window.addEventListener('beforeunload', beforeUnload) })
onBeforeUnmount(() => window.removeEventListener('beforeunload', beforeUnload))
</script>

<style scoped lang="scss">
.collection-studio { max-width: 1600px; margin: auto; color: var(--text-primary); }
.studio-header, .editor-heading, .section-title, .editor-footer, .library-title { display: flex; justify-content: space-between; align-items: center; gap: 16px; }
.studio-header { margin-bottom: 24px; h1 { margin: 8px 0; font-size: 28px; letter-spacing: -1px; } p { margin: 0; color: var(--text-secondary); } }
.eyebrow { font-size: 11px; letter-spacing: 2px; font-weight: 700; color: #6366f1; }
.actions { display: flex; gap: 8px; flex-wrap: wrap; .el-button + .el-button { margin-left: 0; } }
.studio-layout { display: grid; grid-template-columns: 230px minmax(0, 1fr); gap: 20px; align-items: start; }
.rule-library, .workspace { background: var(--card-bg, #fff); border: 1px solid var(--border-color, #e2e8f0); border-radius: 16px; }
.rule-library { padding: 16px; .el-input { margin: 12px 0; } }
.rule-item { display: flex; flex-direction: column; width: 100%; gap: 7px; text-align: left; padding: 14px 12px; border: 1px solid transparent; border-radius: 10px; background: transparent; cursor: pointer; color: inherit; margin: 5px 0; overflow-wrap: anywhere; span { font-weight: 600; } small { color: var(--text-secondary); } .enabled { color: #059669; } &.selected { background: #eef2ff; border-color: #c7d2fe; color: #4338ca; } &:hover { background: #f5f7ff; } }
.workspace { padding: 24px; min-width: 0; }
.editor-heading { margin-bottom: 24px; h2 { font-size: 19px; margin: 0 0 6px; } }
.steps { margin-bottom: 28px; }
:deep(.el-step.is-simple .el-step__title) { max-width: none; white-space: nowrap; font-size: 13px; }
h3 { font-size: 16px; margin: 22px 0 10px; }
.helper { font-size: 12px; line-height: 1.8; color: var(--text-secondary, #64748b); }
.source-cards { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; margin: 22px 0; button { display: flex; flex-direction: column; align-items: flex-start; text-align: left; gap: 12px; border: 1px solid #e2e8f0; background: #fff; border-radius: 12px; padding: 20px 14px; cursor: pointer; color: #334155; span { font-size: 23px; color: #6366f1; height: 30px; } small { line-height: 1.6; color: #64748b; } &.chosen { border-color: #818cf8; background: #f5f3ff; box-shadow: 0 0 0 1px #818cf8; } } }
.form-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 0 18px; margin-top: 18px; }
.limits { grid-template-columns: repeat(3, minmax(0, 1fr)); }
.upload-zone { display: flex; flex-direction: column; align-items: center; gap: 15px; padding: 35px 15px; border: 1px dashed #a5b4fc; background: #f8faff; border-radius: 12px; margin: 20px 0; cursor: pointer; span { font-size: 12px; color: #64748b; } input { max-width: 100%; } }
.mapping-table { margin-top: 18px; overflow-x: auto; }
.cleaning { padding: 10px 22px 18px; background: #f8fafc; }
.editor-footer { border-top: 1px solid var(--border-color, #e2e8f0); margin-top: 28px; padding-top: 20px; }
.invalid { color: #dc2626; }.sample-mode { margin: 15px 0; }.el-pagination { margin-top: 20px; }
:global(html.dark .collection-studio .source-cards button), :global(html.dark .collection-studio .cleaning), :global(html.dark .collection-studio .upload-zone) { background: #151e30; color: #e2e8f0; border-color: #334155; }
:global(html.dark .collection-studio .rule-item.selected), :global(html.dark .collection-studio .source-cards button.chosen), :global(html.dark .collection-studio .rule-item:hover) { background: #262547; color: #c7d2fe; border-color: #818cf8; }
@media (max-width: 1150px) { .source-cards { grid-template-columns: repeat(2, minmax(0, 1fr)); } .limits { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
@media (min-width: 801px) and (max-width: 1250px) { .studio-layout { grid-template-columns: 1fr; }.rule-library { display: flex; flex-wrap: wrap; gap: 12px; align-items: center; max-height: 180px; overflow-y: auto; }.library-title { min-width: 150px; }.rule-library .el-input { width: 200px; margin: 0; }.rule-library :deep(.el-empty), .rule-library > .helper, .rule-library > .el-divider { display: none; }.rule-item { width: 210px; margin: 0; }.steps { padding: 16px; } }
@media (max-width: 800px) { .studio-layout { grid-template-columns: 1fr; }.rule-library { max-height: 240px; overflow-y: auto; }.workspace { padding: 16px; }.studio-header, .editor-heading { align-items: flex-start; flex-direction: column; }.form-grid { grid-template-columns: 1fr; }.steps { padding: 12px 6px; }:deep(.el-step__title) { font-size: 12px; } }
</style>
