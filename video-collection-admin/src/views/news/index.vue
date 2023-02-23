<template>
  <div class="news-page">
    <el-card shadow="never" class="table-card">
      <div class="table-header">
        <div class="header-left">
          <span class="page-title">动漫资讯内容管理</span>
          <span class="sub-desc">发布与维护前台资讯频道文章，支持草稿/发布状态与置顶推荐</span>
        </div>
        <div class="header-right">
          <el-select
            v-model="filterStatus"
            placeholder="状态筛选"
            style="width: 120px"
            @change="handleFilterChange"
          >
            <el-option label="全部状态" value="" />
            <el-option label="已发布" value="published" />
            <el-option label="草稿箱" value="draft" />
          </el-select>
          <el-input
            v-model="keyword"
            placeholder="搜索标题/摘要"
            style="width: 200px"
            clearable
            @keyup.enter="handleFilterChange"
            @clear="handleFilterChange"
          />
          <el-button type="primary" @click="openDialog()">
            <el-icon><Plus /></el-icon>新增资讯
          </el-button>
          <el-button @click="loadData" :loading="loading">
            <el-icon><RefreshRight /></el-icon>刷新
          </el-button>
        </div>
      </div>

      <el-table :data="tableData" v-loading="loading" border stripe style="width: 100%">
        <el-table-column prop="id" label="ID" width="70" align="center" />
        <el-table-column label="封面" width="90" align="center">
          <template #default="{ row }">
            <el-image
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
            </el-image>
            <div v-else class="cover-fallback">无图</div>
          </template>
        </el-table-column>
        <el-table-column prop="title" label="标题" min-width="200" show-overflow-tooltip>
          <template #default="{ row }">
            <div class="title-cell">
              <el-tag v-if="row.pinned" type="warning" size="small" effect="dark" class="pin-tag">置顶</el-tag>
              <span class="font-bold">{{ row.title }}</span>
            </div>
          </template>
        </el-table-column>
        <el-table-column prop="category" label="分类" width="110" align="center">
          <template #default="{ row }">
            <el-tag v-if="row.category" type="info" effect="plain">{{ row.category }}</el-tag>
            <span v-else class="text-gray-400">-</span>
          </template>
        </el-table-column>
        <el-table-column prop="author_name" label="作者" width="110" align="center">
          <template #default="{ row }">
            <span>{{ row.author_name || '-' }}</span>
          </template>
        </el-table-column>
        <el-table-column prop="status" label="状态" width="95" align="center">
          <template #default="{ row }">
            <el-tag :type="row.status === 'published' ? 'success' : 'info'">
              {{ row.status === 'published' ? '已发布' : '草稿' }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="like_count" label="点赞" width="75" align="center" />
        <el-table-column prop="created_at" label="发布时间" width="160" align="center">
          <template #default="{ row }">
            <span class="date-text">{{ formatDate(row.created_at) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="160" align="center" fixed="right">
          <template #default="{ row }">
            <el-button size="small" type="primary" plain @click="openDialog(row)">编辑</el-button>
            <el-button size="small" type="danger" plain @click="handleDelete(row)">删除</el-button>
          </template>
        </el-table-column>
      </el-table>

      <div class="pagination-wrap" v-if="total > pageSize">
        <el-pagination
          v-model:current-page="page"
          :total="total"
          :page-size="pageSize"
          layout="total, prev, pager, next"
          @current-change="loadData"
        />
      </div>
    </el-card>

    <!-- 新增/编辑对话框 -->
    <el-dialog
      v-model="dialogVisible"
      :title="editingId ? `编辑资讯 #${editingId}` : '新增资讯'"
      width="720px"
      top="6vh"
    >
      <el-form ref="formRef" :model="form" :rules="formRules" label-width="90px">
        <el-form-item label="标题" prop="title">
          <el-input v-model="form.title" maxlength="200" show-word-limit placeholder="资讯标题 (最多200字)" />
        </el-form-item>
        <el-form-item label="分类" prop="category">
          <el-input v-model="form.category" maxlength="50" placeholder="如：新番情报 / 制作动态 / 行业新闻" />
        </el-form-item>
        <el-form-item label="封面图" prop="cover">
          <el-input v-model="form.cover" placeholder="http(s):// 开头的图片地址，留空则不显示封面" />
        </el-form-item>
        <el-form-item label="摘要" prop="summary">
          <el-input
            v-model="form.summary"
            type="textarea"
            :rows="2"
            maxlength="1000"
            show-word-limit
            placeholder="列表页展示的简短摘要 (最多1000字)"
          />
        </el-form-item>
        <el-form-item label="正文" prop="content">
          <el-input
            v-model="form.content"
            type="textarea"
            :rows="12"
            maxlength="50000"
            show-word-limit
            placeholder="支持 HTML 富文本内容 (最多50000字)"
          />
        </el-form-item>
        <el-form-item label="发布状态">
          <el-radio-group v-model="form.status">
            <el-radio value="published">立即发布</el-radio>
            <el-radio value="draft">存为草稿</el-radio>
          </el-radio-group>
        </el-form-item>
        <el-form-item label="置顶推荐">
          <el-switch v-model="form.pinned" active-text="置顶显示" inactive-text="常规排序" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="submitting" @click="submitForm">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { getNewsList, saveNews, deleteNews } from '@/api/content'
import type { ContentItem } from '@/types'
import { ElMessage, ElMessageBox, type FormInstance, type FormRules } from 'element-plus'
import { Plus, RefreshRight } from '@element-plus/icons-vue'

const loading = ref(false)
const tableData = ref<ContentItem[]>([])
const total = ref(0)
const page = ref(1)
const pageSize = 20
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
  loading.value = true
  try {
    const res = await getNewsList({
      page: page.value,
      page_size: pageSize,
      status: filterStatus.value || undefined,
      keyword: keyword.value.trim() || undefined
    })
    if (res.code === 1 && res.data) {
      tableData.value = res.data
      total.value = res.total || res.data.length
    }
  } finally {
    loading.value = false
  }
}

const handleFilterChange = () => {
  page.value = 1
  loadData()
}

const openDialog = (row?: ContentItem) => {
  if (row) {
    editingId.value = row.id
    form.id = row.id
    form.title = row.title
    form.summary = row.summary
    form.content = row.content
    form.cover = row.cover
    form.category = row.category
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
    form.status = 'published'
    form.pinned = false
  }
  dialogVisible.value = true
}

const submitForm = async () => {
  if (!formRef.value) return
  await formRef.value.validate(async (valid) => {
    if (!valid) return
    if (form.cover && !/^https?:\/\/.+/.test(form.cover)) {
      ElMessage.warning('封面必须为 http 或 https 开头的 URL')
      return
    }
    submitting.value = true
    try {
      const res = await saveNews({ ...form })
      if (res.code === 1) {
        ElMessage.success(editingId.value ? '资讯更新成功' : '资讯发布成功')
        dialogVisible.value = false
        loadData()
      } else {
        ElMessage.error(res.error || res.msg || '保存失败')
      }
    } finally {
      submitting.value = false
    }
  })
}

const handleDelete = (row: ContentItem) => {
  ElMessageBox.confirm(`确定要删除资讯 [${row.title}] 吗？删除后前台将不可见。`, '删除确认', {
    confirmButtonText: '确定删除',
    cancelButtonText: '取消',
    type: 'error'
  }).then(async () => {
    const res = await deleteNews(row.id)
    if (res.code === 1) {
      ElMessage.success('已删除资讯')
      loadData()
    } else {
      ElMessage.error(res.error || res.msg || '删除失败')
    }
  }).catch(() => {})
}

onMounted(() => {
  loadData()
})
</script>

<style scoped lang="scss">
.news-page {
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
        flex-wrap: wrap;
      }
    }

    .cover-thumb {
      width: 60px;
      height: 42px;
      border-radius: 6px;
    }

    .cover-fallback {
      width: 60px;
      height: 42px;
      border-radius: 6px;
      background: var(--border-color);
      color: var(--text-secondary);
      font-size: 11px;
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
      font-size: 12px;
      color: var(--text-secondary);
    }

    .pagination-wrap {
      display: flex;
      justify-content: flex-end;
      margin-top: 16px;
    }
  }
}
</style>
