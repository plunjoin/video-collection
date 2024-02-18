<template>
  <div class="operations-page">
    <el-card shadow="never" class="toolbar">
      <div class="toolbar__left">
        <el-select v-model="slotFilter" placeholder="全部广告位" clearable style="width: 180px" @change="load">
          <el-option v-for="(label, key) in slotLabels" :key="key" :label="label" :value="key" />
        </el-select>
        <span class="toolbar__tip">广告位按位置投放到客户端：banner=首页顶部横幅，home_recommend=首页推荐位（番剧列表内），detail=详情/播放页。未配置或过期时客户端自动隐藏。</span>
      </div>
      <div class="toolbar__right">
        <el-button type="primary" :disabled="!canManage" @click="editItem()">新增广告</el-button>
        <el-button @click="load">刷新</el-button>
      </div>
    </el-card>

    <el-table :data="items" v-loading="loading" border>
      <el-table-column prop="id" label="ID" width="70" />
      <el-table-column label="广告位" width="150">
        <template #default="{ row }">{{ slotLabels[row.slot] || row.slot }}</template>
      </el-table-column>
      <el-table-column label="物料" min-width="260">
        <template #default="{ row }">
          <div class="ad-cell">
            <el-image :src="row.image" fit="cover" class="ad-cell__img" fit-on-error>
              <template #error><div class="ad-cell__img ad-cell__img--empty">无图</div></template>
            </el-image>
            <div class="ad-cell__meta">
              <span class="ad-cell__title">{{ row.title }}</span>
              <span class="ad-cell__link">{{ row.link || (row.video_id ? '/play/' + row.video_id : '未设置跳转') }}</span>
            </div>
          </div>
        </template>
      </el-table-column>
      <el-table-column prop="sort" label="排序" width="80" />
      <el-table-column label="排期" width="210">
        <template #default="{ row }">{{ row.starts_at || '不限' }} ~ {{ row.ends_at || '不限' }}</template>
      </el-table-column>
      <el-table-column label="状态" width="90">
        <template #default="{ row }">
          <el-tag :type="row.active ? 'success' : 'info'" size="small">{{ row.active ? '上架中' : '已下架' }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="150">
        <template #default="{ row }">
          <el-button size="small" :disabled="!canManage" @click="editItem(row)">编辑</el-button>
          <el-button size="small" type="danger" plain :disabled="!canManage" @click="remove(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-dialog v-model="dialogVisible" :title="form.id ? '编辑广告' : '新增广告'" width="560px">
      <el-form label-width="90px">
        <el-form-item label="广告位" required>
          <el-select v-model="form.slot" :disabled="!!form.id" style="width: 100%">
            <el-option v-for="(label, key) in slotLabels" :key="key" :label="label" :value="key" />
          </el-select>
        </el-form-item>
        <el-form-item label="标题" required><el-input v-model="form.title" maxlength="60" placeholder="广告标题，最多60字" /></el-form-item>
        <el-form-item label="图片地址" required><el-input v-model="form.image" maxlength="512" placeholder="站内路径 / 或 https 图片" /></el-form-item>
        <el-form-item label="跳转链接"><el-input v-model="form.link" maxlength="512" placeholder="站内路径（/category）或 https 外链" /></el-form-item>
        <el-form-item label="关联影片ID"><el-input-number v-model="form.video_id" :min="0" controls-position="right" style="width: 100%" /><span class="form-tip">未填跳转链接时，点击跳转到该影片播放页</span></el-form-item>
        <el-form-item label="排序"><el-input-number v-model="form.sort" :min="0" :max="9999" controls-position="right" style="width: 100%" /></el-form-item>
        <el-form-item label="生效排期">
          <div class="date-range">
            <el-date-picker v-model="form.starts_at" type="date" value-format="YYYY-MM-DD" placeholder="开始日期" clearable />
            <span>~</span>
            <el-date-picker v-model="form.ends_at" type="date" value-format="YYYY-MM-DD" placeholder="结束日期" clearable />
          </div>
        </el-form-item>
        <el-form-item label="上架"><el-switch v-model="form.active" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="save">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import request from '@/utils/request'
import { getAds, saveAd, deleteAd } from '@/api/admin'
import { useUserStore } from '@/store/user'

const user = useUserStore()
const canManage = computed(() => ['super_admin', 'admin'].includes(user.userInfo?.role || ''))

const slotLabels: Record<string, string> = {
  banner: '首页横幅 Banner',
  home_recommend: '首页推荐位（列表内）',
  detail: '详情/播放页'
}

const items = ref<any[]>([])
const loading = ref(false)
const saving = ref(false)
const slotFilter = ref('')
const dialogVisible = ref(false)
const emptyForm = () => ({ id: 0, slot: 'banner', title: '', image: '', link: '', video_id: 0, sort: 0, active: true, starts_at: '', ends_at: '' })
const form = reactive(emptyForm())

async function load() {
  loading.value = true
  try {
    const r: any = await getAds(slotFilter.value || undefined)
    items.value = r.data || []
  } finally {
    loading.value = false
  }
}

function editItem(row?: any) {
  Object.assign(form, emptyForm(), row || {})
  dialogVisible.value = true
}

async function save() {
  if (!form.title.trim()) { ElMessage.warning('请填写广告标题'); return }
  if (!form.image.trim()) { ElMessage.warning('请填写图片地址'); return }
  saving.value = true
  try {
    await saveAd({ ...form })
    ElMessage.success('广告已保存')
    dialogVisible.value = false
    await load()
  } catch (e: any) {
    ElMessage.error(e?.response?.data?.error || '保存失败')
  } finally {
    saving.value = false
  }
}

async function remove(row: any) {
  await ElMessageBox.confirm(`确定删除广告「${row.title}」？删除后客户端立即不再展示。`, '删除确认', { type: 'warning' })
  await deleteAd(row.id)
  ElMessage.success('已删除')
  await load()
}

onMounted(load)
</script>

<style scoped>
.toolbar { display: flex; justify-content: space-between; align-items: center; gap: 16px; margin-bottom: 16px; flex-wrap: wrap; }
.toolbar__left { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
.toolbar__tip { font-size: 12px; color: var(--el-text-color-secondary); line-height: 1.6; max-width: 640px; }
.ad-cell { display: flex; align-items: center; gap: 10px; }
.ad-cell__img { width: 44px; height: 58px; border-radius: 6px; flex-shrink: 0; object-fit: cover; background: var(--el-fill-color-light); }
.ad-cell__img--empty { display: flex; align-items: center; justify-content: center; font-size: 11px; color: var(--el-text-color-placeholder); }
.ad-cell__meta { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.ad-cell__title { font-size: 13px; font-weight: 600; }
.ad-cell__link { font-size: 12px; color: var(--el-text-color-secondary); }
.form-tip { margin-left: 10px; font-size: 12px; color: var(--el-text-color-secondary); }
.date-range { display: flex; align-items: center; gap: 8px; }
.date-range .el-date-editor { flex: 1; }
</style>
