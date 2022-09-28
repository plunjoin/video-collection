<template>
  <div class="feedbacks-page">
    <el-card shadow="never" class="table-card">
      <div class="table-header">
        <div class="header-left">
          <span class="page-title">用户求片与报错反馈</span>
          <span class="sub-desc">收集并处理客户端用户提交的求片申请、视频播放报错及建议</span>
        </div>
        <div class="header-right">
          <el-select v-model="filterStatus" placeholder="状态筛选" style="width: 130px" @change="loadData">
            <el-option label="全部状态" value="" />
            <el-option label="待处理" value="pending" />
            <el-option label="已处理" value="resolved" />
          </el-select>
          <el-button @click="loadData" :loading="loading">
            <el-icon><RefreshRight /></el-icon>刷新
          </el-button>
        </div>
      </div>

      <el-table :data="tableData" v-loading="loading" border stripe style="width: 100%">
        <el-table-column prop="id" label="ID" width="70" align="center" />
        <el-table-column prop="type" label="反馈类型" width="100" align="center">
          <template #default="{ row }">
            <el-tag :type="getTypeTag(row.type)">{{ getTypeLabel(row.type) }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="title" label="标题" min-width="160">
          <template #default="{ row }">
            <span class="font-bold">{{ row.title }}</span>
          </template>
        </el-table-column>
        <el-table-column prop="content" label="反馈详细说明" min-width="240" show-overflow-tooltip />
        <el-table-column prop="contact" label="联系方式" width="130" align="center">
          <template #default="{ row }">
            <span>{{ row.contact || '匿名未填' }}</span>
          </template>
        </el-table-column>
        <el-table-column prop="status" label="处理状态" width="100" align="center">
          <template #default="{ row }">
            <el-tag :type="row.status === 'resolved' ? 'success' : 'warning'">
              {{ row.status === 'resolved' ? '已处理' : '待处理' }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="reply" label="管理员回复" min-width="160" show-overflow-tooltip>
          <template #default="{ row }">
            <span v-if="row.reply" class="reply-text">{{ row.reply }}</span>
            <span v-else class="text-gray-400">暂未回复</span>
          </template>
        </el-table-column>
        <el-table-column prop="created_at" label="提交时间" width="160" align="center">
          <template #default="{ row }">
            <span class="date-text">{{ formatDate(row.created_at) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="160" align="center" fixed="right">
          <template #default="{ row }">
            <el-button size="small" type="primary" plain @click="openReplyDialog(row)">
              处理/回复
            </el-button>
            <el-button size="small" type="danger" plain @click="handleDelete(row)">
              删除
            </el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <!-- 回复处理模态框 -->
    <el-dialog v-model="replyDialogVisible" title="反馈跟进处理" width="500px">
      <el-form :model="replyForm" label-width="90px">
        <el-form-item label="反馈标题">
          <el-input :model-value="currentRow?.title" disabled />
        </el-form-item>
        <el-form-item label="反馈内容">
          <el-input :model-value="currentRow?.content" type="textarea" :rows="2" disabled />
        </el-form-item>
        <el-form-item label="处理状态">
          <el-radio-group v-model="replyForm.status">
            <el-radio value="pending">待跟进</el-radio>
            <el-radio value="resolved">已完成解决</el-radio>
          </el-radio-group>
        </el-form-item>
        <el-form-item label="回复说明">
          <el-input
            v-model="replyForm.reply"
            type="textarea"
            :rows="3"
            placeholder="填写给用户的回复内容或内部处理备忘..."
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="replyDialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="submitReply">保存跟进</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { getFeedbacks, replyFeedback, deleteFeedback } from '@/api/admin'
import type { FeedbackItem } from '@/types'
import { ElMessage, ElMessageBox } from 'element-plus'
import { RefreshRight } from '@element-plus/icons-vue'

const loading = ref(false)
const tableData = ref<FeedbackItem[]>([])
const filterStatus = ref('')
const replyDialogVisible = ref(false)
const saving = ref(false)
const currentRow = ref<FeedbackItem | null>(null)

const replyForm = reactive({
  id: 0,
  status: 'resolved',
  reply: ''
})

const getTypeTag = (type: string) => {
  switch (type) {
    case 'request':
      return 'primary'
    case 'error':
      return 'danger'
    default:
      return 'info'
  }
}

const getTypeLabel = (type: string) => {
  switch (type) {
    case 'request':
      return '求片申请'
    case 'error':
      return '播放报错'
    default:
      return '建议吐槽'
  }
}

const formatDate = (val?: string) => {
  if (!val) return '-'
  return val.replace('T', ' ').substring(0, 19)
}

const loadData = async () => {
  loading.value = true
  try {
    const res = await getFeedbacks({
      status: filterStatus.value || undefined
    })
    if (res.code === 1) {
      tableData.value = res.data || []
    }
  } finally {
    loading.value = false
  }
}

const openReplyDialog = (row: FeedbackItem) => {
  currentRow.value = row
  replyForm.id = row.id
  replyForm.status = row.status || 'resolved'
  replyForm.reply = row.reply || ''
  replyDialogVisible.value = true
}

const submitReply = async () => {
  saving.value = true
  try {
    const res = await replyFeedback({
      id: replyForm.id,
      status: replyForm.status,
      reply: replyForm.reply
    })
    if (res.code === 1) {
      ElMessage.success('跟进状态已更新')
      replyDialogVisible.value = false
      loadData()
    }
  } finally {
    saving.value = false
  }
}

const handleDelete = (row: FeedbackItem) => {
  ElMessageBox.confirm(`确定要删除此条反馈记录吗？`, '删除确认', {
    confirmButtonText: '确定删除',
    cancelButtonText: '取消',
    type: 'error'
  }).then(async () => {
    await deleteFeedback(row.id)
    ElMessage.success('已删除反馈')
    loadData()
  }).catch(() => {})
}

onMounted(() => {
  loadData()
})
</script>

<style scoped lang="scss">
.feedbacks-page {
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

    .reply-text {
      color: #10b981;
      font-size: 12px;
    }
    .date-text {
      font-size: 12px;
      color: var(--text-secondary);
    }
  }
}
</style>
