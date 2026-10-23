<template>
  <div class="community-page">
    <r-card shadow="never" class="table-card">
      <div class="table-header">
        <div class="header-left">
          <span class="page-title">同好社区内容管理</span>
          <span class="sub-desc">管理用户发布的社区帖子与评论，支持置顶、隐藏与违规内容清理</span>
        </div>
        <div class="header-right">
          <r-button type="primary" @click="openPostDialog()">
            <r-icon><Plus /></r-icon>发布官方帖
          </r-button>
        </div>
      </div>

      <r-tabs v-model="activeTab">
        <!-- 帖子管理 -->
        <r-tab-pane label="帖子管理" name="posts">
          <div class="filter-bar">
            <r-select
              v-model="postFilter.status"
              placeholder="状态筛选"
              style="width: 120px"
              @change="handlePostFilterChange"
            >
              <r-option label="全部状态" value="" />
              <r-option label="已发布" value="published" />
              <r-option label="已隐藏" value="hidden" />
            </r-select>
            <r-input
              v-model="postFilter.keyword"
              placeholder="搜索帖子标题"
              style="width: 220px"
              clearable
              @keyup.enter="handlePostFilterChange"
              @clear="handlePostFilterChange"
            />
            <r-button @click="loadPosts" :loading="postsLoading">
              <r-icon><RefreshRight /></r-icon>刷新
            </r-button>
          </div>

          <r-table :data="posts" v-loading="postsLoading" border stripe style="width: 100%">
            <r-table-column prop="id" label="ID" width="70" align="center" />
            <r-table-column prop="title" label="帖子标题" min-width="220" show-overflow-tooltip>
              <template #default="{ row }">
                <div class="title-cell">
                  <r-tag v-if="row.pinned" type="warning" size="small" effect="dark" class="pin-tag">置顶</r-tag>
                  <span class="font-bold">{{ row.title }}</span>
                </div>
              </template>
            </r-table-column>
            <r-table-column prop="category" label="分类" width="100" align="center">
              <template #default="{ row }">
                <r-tag v-if="row.category" type="info" effect="plain">{{ row.category }}</r-tag>
                <span v-else class="text-gray-400">-</span>
              </template>
            </r-table-column>
            <r-table-column prop="author_name" label="发帖人" width="110" align="center">
              <template #default="{ row }">
                <span>{{ row.author_name || '-' }}</span>
              </template>
            </r-table-column>
            <r-table-column prop="status" label="状态" width="90" align="center">
              <template #default="{ row }">
                <r-tag :type="row.status === 'published' ? 'success' : 'danger'">
                  {{ row.status === 'published' ? '已发布' : '已隐藏' }}
                </r-tag>
              </template>
            </r-table-column>
            <r-table-column prop="like_count" label="点赞" width="70" align="center" />
            <r-table-column prop="comment_count" label="评论" width="70" align="center" />
            <r-table-column prop="created_at" label="发布时间" width="160" align="center">
              <template #default="{ row }">
                <span class="date-text">{{ formatDate(row.created_at) }}</span>
              </template>
            </r-table-column>
            <r-table-column label="操作" width="240" align="center" fixed="right">
              <template #default="{ row }">
                <r-button size="small" type="primary" plain @click="openPostDialog(row)">编辑</r-button>
                <r-button size="small" type="warning" plain @click="viewComments(row)">评论</r-button>
                <r-button size="small" type="danger" plain @click="handleDeletePost(row)">删除</r-button>
              </template>
            </r-table-column>
          </r-table>

          <div class="pagination-wrap" v-if="postsTotal > 0">
            <r-pagination
              v-model:current-page="postsPage"
              v-model:page-size="postsPageSize"
              :page-sizes="[10, 20, 50, 100]"
              :total="postsTotal"
              @current-change="loadPosts"
              @size-change="loadPosts"
            />
          </div>
        </r-tab-pane>

        <!-- 评论管理 -->
        <r-tab-pane label="评论管理" name="comments">
          <div class="filter-bar">
            <span class="filter-label">帖子 ID：</span>
            <r-input-number v-model="commentPostId" :min="1" :controls="false" style="width: 120px" placeholder="帖子ID" />
            <r-button type="primary" plain :disabled="!commentPostId" @click="loadComments">
              查询评论
            </r-button>
            <span class="filter-tip">提示：可在“帖子管理”中点击某行的“评论”按钮快速跳转</span>
          </div>

          <template v-if="commentsLoaded">
            <r-table :data="comments" v-loading="commentsLoading" border stripe style="width: 100%">
              <r-table-column prop="id" label="ID" width="70" align="center" />
              <r-table-column prop="post_id" label="所属帖子" width="90" align="center" />
              <r-table-column prop="author_name" label="评论人" width="110" align="center">
                <template #default="{ row }">
                  <span>{{ row.author_name || '-' }}</span>
                </template>
              </r-table-column>
              <r-table-column prop="content" label="评论内容" min-width="280" show-overflow-tooltip />
              <r-table-column prop="like_count" label="点赞" width="70" align="center" />
              <r-table-column prop="reply_count" label="回复" width="70" align="center" />
              <r-table-column prop="created_at" label="评论时间" width="160" align="center">
                <template #default="{ row }">
                  <span class="date-text">{{ formatDate(row.created_at) }}</span>
                </template>
              </r-table-column>
              <r-table-column label="操作" width="100" align="center" fixed="right">
                <template #default="{ row }">
                  <r-button size="small" type="danger" plain @click="handleDeleteComment(row)">删除</r-button>
                </template>
              </r-table-column>
            </r-table>

            <div class="pagination-wrap" v-if="commentsTotal > 0">
              <r-pagination
                v-model:current-page="commentsPage"
                v-model:page-size="commentsPageSize"
                :page-sizes="[10, 20, 50, 100]"
                :total="commentsTotal"
                @current-change="loadComments"
                @size-change="loadComments"
              />
            </div>
          </template>
          <div v-else class="empty-tip">
            <r-empty description="输入帖子 ID 查询该帖下的全部评论" :image-size="90" />
          </div>
        </r-tab-pane>
      </r-tabs>
    </r-card>

    <!-- 帖子新增/编辑对话框 -->
    <r-dialog
      v-model="postDialogVisible"
      :title="editingPostId ? `编辑帖子 #${editingPostId}` : '发布官方帖'"
      width="720px"
      top="6vh"
    >
      <r-form ref="postFormRef" :model="postForm" :rules="postFormRules" label-width="90px">
        <r-form-item label="标题" prop="title">
          <r-input v-model="postForm.title" maxlength="200" show-word-limit placeholder="帖子标题 (最多200字)" />
        </r-form-item>
        <r-form-item label="分类" prop="category">
          <r-input v-model="postForm.category" maxlength="50" placeholder="如：推荐 / 吐槽 / 求助 / 官方公告" />
        </r-form-item>
        <r-form-item label="摘要" prop="summary">
          <r-input
            v-model="postForm.summary"
            type="textarea"
            :rows="2"
            maxlength="1000"
            show-word-limit
            placeholder="列表页展示的简短摘要 (最多1000字)"
          />
        </r-form-item>
        <r-form-item label="正文" prop="content">
          <r-input
            v-model="postForm.content"
            type="textarea"
            :rows="10"
            maxlength="50000"
            show-word-limit
            placeholder="纯文本内容，保留换行 (最多50000字)"
          />
        </r-form-item>
        <r-form-item label="显示状态">
          <r-radio-group v-model="postForm.status">
            <r-radio value="published">公开显示</r-radio>
            <r-radio value="hidden">隐藏 (仅管理可见)</r-radio>
          </r-radio-group>
        </r-form-item>
        <r-form-item label="置顶推荐">
          <r-switch v-model="postForm.pinned" active-text="置顶显示" inactive-text="常规排序" />
        </r-form-item>
      </r-form>
      <template #footer>
        <r-button @click="postDialogVisible = false">取消</r-button>
        <r-button type="primary" :loading="submitting" @click="submitPostForm">保存</r-button>
      </template>
    </r-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { getPostList, savePost, deletePost, getCommentList, deleteComment } from '@/api/content'
import type { ContentItem, CommunityCommentItem } from '@/types'
import { notify, confirmAction } from '@/components/radix/feedback'
import type { FormInstance, FormRules }  from '@/components/radix/types'
import { Plus, RefreshRight } from '@/components/radix/icons'

// ========== 帖子管理 ==========
const postsLoading = ref(false)
const posts = ref<ContentItem[]>([])
const postsTotal = ref(0)
const postsPage = ref(1)
const postsPageSize = ref(20)
const postFilter = reactive({ status: '', keyword: '' })

const postDialogVisible = ref(false)
const submitting = ref(false)
const editingPostId = ref<number | null>(null)
const postFormRef = ref<FormInstance>()

const postForm = reactive({
  id: 0,
  title: '',
  summary: '',
  content: '',
  cover: '',
  category: '',
  status: 'published',
  pinned: false
})

const postFormRules: FormRules = {
  title: [{ required: true, message: '请输入帖子标题', trigger: 'blur' }],
  content: [{ required: true, message: '请输入正文内容', trigger: 'blur' }]
}

// ========== 评论管理 ==========
const activeTab = ref('posts')
const commentsLoading = ref(false)
const commentsLoaded = ref(false)
const comments = ref<CommunityCommentItem[]>([])
const commentsTotal = ref(0)
const commentsPage = ref(1)
const commentsPageSize = ref(20)
const commentPostId = ref<number | undefined>(undefined)

const formatDate = (val?: string) => {
  if (!val) return '-'
  return val.replace('T', ' ').substring(0, 19)
}

const loadPosts = async () => {
  postsLoading.value = true
  try {
    const res = await getPostList({
      page: postsPage.value,
      page_size: postsPageSize.value,
      status: postFilter.status || undefined,
      keyword: postFilter.keyword.trim() || undefined
    })
    if (res.code === 1 && res.data) {
      posts.value = res.data
      postsTotal.value = res.total || res.data.length
    }
  } finally {
    postsLoading.value = false
  }
}

const handlePostFilterChange = () => {
  postsPage.value = 1
  loadPosts()
}

const openPostDialog = (row?: ContentItem) => {
  if (row) {
    editingPostId.value = row.id
    postForm.id = row.id
    postForm.title = row.title
    postForm.summary = row.summary
    postForm.content = row.content
    postForm.cover = row.cover
    postForm.category = row.category
    postForm.status = row.status === 'hidden' ? 'hidden' : 'published'
    postForm.pinned = row.pinned
  } else {
    editingPostId.value = null
    postForm.id = 0
    postForm.title = ''
    postForm.summary = ''
    postForm.content = ''
    postForm.cover = ''
    postForm.category = ''
    postForm.status = 'published'
    postForm.pinned = false
  }
  postDialogVisible.value = true
}

const submitPostForm = async () => {
  if (!postFormRef.value) return
  await postFormRef.value.validate(async (valid) => {
    if (!valid) return
    submitting.value = true
    try {
      const res = await savePost({ ...postForm })
      if (res.code === 1) {
        notify(res.msg || '保存成功', 'success')
        postDialogVisible.value = false
        loadPosts()
      } else {
        notify(res.error || res.msg || '保存失败', 'error')
      }
    } finally {
      submitting.value = false
    }
  })
}

const handleDeletePost = (row: ContentItem) => {
  confirmAction(`确定要删除帖子 [${row.title}] 吗？帖子下的评论将一并清理。`, '删除确认', {
    confirmButtonText: '确定删除',
    cancelButtonText: '取消',
    type: 'error'
  }).then(async () => {
    const res = await deletePost(row.id)
    if (res.code === 1) {
      notify('已删除帖子', 'success')
      loadPosts()
    } else {
      notify(res.error || res.msg || '删除失败', 'error')
    }
  }).catch(() => {})
}

// 从帖子行跳转到评论 Tab
const viewComments = (row: ContentItem) => {
  commentPostId.value = row.id
  commentsPage.value = 1
  activeTab.value = 'comments'
  loadComments()
}

const loadComments = async () => {
  if (!commentPostId.value) {
    notify('请先输入要查询的帖子 ID', 'warning')
    return
  }
  commentsLoading.value = true
  try {
    const res = await getCommentList({
      post_id: commentPostId.value,
      page: commentsPage.value,
      page_size: commentsPageSize.value
    })
    if (res.code === 1 && res.data) {
      comments.value = res.data
      commentsTotal.value = res.total || res.data.length
      commentsLoaded.value = true
    }
  } finally {
    commentsLoading.value = false
  }
}

const handleDeleteComment = (row: CommunityCommentItem) => {
  confirmAction(`确定要删除该条评论吗？内容：${row.content.substring(0, 40)}${row.content.length > 40 ? '…' : ''}`, '删除确认', {
    confirmButtonText: '确定删除',
    cancelButtonText: '取消',
    type: 'error'
  }).then(async () => {
    const res = await deleteComment(row.id)
    if (res.code === 1) {
      notify('已删除评论', 'success')
      loadComments()
    } else {
      notify(res.error || res.msg || '删除失败', 'error')
    }
  }).catch(() => {})
}

onMounted(() => {
  loadPosts()
})
</script>

<style scoped lang="scss">
.community-page {
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
    }

    .filter-bar {
      display: flex;
      align-items: center;
      gap: 8px;
      flex-wrap: wrap;
      margin-bottom: 10px;

      .filter-label {
        font-size: 11px;
        color: var(--text-secondary);
      }

      .filter-tip {
        font-size: 10px;
        color: var(--text-secondary);
      }
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

    .empty-tip {
      padding: 16px 0;
    }

    .pagination-wrap {
      display: flex;
      justify-content: flex-end;
      margin-top: 10px;
    }
  }
}
</style>
