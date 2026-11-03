<template>
  <div class="users-page">
    <r-card shadow="never" class="table-card">
      <div class="table-header">
        <div class="header-left">
          <span class="page-title">系统用户与管理员管控</span>
          <span class="sub-desc">集中管理系统管理员及前台注册用户，支持检索、角色授权与密码重置</span>
        </div>
        <div class="header-right">
          <r-button type="primary" @click="openDialog()">
            <r-icon><Plus /></r-icon>新增用户
          </r-button>
          <r-button @click="loadData" :loading="loading">
            <r-icon><RefreshRight /></r-icon>刷新
          </r-button>
        </div>
      </div>

      <div class="filter-bar">
        <r-input
          v-model="filters.q"
          placeholder="搜索用户名或昵称"
          clearable
          class="filter-keyword"
          @keyup.enter="applyFilters"
        />
        <r-select v-model="filters.role" placeholder="全部角色" style="width: 140px" @change="applyFilters">
          <r-option label="全部角色" value="" />
          <r-option v-for="(label, value) in roleLabels" :key="value" :label="label" :value="value" />
        </r-select>
        <r-select v-model="filters.status" placeholder="全部状态" style="width: 130px" @change="applyFilters">
          <r-option label="全部状态" value="" />
          <r-option label="正常启用" :value="1" />
          <r-option label="已封禁" :value="0" />
        </r-select>
        <r-button @click="applyFilters">查询</r-button>
        <r-button @click="resetFilters">重置</r-button>
      </div>

      <r-table :data="tableData" v-loading="loading" border stripe style="width: 100%">
        <r-table-column prop="id" label="UID" width="70" align="center" />
        <r-table-column prop="username" label="用户名" min-width="140">
          <template #default="{ row }">
            <button type="button" class="user-link" @click="openDetail(row)">{{ row.username }}</button>
          </template>
        </r-table-column>
        <r-table-column prop="nickname" label="昵称" min-width="140">
          <template #default="{ row }">
            <span>{{ row.nickname || '-' }}</span>
          </template>
        </r-table-column>
        <r-table-column prop="role" label="角色身份" width="120" align="center">
          <template #default="{ row }">
            <r-tag :type="row.role === 'user' ? 'primary' : 'danger'" effect="plain">
              {{ roleLabels[row.role] || row.role }}
            </r-tag>
          </template>
        </r-table-column>
        <r-table-column prop="status" label="账号状态" width="100" align="center">
          <template #default="{ row }">
            <r-tag :type="row.status === 1 ? 'success' : 'danger'">
              {{ row.status === 1 ? '正常启用' : '已封禁' }}
            </r-tag>
          </template>
        </r-table-column>
        <r-table-column prop="created_at" label="注册时间" width="170" align="center">
          <template #default="{ row }">
            <span class="date-text">{{ formatDate(row.created_at) }}</span>
          </template>
        </r-table-column>
        <r-table-column label="操作" width="220" align="center" fixed="right">
          <template #default="{ row }">
            <r-button size="small" @click="openDetail(row)">详情</r-button>
            <r-button size="small" type="primary" plain @click="openDialog(row)">编辑</r-button>
            <r-button
              size="small"
              type="danger"
              plain
              :disabled="row.id === userStore.userInfo?.id || (userStore.userInfo?.role !== 'super_admin' && row.role !== 'user')"
              @click="handleDelete(row)"
            >
              删除
            </r-button>
          </template>
        </r-table-column>
      </r-table>

      <div v-if="total > 0" class="pagination-wrap">
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

    <!-- 用户详情抽屉 -->
    <r-drawer v-model="detailVisible" title="用户详情" width="420px">
      <div v-if="detailUser" class="detail-panel">
        <div class="detail-identity">
          <img v-if="detailUser.avatar" :src="detailUser.avatar" alt="" class="detail-avatar" />
          <span v-else class="detail-avatar detail-avatar--text">{{ (detailUser.nickname || detailUser.username).slice(0, 1) }}</span>
          <div class="detail-name">
            <strong>{{ detailUser.nickname || detailUser.username }}</strong>
            <span>@{{ detailUser.username }}</span>
          </div>
        </div>

        <dl class="detail-list">
          <div><dt>UID</dt><dd>{{ detailUser.id }}</dd></div>
          <div><dt>角色身份</dt><dd>{{ roleLabels[detailUser.role] || detailUser.role }}</dd></div>
          <div>
            <dt>账号状态</dt>
            <dd>
              <r-tag :type="detailUser.status === 1 ? 'success' : 'danger'">
                {{ detailUser.status === 1 ? '正常启用' : '已封禁' }}
              </r-tag>
            </dd>
          </div>
          <div><dt>注册时间</dt><dd>{{ formatDate(detailUser.created_at) }}</dd></div>
          <div><dt>最近更新</dt><dd>{{ formatDate(detailUser.updated_at) }}</dd></div>
          <div class="detail-bio"><dt>个人简介</dt><dd>{{ detailUser.bio || '未填写' }}</dd></div>
        </dl>

        <p class="detail-note">密码无法查看。如需重置，请使用「编辑」填写新密码；用户本人也可在门户或客户端自助修改。</p>

        <div class="detail-actions">
          <r-button type="primary" @click="editFromDetail">编辑该用户</r-button>
          <r-button @click="detailVisible = false">关闭</r-button>
        </div>
      </div>
    </r-drawer>

    <!-- 新增/编辑对话框 -->
    <r-dialog
      v-model="dialogVisible"
      :title="editingId ? '编辑用户信息' : '新增用户'"
      width="500px"
    >
      <r-form ref="formRef" :model="form" :rules="formRules" label-width="100px">
        <r-form-item label="用户名" prop="username">
          <r-input v-model="form.username" :disabled="!!editingId" placeholder="英文与数字组合" />
        </r-form-item>
        <r-form-item label="用户昵称" prop="nickname">
          <r-input v-model="form.nickname" placeholder="显示的称谓昵称" />
        </r-form-item>
        <r-form-item
          :label="editingId ? '重置密码' : '登录密码'"
          :prop="editingId ? '' : 'password'"
        >
          <r-input
            v-model="form.password"
            type="password"
            show-password
            :placeholder="editingId ? '留空表示不修改密码' : '设置登录密码 (至少6位)'"
          />
        </r-form-item>
        <r-form-item label="角色权限" prop="role">
          <r-radio-group v-model="form.role" :disabled="userStore.userInfo?.role !== 'super_admin'">
            <r-radio value="user">普通会员</r-radio>
            <r-radio value="super_admin">超级管理员</r-radio><r-radio value="admin">管理员</r-radio><r-radio value="observer">观察员</r-radio><r-radio value="operator">运营人员</r-radio>
          </r-radio-group>
        </r-form-item>
        <r-form-item label="账号状态">
          <r-switch
            v-model="form.status"
            :active-value="1"
            :inactive-value="0"
            active-text="正常可用"
            inactive-text="禁用封禁"
          />
        </r-form-item>
      </r-form>
      <template #footer>
        <r-button @click="dialogVisible = false">取消</r-button>
        <r-button type="primary" :loading="submitting" @click="submitForm">保存</r-button>
      </template>
    </r-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { getUsers, saveUser, deleteUser } from '@/api/admin'
import type { UserInfo } from '@/types'
import { useUserStore } from '@/store/user'
import { roleLabels } from '@/utils/permissions'
import { notify, confirmAction } from '@/components/radix/feedback'
import type { FormInstance, FormRules }  from '@/components/radix/types'
import { Plus, RefreshRight } from '@/components/radix/icons'

const userStore = useUserStore()
const loading = ref(false)
const tableData = ref<UserInfo[]>([])
const total = ref(0)
const page = ref(1)
const pageSize = ref(20)
const filters = reactive<{ q: string; role: string; status: number | '' }>({
  q: '',
  role: '',
  status: ''
})

const dialogVisible = ref(false)
const submitting = ref(false)
const editingId = ref<number | null>(null)
const formRef = ref<FormInstance>()

const detailVisible = ref(false)
const detailUser = ref<UserInfo | null>(null)

const form = reactive({
  id: 0,
  username: '',
  nickname: '',
  password: '',
  role: 'user',
  status: 1
})

const formRules: FormRules = {
  username: [{ required: true, message: '请输入用户名', trigger: 'blur' }],
  password: [{ min: 6, message: '密码不能少于6位', trigger: 'blur' }]
}

const formatDate = (val?: string) => {
  if (!val) return '-'
  return val.replace('T', ' ').substring(0, 19)
}

const loadData = async () => {
  loading.value = true
  try {
    const res = await getUsers({
      q: filters.q.trim() || undefined,
      role: filters.role || undefined,
      status: filters.status === '' ? undefined : filters.status,
      page: page.value,
      size: pageSize.value
    })
    if (res.code === 1 && res.data) {
      tableData.value = res.data
      total.value = res.total ?? res.data.length
    }
  } finally {
    loading.value = false
  }
}

const applyFilters = () => {
  page.value = 1
  loadData()
}

const resetFilters = () => {
  filters.q = ''
  filters.role = ''
  filters.status = ''
  page.value = 1
  loadData()
}

const openDetail = (row: UserInfo) => {
  detailUser.value = row
  detailVisible.value = true
}

const editFromDetail = () => {
  if (!detailUser.value) return
  detailVisible.value = false
  openDialog(detailUser.value)
}

const openDialog = (row?: UserInfo) => {
  if (row) {
    editingId.value = row.id
    form.id = row.id
    form.username = row.username
    form.nickname = row.nickname
    form.password = ''
    form.role = row.role
    form.status = row.status ?? 1
  } else {
    editingId.value = null
    form.id = 0
    form.username = ''
    form.nickname = ''
    form.password = ''
    form.role = 'user'
    form.status = 1
  }
  dialogVisible.value = true
}

const submitForm = async () => {
  if (!formRef.value) return
  await formRef.value.validate(async (valid) => {
    if (!valid) return
    submitting.value = true
    try {
      await saveUser({
        id: form.id || undefined,
        username: form.username,
        nickname: form.nickname,
        password: form.password || undefined,
        role: form.role,
        status: form.status
      })
      notify('用户保存成功', 'success')
      dialogVisible.value = false
      loadData()
    } finally {
      submitting.value = false
    }
  })
}

const handleDelete = (row: UserInfo) => {
  if (row.id === userStore.userInfo?.id) {
    notify('不能删除自己的账号', 'warning')
    return
  }
  confirmAction(`确定要删除用户 [${row.username}] 吗？`, '删除确认', {
    confirmButtonText: '确定删除',
    cancelButtonText: '取消',
    type: 'error'
  }).then(async () => {
    await deleteUser(row.id)
    notify('已删除用户', 'success')
    loadData()
  }).catch(() => {})
}

onMounted(() => {
  loadData()
})
</script>

<style scoped>
.users-page {
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
          font-weight: 600;
          letter-spacing: 0;
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
      }
    }

    .filter-bar {
      display: flex;
      align-items: center;
      flex-wrap: wrap;
      gap: 8px;
      margin-bottom: 12px;

      .filter-keyword {
        width: 220px;
      }
    }

    .pagination-wrap {
      display: flex;
      justify-content: flex-end;
      margin-top: 14px;
    }

    .date-text {
      font-size: 10px;
      color: var(--text-secondary);
    }

    .user-link {
      padding: 0;
      color: var(--brand);
      background: none;
      border: 0;
      font-size: inherit;
      font-weight: 600;
      cursor: pointer;
    }
  }

  .detail-panel {
    display: flex;
    flex-direction: column;
    gap: 18px;

    .detail-identity {
      display: flex;
      align-items: center;
      gap: 12px;

      .detail-avatar {
        width: 52px;
        height: 52px;
        border-radius: 50%;
        object-fit: cover;
        background: var(--nav-bg-active, rgba(63, 111, 216, 0.1));

        &--text {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          color: var(--brand);
          font-size: 20px;
          font-weight: 600;
        }
      }

      .detail-name {
        display: flex;
        flex-direction: column;
        gap: 2px;

        strong {
          color: var(--text-primary);
          font-size: 14px;
        }

        span {
          color: var(--text-secondary);
          font-size: 11px;
        }
      }
    }

    .detail-list {
      display: flex;
      flex-direction: column;
      gap: 10px;
      margin: 0;

      > div {
        display: flex;
        align-items: flex-start;
        gap: 12px;
        padding-bottom: 10px;
        border-bottom: 1px dashed var(--border-color, rgba(20, 32, 57, 0.08));

        &:last-child {
          border-bottom: 0;
        }
      }

      dt {
        flex: 0 0 72px;
        color: var(--text-secondary);
        font-size: 11px;
        line-height: 1.6;
      }

      dd {
        flex: 1;
        margin: 0;
        color: var(--text-primary);
        font-size: 12px;
        line-height: 1.6;
        word-break: break-word;
      }
    }

    .detail-note {
      margin: 0;
      padding: 10px 12px;
      color: var(--text-secondary);
      background: var(--nav-bg-subtle, rgba(20, 32, 57, 0.03));
      border-radius: var(--radius-sm);
      font-size: 11px;
      line-height: 1.7;
    }

    .detail-actions {
      display: flex;
      gap: 8px;
    }
  }
}
</style>
