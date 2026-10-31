<template>
  <div class="users-page">
    <r-card shadow="never" class="table-card">
      <div class="table-header">
        <div class="header-left">
          <span class="page-title">系统用户与管理员管控</span>
          <span class="sub-desc">集中管理系统管理员及前台注册用户，支持角色授权与密码重置</span>
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

      <r-table :data="tableData" v-loading="loading" border stripe style="width: 100%">
        <r-table-column prop="id" label="UID" width="70" align="center" />
        <r-table-column prop="username" label="用户名" min-width="140">
          <template #default="{ row }">
            <span class="font-bold">{{ row.username }}</span>
          </template>
        </r-table-column>
        <r-table-column prop="nickname" label="昵称" min-width="140">
          <template #default="{ row }">
            <span>{{ row.nickname || '-' }}</span>
          </template>
        </r-table-column>
        <r-table-column prop="role" label="角色身份" width="120" align="center">
          <template #default="{ row }">
            <r-tag :type="row.role === 'admin' ? 'danger' : 'primary'" effect="plain">
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
        <r-table-column label="操作" width="180" align="center" fixed="right">
          <template #default="{ row }">
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
    </r-card>

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
const dialogVisible = ref(false)
const submitting = ref(false)
const editingId = ref<number | null>(null)
const formRef = ref<FormInstance>()

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
    const res = await getUsers()
    if (res.code === 1 && res.data) {
      tableData.value = res.data
    }
  } finally {
    loading.value = false
  }
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
      }
    }

    .date-text {
      font-size: 10px;
      color: var(--text-secondary);
    }
  }
}
</style>
