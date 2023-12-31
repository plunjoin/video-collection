<template>
  <div class="sources-page">
    <el-card shadow="never" class="table-card">
      <!-- 头部操作区 -->
      <div class="table-header">
        <div class="header-left">
          <span class="page-title">采集点 / 节点配置与管理</span>
          <span class="sub-desc">支持 MacCMS v10 JSON、XML、RSS 及自定义 RESTful 接口采集</span>
        </div>
        <div class="header-right">
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
            <el-tag :type="getTypeTag(row.type)">{{ (row.type || 'json').toUpperCase() }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="collect_hours" label="增量策略" width="110" align="center">
          <template #default="{ row }">
            <span>{{ row.collect_hours || 24 }} 小时</span>
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
            <el-button size="small" type="primary" plain @click="handleCollect(row, 24)">
              24h增量
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
      width="600px"
      destroy-on-close
    >
      <el-form ref="formRef" :model="form" :rules="formRules" label-width="110px">
        <el-form-item label="节点名称" prop="name">
          <el-input v-model="form.name" placeholder="例如：自有片库 / 已授权数据源" />
        </el-form-item>
        <el-form-item label="接口协议类型" prop="type">
          <el-radio-group v-model="form.type">
            <el-radio value="json">MacCMS JSON (默认)</el-radio>
            <el-radio value="xml">MacCMS XML</el-radio>
            <el-radio value="rss">RSS 2.0</el-radio>
            <el-radio value="custom">通用 RESTful</el-radio>
          </el-radio-group>
        </el-form-item>
        <el-form-item label="API 接口地址" prop="api">
          <el-input
            v-model="form.api"
            placeholder="例如：https://api.example.com/api.php/provide/vod/"
          />
        </el-form-item>
        <el-form-item label="默认增量周期" prop="collect_hours">
          <el-input-number v-model="form.collect_hours" :min="1" :max="168" />
          <span style="margin-left: 10px; color: #94a3b8; font-size: 12px;">小时</span>
        </el-form-item>
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
  saveSource,
  deleteSource,
  testSource,
  triggerCollect,
  triggerCollectAll
} from '@/api/admin'
import type { SourceConfig } from '@/types'
import { ElMessage, ElMessageBox, type FormInstance, type FormRules } from 'element-plus'
import { Plus, Refresh, ArrowDown, RefreshRight } from '@element-plus/icons-vue'

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
      tableData.value = res.data.map((item: any) => ({
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
    editingId.value = row.id
    form.id = row.id
    form.name = row.name
    form.api = row.api
    form.type = row.type
    form.collect_hours = row.collect_hours || 24
    form.active = row.active !== undefined ? row.active : row.enabled !== false
  } else {
    editingId.value = null
    form.id = 'src_' + Date.now()
    form.name = ''
    form.api = ''
    form.type = 'json'
    form.collect_hours = 24
    form.active = true
  }
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
      await saveSource({
        ...form,
        active: form.active,
        enabled: form.active
      } as any)
      ElMessage.success('节点配置保存成功，关联视频节点名称已同步更新')
      dialogVisible.value = false
      loadData()
    } finally {
      submitting.value = false
    }
  })
}

const handleCollect = async (row: SourceConfig, hours: number) => {
  const modeText = hours === 0 ? '全量历史' : '近24小时增量'
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
    const res = await testSource({
      api: row.api,
      type: row.type
    })
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
  await handleTest(form as SourceConfig)
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

onMounted(() => {
  loadData()
})
</script>

<style scoped lang="scss">
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
