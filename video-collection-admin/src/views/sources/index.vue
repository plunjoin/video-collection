<template>
  <div class="sources-page">
    <el-card shadow="never" class="table-card">
      <!-- 头部操作区 -->
      <div class="table-header">
        <div class="header-left">
          <span class="page-title">采集点 / 节点配置与管理</span>
          <span class="sub-desc">按规则配置请求与响应，支持模板、自定义映射和通用采集</span>
        </div>
        <div class="header-right">
          <el-button @click="$router.push('/collection-rules')">通用采集规则工作台</el-button>
          <el-button type="primary" @click="openEditDialog()">
            <el-icon><Plus /></el-icon>新增节点
          </el-button>
          <el-dropdown trigger="click" @command="handleCollectAll">
            <el-button type="success">
              <el-icon><Refresh /></el-icon>一键全网采集<el-icon class="el-icon--right"><ArrowDown /></el-icon>
            </el-button>
            <template #dropdown>
              <el-dropdown-menu>
                <el-dropdown-item :command="24">近 24 小时增量同步</el-dropdown-item>
                <el-dropdown-item :command="0" divided style="color: #e6a23c;">全量历史补全 (耗时较长)</el-dropdown-item>
              </el-dropdown-menu>
            </template>
          </el-dropdown>
          <el-button @click="loadData" :loading="loading">
            <el-icon><RefreshRight /></el-icon>刷新
          </el-button>
        </div>
      </div>

      <!-- 表格内容 -->
      <el-table :data="tableData" v-loading="loading" border stripe style="width: 100%">
        <el-table-column prop="id" label="标识 ID" width="130" />
        <el-table-column prop="name" label="节点名称 (采集源)" min-width="150">
          <template #default="{ row }">
            <span class="font-bold">{{ row.name }}</span>
          </template>
        </el-table-column>
        <el-table-column prop="api" label="接口地址" min-width="260" show-overflow-tooltip>
          <template #default="{ row }">
            <el-link :href="row.api" target="_blank" type="primary" :underline="false">
              {{ row.api }}
            </el-link>
          </template>
        </el-table-column>
        <el-table-column prop="type" label="协议类型" width="100" align="center">
          <template #default="{ row }">
            <el-tag :type="getTypeTag(row.type)">{{ row.filter?.collector?.format || row.type }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="collect_hours" label="增量策略" width="110" align="center">
          <template #default="{ row }">
            <span>{{ row.collect_hours === 0 ? '全量' : `${row.collect_hours ?? 24} 小时` }}</span>
          </template>
        </el-table-column>
        <el-table-column prop="active" label="状态" width="90" align="center">
          <template #default="{ row }">
            <el-switch
              v-model="row.active"
              @change="handleStatusChange(row)"
              inline-prompt
              active-text="开"
              inactive-text="关"
            />
          </template>
        </el-table-column>
        <el-table-column label="快捷采集" width="180" align="center">
          <template #default="{ row }">
            <el-button size="small" type="primary" plain @click="handleCollect(row, row.collect_hours ?? 24)">
              按配置
            </el-button>
            <el-button size="small" type="warning" plain @click="handleCollect(row, 0)">
              全量补全
            </el-button>
          </template>
        </el-table-column>
        <el-table-column label="管理操作" width="200" align="center" fixed="right">
          <template #default="{ row }">
            <el-button size="small" type="info" plain @click="handleTest(row)">测试</el-button>
            <el-button size="small" type="primary" @click="openEditDialog(row)">编辑</el-button>
            <el-button size="small" type="danger" @click="handleDelete(row)">删除</el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <!-- 新增/编辑采集点模态框 -->
    <el-dialog
      v-model="dialogVisible"
      :title="editingId ? '编辑采集节点' : '新增采集节点'"
      width="min(900px, 95vw)"
      destroy-on-close
    >
      <el-form ref="formRef" :model="form" :rules="formRules" label-width="110px">
        <el-form-item label="节点名称" prop="name">
          <el-input v-model="form.name" placeholder="例如：自有片库 / 已授权数据源" />
        </el-form-item>
        <el-form-item label="规则模板">
          <el-select v-model="templateID" placeholder="选择模板作为起点" @change="applyTemplate">
            <el-option v-for="item in templates" :key="item.id" :label="item.name" :value="item.id" />
          </el-select>
          <p class="config-hint">{{ templates.find(t => t.id === templateID)?.description || '现有规则可直接编辑；模板只在选择时复制。' }}</p>
        </el-form-item>
        <el-form-item label="API 接口地址" prop="api">
          <el-input
            v-model="form.api"
            placeholder="例如：https://api.example.com/api.php/provide/vod/"
          />
        </el-form-item>
        <el-form-item label="默认增量周期" prop="collect_hours">
          <el-input-number v-model="form.collect_hours" :min="0" :max="168" />
          <span style="margin-left: 10px; color: #94a3b8; font-size: 12px;">小时</span>
        </el-form-item>
        <el-form-item label="页数上限"><el-input-number v-model="form.page_limit" :min="1" :max="10000" /><span class="config-hint">全量采集也遵守此上限；旧配置 0 表示不限页数。</span></el-form-item>
        <el-form-item label="请求超时"><el-input-number v-model="form.timeout_sec" :min="1" :max="60" /><span class="config-hint">秒</span></el-form-item>
        <el-form-item label="失败重试"><el-input-number v-model="form.retry_count" :min="0" :max="3" /></el-form-item>
        <el-form-item label="请求间隔"><el-input-number v-model="form.interval_ms" :min="0" :max="10000" /><span class="config-hint">毫秒</span></el-form-item>
        <el-form-item label="请求头"><el-input v-model="headersText" type="textarea" :rows="3" placeholder='{"Authorization":"Bearer ..."}' /></el-form-item>
        <el-form-item label="固定参数"><el-input v-model="paramsText" type="textarea" :rows="3" placeholder='{"limit":"50"}' /></el-form-item>
        <el-form-item label="采集规则">
          <el-input v-model="ruleText" type="textarea" :rows="12" />
          <p class="config-hint">支持 GET / POST、body、query 和 mapping。query 支持 {page}、{hours}、{action}、{type_id}、{keyword}、{ids}；mapping 支持 data.items、images.0.url 等路径。未配置的参数不会自动添加。</p>
        </el-form-item>
        <el-collapse><el-collapse-item title="分类绑定与清洗规则" name="advanced">
          <el-form-item label="分类绑定"><el-input v-model="categoriesText" type="textarea" :rows="4" /></el-form-item>
          <el-form-item label="过滤与清洗"><el-input v-model="filterText" type="textarea" :rows="6" /></el-form-item>
        </el-collapse-item></el-collapse>
        <el-form-item label="启用状态">
          <el-switch v-model="form.active" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="info" :loading="testing" @click="testCurrentForm">连通性测试</el-button>
        <el-button type="primary" :loading="submitting" @click="submitForm">保存节点配置</el-button>
      </template>
    </el-dialog>

    <!-- 连通性测试结果弹窗 -->
    <el-dialog v-model="testResultVisible" title="采集点连通性测试结果" width="550px">
      <div v-loading="testing" class="test-result-box">
        <el-result
          :icon="testSuccess ? 'success' : 'error'"
          :title="testSuccess ? '连接探测成功' : '探测失败'"
          :sub-title="testMsg"
        >
          <template #extra v-if="testSuccess">
            <div class="result-details">
              <div class="detail-item">
                <span class="label">识别到分类数：</span>
                <el-tag type="success">{{ testData.classes_total || 0 }} 个</el-tag>
              </div>
              <div class="detail-item" v-if="testData.samples && testData.samples.length">
                <span class="label">抓取样本片名：</span>
                <div class="sample-tags">
                  <el-tag
                    v-for="(name, idx) in testData.samples"
                    :key="idx"
                    size="small"
                    type="info"
                  >
                    {{ name }}
                  </el-tag>
                </div>
              </div>
            </div>
          </template>
        </el-result>
      </div>
    </el-dialog>
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
import { ElMessage, ElMessageBox, type FormInstance, type FormRules } from 'element-plus'
import { Plus, Refresh, ArrowDown, RefreshRight } from '@element-plus/icons-vue'

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
function payload(): Partial<SourceConfig> {
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
      return 'primary'
    case 'xml':
      return 'success'
    case 'rss':
      return 'warning'
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
  if (row) {
    Object.keys(form).forEach(key => delete (form as any)[key])
    Object.assign(form, JSON.parse(JSON.stringify(row)))
    editingId.value = row.id
    form.id = row.id
    form.name = row.name
    form.api = row.api
    form.type = row.type === 'custom' ? 'custom_json' : row.type
    form.collect_hours = row.collect_hours ?? 24
    form.active = row.active !== undefined ? row.active : row.enabled !== false
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
    ElMessage.success(`节点 [${row.name}] 状态已更新`)
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
      ElMessage.success('节点配置保存成功，关联视频节点名称已同步更新')
      dialogVisible.value = false
      loadData()
    } catch (err) {
      if (err instanceof SyntaxError) ElMessage.error('JSON 格式错误，请检查规则、请求头和参数')
      else if (err instanceof Error && !('response' in err)) ElMessage.error(err.message)
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
      ElMessage.success(`已为 [${row.name}] 启动 ${modeText} 采集任务`)
    }
  } catch (e) {}
}

const handleCollectAll = async (hours: number) => {
  const modeText = hours === 0 ? '全量历史' : '近24小时增量'
  ElMessageBox.confirm(
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
      ElMessage.success(res.msg || '全网并发采集任务已启动')
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
    ElMessage.warning('请先填写 API 接口地址')
    return
  }
  try { await handleTest(payload() as SourceConfig) } catch (err) { ElMessage.error(err instanceof Error ? err.message : '配置格式错误') }
}

const handleDelete = (row: SourceConfig) => {
  ElMessageBox.confirm(`确定要删除采集点 [${row.name}] 吗？删除后将不再同步此源。`, '删除确认', {
    confirmButtonText: '确定删除',
    cancelButtonText: '取消',
    type: 'error'
  }).then(async () => {
    await deleteSource(row.id)
    ElMessage.success('已删除采集点')
    loadData()
  }).catch(() => {})
}

onMounted(async () => {
  await Promise.all([loadData(), getCollectionTemplates().then(res => { templates.value = res.data || [] })])
})
</script>

<style scoped lang="scss">
.config-hint { margin: 6px 10px; color: var(--text-secondary); font-size: 12px; line-height: 1.6; }
.sources-page {
  .table-card {
    border-radius: 12px;
    border: 1px solid var(--border-color);

    .table-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 20px;
      flex-wrap: wrap;
      gap: 12px;

      .header-left {
        display: flex;
        flex-direction: column;
        gap: 4px;

        .page-title {
          font-size: 16px;
          font-weight: 700;
          color: var(--text-primary);
        }
        .sub-desc {
          font-size: 12px;
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
