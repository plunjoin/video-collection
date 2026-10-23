<template>
  <div class="news-page">
    <r-card shadow="never" class="table-card">
      <div class="table-header">
        <div class="header-left">
          <span class="page-title">动漫资讯内容管理</span>
          <span class="sub-desc">发布与维护前台资讯频道文章，支持草稿/发布状态与置顶推荐</span>
        </div>
        <div class="header-right">
          <r-select
            v-model="filterStatus"
            placeholder="状态筛选"
            style="width: 120px"
            @change="handleFilterChange"
          >
            <r-option label="全部状态" value="" />
            <r-option label="已发布" value="published" />
            <r-option label="草稿箱" value="draft" />
          </r-select>
          <r-input
            v-model="keyword"
            placeholder="搜索标题/摘要"
            style="width: 200px"
            clearable
            @keyup.enter="handleFilterChange"
            @clear="handleFilterChange"
          />
          <r-button v-if="!readOnly" type="primary" @click="openDialog()">
            <r-icon><Plus /></r-icon>新增资讯
          </r-button>
          <r-button @click="loadData" :loading="loading">
            <r-icon><RefreshRight /></r-icon>刷新
          </r-button>
        </div>
      </div>

      <div v-if="canBatch && selectedIds.length" class="batch-bar">
        <span>已选中 {{ selectedIds.length }} 条资讯（当前页）</span>
        <r-button type="primary" size="small" :disabled="loading || batching" @click="handleBatch('publish')">批量发布</r-button>
        <r-button size="small" :disabled="loading || batching" @click="handleBatch('draft')">批量设为草稿</r-button>
        <r-button type="danger" size="small" :disabled="loading || batching" @click="handleBatch('delete')">批量删除</r-button>
        <span v-if="batching" role="status">正在处理…</span>
      </div>

      <r-table :key="tableKey" :data="tableData" v-loading="loading || batching" border stripe style="width: 100%" @selection-change="handleSelectionChange">
        <r-table-column v-if="canBatch" type="selection" width="50" align="center" />
        <r-table-column prop="id" label="ID" width="70" align="center" />
        <r-table-column label="封面" width="90" align="center">
          <template #default="{ row }">
            <r-image
              v-if="row.cover"
              :src="row.cover"
              :preview-src-list="[row.cover]"
              preview-teleported
              fit="cover"
              class="cover-thumb"
            >
              <template #error>
                <div class="cover-fallback">无图</div>
              </template>
            </r-image>
            <div v-else class="cover-fallback">无图</div>
          </template>
        </r-table-column>
        <r-table-column prop="title" label="标题" min-width="200" show-overflow-tooltip>
          <template #default="{ row }">
            <div class="title-cell">
              <r-tag v-if="row.pinned" type="warning" size="small" effect="dark" class="pin-tag">置顶</r-tag>
              <span class="font-bold">{{ row.title }}</span>
            </div>
          </template>
        </r-table-column>
        <r-table-column prop="category" label="分类" width="110" align="center">
          <template #default="{ row }">
            <r-tag v-if="row.category" type="info" effect="plain">{{ row.category }}</r-tag>
            <span v-else class="text-gray-400">-</span>
          </template>
        </r-table-column>
        <r-table-column prop="source_name" label="来源" width="130" align="center" show-overflow-tooltip>
          <template #default="{ row }">
            <span>{{ row.source_name || '-' }}</span>
          </template>
        </r-table-column>
        <r-table-column label="原文" width="90" align="center">
          <template #default="{ row }">
            <a
              v-if="row.source_url"
              :href="row.source_url"
              target="_blank"
              rel="noopener noreferrer"
              class="source-link"
            >打开</a>
            <span v-else class="text-gray-400">-</span>
          </template>
        </r-table-column>
        <r-table-column prop="published_at" label="原文时间" width="160" align="center">
          <template #default="{ row }">
            <span class="date-text">{{ formatDate(row.published_at) }}</span>
          </template>
        </r-table-column>
        <r-table-column prop="author_name" label="作者" width="110" align="center">
          <template #default="{ row }">
            <span>{{ row.author_name || '-' }}</span>
          </template>
        </r-table-column>
        <r-table-column prop="status" label="状态" width="95" align="center">
          <template #default="{ row }">
            <r-tag :type="row.status === 'published' ? 'success' : 'info'">
              {{ row.status === 'published' ? '已发布' : '草稿' }}
            </r-tag>
          </template>
        </r-table-column>
        <r-table-column prop="like_count" label="点赞" width="75" align="center" />
        <r-table-column prop="created_at" label="发布时间" width="160" align="center">
          <template #default="{ row }">
            <span class="date-text">{{ formatDate(row.created_at) }}</span>
          </template>
        </r-table-column>
        <r-table-column v-if="!readOnly" label="操作" width="160" align="center" fixed="right">
          <template #default="{ row }">
            <r-button size="small" type="primary" plain @click="openDialog(row)">编辑</r-button>
            <r-button v-if="canBatch" size="small" type="danger" plain @click="handleDelete(row)">删除</r-button>
          </template>
        </r-table-column>
      </r-table>

      <div class="pagination-wrap" v-if="total > 0">
        <r-pagination
          v-model:current-page="page"
          v-model:page-size="pageSize"
          :page-sizes="[10, 20, 50, 100]"
          :total="total"
          @current-change="loadData"
          @size-change="loadData"
        />
      </div>
    </r-card>

    <!-- 新增/编辑对话框 -->
    <r-dialog
      v-model="dialogVisible"
      :title="editingId ? `编辑资讯 #${editingId}` : '新增资讯'"
      width="720px"
      top="6vh"
    >
      <r-form ref="formRef" :model="form" :rules="formRules" label-width="90px">
        <r-form-item label="标题" prop="title">
          <r-input v-model="form.title" maxlength="200" show-word-limit placeholder="资讯标题 (最多200字)" />
        </r-form-item>
        <r-form-item label="分类" prop="category">
          <r-input v-model="form.category" maxlength="50" placeholder="如：新番情报 / 制作动态 / 行业新闻" />
        </r-form-item>
        <r-form-item label="封面图" prop="cover">
          <r-input v-model="form.cover" placeholder="http(s):// 开头的图片地址，留空则不显示封面" />
        </r-form-item>
        <r-form-item label="来源">
          <r-input v-model="form.source_name" placeholder="采集来源名称（Webhook 写入，可改）" />
        </r-form-item>
        <r-form-item label="原文链接">
          <r-input v-model="form.source_url" placeholder="http(s):// 原文地址" />
        </r-form-item>
        <r-form-item label="原文时间">
          <r-input v-model="form.published_at" placeholder="如 2026-10-18T13:00:00-04:00" />
        </r-form-item>
        <r-form-item label="摘要" prop="summary">
          <r-input
            v-model="form.summary"
            type="textarea"
            :rows="2"
            maxlength="1000"
            show-word-limit
            placeholder="列表页展示的简短摘要 (最多1000字)"
          />
        </r-form-item>
        <r-form-item label="正文" prop="content">
          <r-input
            v-model="form.content"
            type="textarea"
            :rows="12"
            maxlength="50000"
            show-word-limit
            placeholder="纯文本内容，保留换行 (最多50000字)"
          />
        </r-form-item>
        <r-form-item label="发布状态">
          <r-radio-group v-model="form.status">
            <r-radio value="published">{{ isOperator ? '审核后发布' : '立即发布' }}</r-radio>
            <r-radio value="draft">存为草稿</r-radio>
          </r-radio-group>
        </r-form-item>
        <r-form-item label="置顶推荐">
          <r-switch v-model="form.pinned" active-text="置顶显示" inactive-text="常规排序" />
        </r-form-item>
      </r-form>
      <template #footer>
        <r-button @click="dialogVisible = false">取消</r-button>
        <r-button type="primary" :loading="submitting" @click="submitForm">{{ isOperator ? '提交审核' : '保存' }}</r-button>
      </template>
    </r-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, computed, onMounted } from 'vue'
import { useUserStore } from '@/store/user'
import { getNewsList, saveNews, deleteNews } from '@/api/content'
import { batchNews } from '@/api/admin'
import type { NewsBatchAction } from '@/api/admin'
import type { ContentItem } from '@/types'
import { notify, confirmAction } from '@/components/radix/feedback'
import type { FormInstance, FormRules }  from '@/components/radix/types'
import { Plus, RefreshRight } from '@/components/radix/icons'

const loading = ref(false)
const userStore = useUserStore()
const isOperator = computed(() => userStore.userInfo?.role === 'operator')
const readOnly = computed(() => userStore.userInfo?.role === 'observer')
const canBatch = computed(() => ['admin', 'super_admin'].includes(userStore.userInfo?.role || ''))
const selectedIds = ref<number[]>([])
const batching = ref(false)
const tableKey = ref(0)
const tableData = ref<ContentItem[]>([])
const total = ref(0)
const page = ref(1)
const pageSize = ref(20)
const filterStatus = ref('')
const keyword = ref('')

const dialogVisible = ref(false)
const submitting = ref(false)
const editingId = ref<number | null>(null)
const formRef = ref<FormInstance>()

const form = reactive({
  id: 0,
  title: '',
  summary: '',
  content: '',
  cover: '',
  category: '',
  source_url: '',
  source_name: '',
  published_at: '',
  status: 'published',
  pinned: false
})

const formRules: FormRules = {
  title: [{ required: true, message: '请输入资讯标题', trigger: 'blur' }],
  content: [{ required: true, message: '请输入正文内容', trigger: 'blur' }]
}

const formatDate = (val?: string) => {
  if (!val) return '-'
  return val.replace('T', ' ').substring(0, 19)
}

const loadData = async () => {
  selectedIds.value = []
  tableKey.value++
  loading.value = true
  try {
    const res = await getNewsList({
      page: page.value,
      page_size: pageSize.value,
      status: filterStatus.value || undefined,
      keyword: keyword.value.trim() || undefined
    })
    if (res.code === 1 && res.data) {
      tableData.value = res.data
      total.value = res.total ?? res.data.length
      const lastPage = Math.max(1, Math.ceil(total.value / pageSize.value))
      if (page.value > lastPage) {
        page.value = lastPage
        await loadData()
      }
    }
  } finally {
    loading.value = false
  }
}

const handleSelectionChange = (rows: ContentItem[]) => {
  selectedIds.value = rows.map(row => row.id)
}

const handleBatch = async (action: NewsBatchAction) => {
  if (!canBatch.value || batching.value || loading.value || !selectedIds.value.length) return
  const ids = [...selectedIds.value]
  const label = { publish: '发布', draft: '设为草稿', delete: '删除' }[action]
  batching.value = true
  try {
    if (action === 'delete') {
      try {
        await confirmAction(`确定删除选中的 ${ids.length} 条资讯吗？删除后无法恢复。`, '批量删除确认', {
          confirmButtonText: '确定删除', cancelButtonText: '取消', type: 'error'
        })
      } catch { return }
    }
    const res = await batchNews(ids, action)
    if (res.code === 1 && res.data) {
      notify(`已${label} ${res.data.count} 条资讯`, 'success')
      await loadData()
    }
  } catch { /* Request interceptor displays the error. */ }
  finally { batching.value = false }
}

const handleFilterChange = () => {
  page.value = 1
  loadData()
}

const openDialog = (row?: ContentItem) => {
  if (readOnly.value) return
  if (row) {
    editingId.value = row.id
    form.id = row.id
    form.title = row.title
    form.summary = row.summary
    form.content = row.content
    form.cover = row.cover
    form.category = row.category
    form.source_url = row.source_url || ''
    form.source_name = row.source_name || ''
    form.published_at = row.published_at || ''
    form.status = row.status
    form.pinned = row.pinned
  } else {
    editingId.value = null
    form.id = 0
    form.title = ''
    form.summary = ''
    form.content = ''
    form.cover = ''
    form.category = ''
    form.source_url = ''
    form.source_name = ''
    form.published_at = ''
    form.status = 'published'
    form.pinned = false
  }
  dialogVisible.value = true
}

const submitForm = async () => {
  if (readOnly.value || !formRef.value) return
  await formRef.value.validate(async (valid) => {
    if (!valid) return
    if (form.cover && !/^https?:\/\/.+/.test(form.cover)) {
      notify('封面必须为 http 或 https 开头的 URL', 'warning')
      return
    }
    submitting.value = true
    try {
      const res = await saveNews({ ...form })
      if (res.code === 1) {
        notify(res.msg || '保存成功', 'success')
        dialogVisible.value = false
        loadData()
      } else {
        notify(res.error || res.msg || '保存失败', 'error')
      }
    } finally {
      submitting.value = false
    }
  })
}

const handleDelete = (row: ContentItem) => {
  if (!canBatch.value) return
  confirmAction(`确定要删除资讯 [${row.title}] 吗？删除后前台将不可见。`, '删除确认', {
    confirmButtonText: '确定删除',
    cancelButtonText: '取消',
    type: 'error'
  }).then(async () => {
    const res = await deleteNews(row.id)
    if (res.code === 1) {
      notify('已删除资讯', 'success')
      loadData()
    } else {
      notify(res.error || res.msg || '删除失败', 'error')
    }
  }).catch(() => {})
}

onMounted(() => {
  loadData()
})
</script>

<style scoped lang="scss">
.news-page {
  .batch-bar {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 8px;
    padding: 10px 12px;
    margin-bottom: 12px;
    border-radius: var(--radius-xs);
    background: var(--bg-hover);
    font-size: 12px;
  }
  .table-card {
    .table-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 12px;
      flex-wrap: wrap;
      gap: 8px;

      .header-left {
        display: flex;
        flex-direction: column;
        gap: 2px;

        .page-title {
          font-size: 13px;
          font-weight: 700;
          letter-spacing: -0.02em;
          color: var(--text-primary);
        }
        .sub-desc {
          font-size: 10px;
          color: var(--text-secondary);
        }
      }

      .header-right {
        display: flex;
        gap: 6px;
        flex-wrap: wrap;
      }
    }

    .cover-thumb {
      width: 52px;
      height: 36px;
      border-radius: var(--radius-xs);
    }

    .cover-fallback {
      width: 52px;
      height: 36px;
      border-radius: var(--radius-xs);
      background: rgba(20, 32, 57, 0.04);
      color: var(--text-secondary);
      font-size: 10px;
      display: flex;
      align-items: center;
      justify-content: center;
      margin: 0 auto;
    }

    .title-cell {
      display: flex;
      align-items: center;
      gap: 6px;

      .pin-tag {
        flex-shrink: 0;
      }
    }

    .date-text {
      font-size: 10px;
      color: var(--text-secondary);
    }

    .source-link {
      font-size: 12px;
      color: var(--color-primary, #3b82f6);
      text-decoration: none;
    }
    .source-link:hover {
      text-decoration: underline;
    }

    .pagination-wrap {
      display: flex;
      justify-content: flex-end;
      margin-top: 10px;
    }
  }
}
</style>
