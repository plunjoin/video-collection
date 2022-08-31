<template>
  <div class="users-page">
    <el-card shadow="never" class="table-card">
      <div class="table-header">
        <div class="header-left">
          <span class="page-title">系统用户与管理员管控</span>
          <span class="sub-desc">集中管理系统管理员及前台注册用户，支持角色授权与密码重置</span>
        </div>
        <div class="header-right">
          <el-button type="primary" @click="openDialog()">
            <el-icon><Plus /></el-icon>新增用户
          </el-button>
          <el-button @click="loadData" :loading="loading">
            <el-icon><RefreshRight /></el-icon>刷新
          </el-button>
        </div>
      </div>

      <el-table :data="tableData" v-loading="loading" border stripe style="width: 100%">
        <el-table-column prop="id" label="UID" width="70" align="center" />
        <el-table-column prop="username" label="用户名" min-width="140">
          <template #default="{ row }">
            <span class="font-bold">{{ row.username }}</span>
          </template>
        </el-table-column>
        <el-table-column prop="nickname" label="昵称" min-width="140">
          <template #default="{ row }">
            <span>{{ row.nickname || '-' }}</span>
          </template>
        </el-table-column>
        <el-table-column prop="role" label="角色身份" width="120" align="center">
          <template #default="{ row }">
            <el-tag :type="row.role === 'admin' ? 'danger' : 'primary'" effect="plain">
              {{ row.role === 'admin' ? '管理员 (Admin)' : '普通会员' }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="status" label="账号状态" width="100" align="center">
          <template #default="{ row }">
            <el-tag :type="row.status === 1 ? 'success' : 'danger'">
              {{ row.status === 1 ? '正常启用' : '已封禁' }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="created_at" label="注册时间" width="170" align="center">
          <template #default="{ row }">
            <span class="date-text">{{ formatDate(row.created_at) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="180" align="center" fixed="right">
          <template #default="{ row }">
            <el-button size="small" type="primary" plain @click="openDialog(row)">编辑</el-button>
            <el-button
              size="small"
              type="danger"
              plain
              :disabled="row.id === 1"
              @click="handleDelete(row)"
            >
              删除
            </el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <!-- 新增/编辑对话框 -->
    <el-dialog
      v-model="dialogVisible"
      :title="editingId ? '编辑用户信息' : '新增用户'"
      width="500px"
    >
      <el-form ref="formRef" :model="form" :rules="formRules" label-width="100px">
        <el-form-item label="用户名" prop="username">
          <el-input v-model="form.username" :disabled="!!editingId" placeholder="英文与数字组合" />
        </el-form-item>
        <el-form-item label="用户昵称" prop="nickname">
          <el-input v-model="form.nickname" placeholder="显示的称谓昵称" />
        </el-form-item>
        <el-form-item
          :label="editingId ? '重置密码' : '登录密码'"
          :prop="editingId ? '' : 'password'"
        >
          <el-input
            v-model="form.password"
            type="password"
            show-password
            :placeholder="editingId ? '留空表示不修改密码' : '设置登录密码 (至少6位)'"
          />
        </el-form-item>
        <el-form-item label="角色权限" prop="role">
          <el-radio-group v-model="form.role">
            <el-radio value="user">普通会员</el-radio>
            <el-radio value="admin">系统管理员</el-radio>
          </el-radio-group>
        </el-form-item>
        <el-form-item label="账号状态">
          <el-switch
            v-model="form.status"
            :active-value="1"
            :inactive-value="0"
            active-text="正常可用"
            inactive-text="禁用封禁"
          />
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
import { getUsers, saveUser, deleteUser } from '@/api/admin'
import type { UserInfo } from '@/types'
import { ElMessage, ElMessageBox, type FormInstance, type FormRules } from 'element-plus'
import { Plus, RefreshRight } from '@element-plus/icons-vue'

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
      ElMessage.success('用户保存成功')
      dialogVisible.value = false
      loadData()
    } finally {
      submitting.value = false
    }
  })
}

const handleDelete = (row: UserInfo) => {
  if (row.id === 1) {
    ElMessage.warning('不能删除超级管理员账号')
    return
  }
  ElMessageBox.confirm(`确定要删除用户 [${row.username}] 吗？`, '删除确认', {
    confirmButtonText: '确定删除',
    cancelButtonText: '取消',
    type: 'error'
  }).then(async () => {
    await deleteUser(row.id)
    ElMessage.success('已删除用户')
    loadData()
  }).catch(() => {})
}

onMounted(() => {
  loadData()
})
</script>

<style scoped lang="scss">
.users-page {
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

    .date-text {
      font-size: 12px;
      color: var(--text-secondary);
    }
  }
}
</style>
