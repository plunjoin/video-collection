<template>
  <div class="videos-page">
    <el-button type="primary" style="margin-bottom:16px" @click="newVideo">新增视频资料</el-button>
    <el-card shadow="never" class="filter-card">
      <el-form :inline="true" :model="queryForm" class="filter-form">
        <el-form-item label="片名搜索">
          <el-input
            v-model="queryForm.keyword"
            placeholder="输入影片关键词"
            clearable
            style="width: 200px"
            @keyup.enter="handleSearch"
          />
        </el-form-item>
        <el-form-item label="所属分类">
          <el-select
            v-model="queryForm.type_id"
            placeholder="全部分类"
            clearable
            filterable
            style="width: 170px"
            @change="handleSearch"
            @clear="handleSearch"
          >
            <el-option label="全部分类" :value="0" />
            <el-option
              v-for="opt in categoryOptions"
              :key="opt.value"
              :label="opt.label"
              :value="opt.value"
            />
          </el-select>
        </el-form-item>
        <el-form-item>
          <el-button type="primary" @click="handleSearch">
            <el-icon><Search /></el-icon>查询
          </el-button>
          <el-button @click="resetQuery">
            <el-icon><RefreshRight /></el-icon>重置
          </el-button>
        </el-form-item>
      </el-form>
    </el-card>

    <el-card shadow="never" class="table-card">
      <!-- 批量操作栏 -->
      <div class="batch-bar" v-if="selectedIds.length > 0">
        <span class="selected-text">已选中 {{ selectedIds.length }} 部视频</span>
        <el-button type="danger" size="small" @click="handleBatchDelete">
          <el-icon><Delete /></el-icon>批量删除所选
        </el-button>
      </div>

      <!-- 数据表格 -->
      <el-table
        :data="tableData"
        v-loading="loading"
        border
        stripe
        style="width: 100%"
        @selection-change="handleSelectionChange"
      >
        <el-table-column type="selection" width="50" align="center" />
        <el-table-column prop="id" label="ID" width="80" align="center" />
        <el-table-column label="封面" width="80" align="center">
          <template #default="{ row }">
            <el-image
              style="width: 50px; height: 70px; border-radius: 4px"
              :src="row.pic || row.picture"
              :preview-src-list="[row.pic || row.picture]"
              fit="cover"
              preview-teleported
            >
              <template #error>
                <div class="image-slot">
                  <el-icon><Picture /></el-icon>
                </div>
              </template>
            </el-image>
          </template>
        </el-table-column>
        <el-table-column prop="name" label="片名 / 备注" min-width="180">
          <template #default="{ row }">
            <div class="title-cell">
              <span class="main-title font-bold">{{ row.name }}</span>
              <span v-if="row.remarks" class="sub-remarks">{{ row.remarks }}</span>
            </div>
          </template>
        </el-table-column>
        <el-table-column prop="type_name" label="分类" width="110" align="center">
          <template #default="{ row }">
            <el-tag size="small">{{ row.type_name || '未分类' }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="地区/年份" width="130" align="center">
          <template #default="{ row }">
            <span class="meta-tag">{{ row.area || '-' }} / {{ row.year || '-' }}</span>
          </template>
        </el-table-column>
        <el-table-column label="聚合线路 / 节点" width="130" align="center">
          <template #default="{ row }">
            <el-tag :type="getRoutesCount(row) > 1 ? 'success' : 'warning'" size="small">
              {{ getRoutesCount(row) }} 条线路
            </el-tag>
            <div v-if="row.source_ids && row.source_ids.length > 1" class="multi-node-badge">
              多节点({{ row.source_ids.length }})
            </div>
          </template>
        </el-table-column>
        <el-table-column prop="hits" label="播放热度" width="90" align="center" />
        <el-table-column prop="updated_at" label="更新时间" width="160" align="center">
          <template #default="{ row }">
            <span class="date-text">{{ formatDate(row.updated_at) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="200" align="center" fixed="right">
          <template #default="{ row }">
            <el-button size="small" type="primary" plain @click="viewDetail(row)">详情</el-button>
            <el-button size="small" type="warning" plain @click="editVideo(row)">编辑</el-button>
            <el-button size="small" type="danger" plain @click="deleteSingleVideo(row)">删除</el-button>
          </template>
        </el-table-column>
      </el-table>

      <!-- 分页栏 -->
      <div class="pagination-bar">
        <el-pagination
          v-model:current-page="queryForm.page"
          v-model:page-size="queryForm.page_size"
          :page-sizes="[10, 20, 50, 100]"
          :total="total"
          layout="total, sizes, prev, pager, next, jumper"
          @size-change="handleSearch"
          @current-change="loadData"
        />
      </div>
    </el-card>

    <!-- 视频详情与多线路播放抽屉 -->
    <el-drawer v-model="detailVisible" title="影视剧聚合线路详情" size="580px" destroy-on-close>
      <div v-if="currentDetail" class="detail-drawer-content">
        <div class="video-meta-header">
          <el-image
            :src="currentDetail.pic || currentDetail.picture"
            style="width: 90px; height: 125px; border-radius: 6px"
            fit="cover"
          />
          <div class="meta-texts">
            <h3 class="meta-title">{{ currentDetail.name }}</h3>
            <div class="badges">
              <el-tag size="small">{{ currentDetail.type_name }}</el-tag>
              <el-tag size="small" type="success">{{ currentDetail.area }}</el-tag>
              <el-tag size="small" type="info">{{ currentDetail.year }}</el-tag>
            </div>
            <p class="staff"><strong>导演：</strong>{{ currentDetail.director || '暂无' }}</p>
            <p class="staff"><strong>主演：</strong>{{ currentDetail.actor || '暂无' }}</p>
          </div>
        </div>

        <el-divider content-position="left">聚合播放线路 ({{ getRoutesList(currentDetail).length }})</el-divider>

        <el-tabs type="border-card" v-if="getRoutesList(currentDetail).length">
          <el-tab-pane
            v-for="(route, idx) in getRoutesList(currentDetail)"
            :key="idx"
            :label="getRouteLabel(route, idx)"
          >
            <div class="route-info">
              <span>采集节点：<el-tag size="small" type="success">{{ route.source_name || route.source_id || '默认节点' }}</el-tag></span>
              <span>播放器编码：<code>{{ route.player_code || route.from }}</code></span>
              <span v-if="route.server && route.server !== 'no'">解析服务器：{{ route.server }}</span>
              <span>总集数：{{ route.episodes?.length || 0 }} 集</span>
            </div>
            <div class="episodes-list">
              <div v-for="(ep, epIdx) in route.episodes" :key="epIdx" class="episode-chip">
                <span class="ep-name">{{ ep.name }}</span>
                <el-link
                  type="primary"
                  :href="ep.url"
                  target="_blank"
                  class="ep-link"
                  title="在新窗口打开播放地址"
                >
                  播放地址
                </el-link>
              </div>
            </div>
          </el-tab-pane>
        </el-tabs>
        <div v-else class="empty-tip">该视频暂无可用的播放集数线路</div>

        <el-divider content-position="left">影片简介</el-divider>
        <div class="blurb-box">{{ currentDetail.blurb || currentDetail.content || '暂无简介' }}</div>
      </div>
    </el-drawer>

    <!-- 视频编辑对话框 -->
    <el-dialog v-model="editDialogVisible" title="编辑视频资料" width="600px">
      <el-form :model="editForm" label-width="90px">
        <el-form-item label="片名" required>
          <el-input v-model="editForm.name" />
        </el-form-item>
        <el-form-item label="副标题/备注">
          <el-input v-model="editForm.remarks" placeholder="如：第10集 / HD国语" />
        </el-form-item>
        <el-form-item label="所属分类">
          <el-select v-model="editForm.type_id" filterable style="width: 100%">
            <el-option
              v-for="opt in categoryOptions"
              :key="opt.value"
              :label="opt.label"
              :value="opt.value"
            />
          </el-select>
        </el-form-item>
        <el-form-item label="海报图片">
          <el-input v-model="editForm.picture" placeholder="http://..." />
        </el-form-item>
        <el-form-item label="年份 / 地区">
          <el-row :gutter="10">
            <el-col :span="12">
              <el-input v-model="editForm.year" placeholder="年份" />
            </el-col>
            <el-col :span="12">
              <el-input v-model="editForm.area" placeholder="地区" />
            </el-col>
          </el-row>
        </el-form-item>
        <el-form-item label="主演">
          <el-input v-model="editForm.actor" />
        </el-form-item>
        <el-form-item label="导演">
          <el-input v-model="editForm.director" />
        </el-form-item>
        <el-form-item label="简介">
          <el-input v-model="editForm.content" type="textarea" :rows="3" />
        </el-form-item>
        <el-form-item label="播放线路"><el-input v-model="routesJSON" type="textarea" :rows="5" placeholder='[{"player_code":"hls","server":"no","note":"","episodes":[{"name":"第1集","url":"https://..."}]}]' /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="editDialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="submitEditVideo">保存修改</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, computed, onMounted } from 'vue'
import {
  getCategories,
  getVideos,
  getVideoDetail,
  saveVideo,
  deleteVideo,
  batchDeleteVideos
} from '@/api/videos'
import type { Category, VideoRecord } from '@/types'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Search, RefreshRight, Delete, Picture } from '@element-plus/icons-vue'

const loading = ref(false)
const tableData = ref<VideoRecord[]>([])
const categories = ref<Category[]>([])
const total = ref(0)
const selectedIds = ref<number[]>([])

const queryForm = reactive({
  page: 1,
  page_size: 20,
  type_id: 0,
  keyword: ''
})

// 分类树级联平铺选项
const categoryOptions = computed(() => {
  const list = categories.value || []
  const parents = list.filter((c) => !c.pid || c.pid === 0)
  const result: { label: string; value: number }[] = []

  parents.forEach((p) => {
    const pId = p.id ?? p.type_id ?? 0
    const pName = p.name ?? p.type_name ?? ''
    result.push({ label: pName, value: pId })

    const children = list.filter((c) => c.pid === pId)
    children.forEach((ch) => {
      const chId = ch.id ?? ch.type_id ?? 0
      const chName = ch.name ?? ch.type_name ?? ''
      result.push({ label: `　└─ ${chName}`, value: chId })
    })
  })

  // 兜底其它未挂载在上述父级的分类
  list.forEach((c) => {
    const cId = c.id ?? c.type_id ?? 0
    if (!result.some((r) => r.value === cId)) {
      result.push({ label: c.name ?? c.type_name ?? '', value: cId })
    }
  })

  return result
})

const detailVisible = ref(false)
const currentDetail = ref<VideoRecord | null>(null)

const getRoutesList = (item?: VideoRecord | null): any[] => {
  if (!item) return []
  return item.play_routes || item.play_groups || []
}

const getRoutesCount = (item?: VideoRecord | null): number => {
  return getRoutesList(item).length
}

const getRouteLabel = (route: any, idx: number): string => {
  if (route.source_name) {
    return `${route.source_name} (${route.player_code || route.from})`
  }
  return route.from || `线路 ${idx + 1}`
}

const editDialogVisible = ref(false)
const saving = ref(false)
const editForm = reactive<Partial<VideoRecord>>({})
const routesJSON = ref('[]')
function newVideo(){for(const key of Object.keys(editForm))delete (editForm as any)[key];Object.assign(editForm,{id:0,name:'',type_id:0,picture:'',content:''});routesJSON.value='[]';editDialogVisible.value=true}

const formatDate = (val?: string) => {
  if (!val) return '-'
  return val.replace('T', ' ').substring(0, 19)
}

const loadCategories = async () => {
  try {
    const res = await getCategories()
    if (res.code === 1 && res.data) {
      categories.value = res.data
    }
  } catch (e) {}
}

const loadData = async () => {
  loading.value = true
  try {
    const params: any = {
      page: queryForm.page,
      page_size: queryForm.page_size
    }
    if (queryForm.type_id && queryForm.type_id > 0) {
      params.type_id = queryForm.type_id
    }
    if (queryForm.keyword && queryForm.keyword.trim()) {
      params.keyword = queryForm.keyword.trim()
    }

    const res = await getVideos(params)
    if (res.code === 1) {
      tableData.value = res.data || []
      total.value = res.total || 0
    }
  } finally {
    loading.value = false
  }
}

const handleSearch = () => {
  queryForm.page = 1
  loadData()
}

const resetQuery = () => {
  queryForm.page = 1
  queryForm.keyword = ''
  queryForm.type_id = 0
  loadData()
}

const handleSelectionChange = (selection: VideoRecord[]) => {
  selectedIds.value = selection.map((it) => it.id)
}

const viewDetail = async (row: VideoRecord) => {
  try {
    const res = await getVideoDetail(row.id)
    if (res.code === 1 && res.data) {
      currentDetail.value = res.data
      detailVisible.value = true
    }
  } catch (e) {}
}

const editVideo = (row: VideoRecord) => {
  for(const key of Object.keys(editForm))delete (editForm as any)[key]
  Object.assign(editForm, row)
  routesJSON.value=JSON.stringify(row.play_groups || row.play_routes || [],null,2)
  editDialogVisible.value = true
}

const submitEditVideo = async () => {
  saving.value = true
  try {
    let routes:any;try{routes=JSON.parse(routesJSON.value);if(!Array.isArray(routes))throw new Error()}catch{ElMessage.error('播放线路必须为 JSON 数组');return}
    const {id,name,sub_name,type_id,type_name,picture,actor,director,area,language,year,remarks,content,source_id}=editForm
    const res = await saveVideo({id,name,sub_name,type_id,type_name,picture,actor,director,area,language,year,remarks,content,source_id,play_groups:routes})
    if (res.code === 1) {
      ElMessage.success(res.msg || '视频资料已保存')
      editDialogVisible.value = false
      loadData()
    }
  } finally {
    saving.value = false
  }
}

const deleteSingleVideo = (row: VideoRecord) => {
  ElMessageBox.confirm(`确定要删除影片 [${row.name}] 吗？`, '删除确认', {
    confirmButtonText: '确定删除',
    cancelButtonText: '取消',
    type: 'error'
  }).then(async () => {
    await deleteVideo(row.id)
    ElMessage.success('已删除该影片')
    loadData()
  }).catch(() => {})
}

const handleBatchDelete = () => {
  if (selectedIds.value.length === 0) return
  ElMessageBox.confirm(
    `确定要批量删除已选中的 ${selectedIds.value.length} 部影片吗？操作不可逆！`,
    '批量删除确认',
    {
      confirmButtonText: '确定批量删除',
      cancelButtonText: '取消',
      type: 'error'
    }
  ).then(async () => {
    const res = await batchDeleteVideos(selectedIds.value)
    if (res.code === 1) {
      ElMessage.success(res.msg || '批量删除成功')
      selectedIds.value = []
      loadData()
    }
  }).catch(() => {})
}

onMounted(() => {
  loadCategories()
  loadData()
})
</script>

<style scoped lang="scss">
.videos-page {
  display: flex;
  flex-direction: column;
  gap: 14px;

  .filter-card {
    border-radius: 12px;
    border: 1px solid var(--border-color);
    :deep(.el-form-item) {
      margin-bottom: 0;
    }
  }

  .table-card {
    border-radius: 12px;
    border: 1px solid var(--border-color);

    .batch-bar {
      display: flex;
      align-items: center;
      gap: 12px;
      padding: 8px 14px;
      margin-bottom: 12px;
      background: rgba(244, 63, 94, 0.1);
      border: 1px solid rgba(244, 63, 94, 0.25);
      border-radius: 8px;

      .selected-text {
        font-size: 13px;
        color: #f43f5e;
        font-weight: 600;
      }
    }

    .title-cell {
      display: flex;
      flex-direction: column;
      gap: 2px;
      .main-title {
        font-size: 13px;
        color: var(--text-primary);
      }
      .sub-remarks {
        font-size: 11px;
        color: #6366f1;
      }
    }

    .meta-tag {
      font-size: 12px;
      color: var(--text-secondary);
    }

    .multi-node-badge {
      font-size: 11px;
      color: #059669;
      background: #ecfdf5;
      padding: 1px 5px;
      border-radius: 4px;
      margin-top: 3px;
      display: inline-block;
      font-weight: 500;
    }

    .date-text {
      font-size: 12px;
      color: var(--text-secondary);
    }

    .pagination-bar {
      display: flex;
      justify-content: flex-end;
      margin-top: 16px;
    }

    .image-slot {
      display: flex;
      justify-content: center;
      align-items: center;
      width: 100%;
      height: 100%;
      background: rgba(148, 163, 184, 0.1);
      color: var(--text-secondary);
    }
  }

  .detail-drawer-content {
    .video-meta-header {
      display: flex;
      gap: 16px;

      .meta-texts {
        display: flex;
        flex-direction: column;
        gap: 6px;

        .meta-title {
          margin: 0;
          font-size: 16px;
          color: var(--text-primary);
        }

        .badges {
          display: flex;
          gap: 6px;
        }

        .staff {
          margin: 0;
          font-size: 12px;
          color: var(--text-regular);
        }
      }
    }

    .route-info {
      font-size: 12px;
      color: var(--text-secondary);
      margin-bottom: 10px;
      display: flex;
      gap: 12px;
    }

    .episodes-list {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(100px, 1fr));
      gap: 8px;
      max-height: 250px;
      overflow-y: auto;

      .episode-chip {
        padding: 6px;
        background: rgba(148, 163, 184, 0.08);
        border: 1px solid var(--border-color);
        border-radius: 6px;
        text-align: center;
        font-size: 12px;
        display: flex;
        flex-direction: column;
        gap: 2px;

        .ep-name {
          font-weight: 500;
          color: var(--text-primary);
        }

        .ep-link {
          font-size: 10px;
        }
      }
    }

    .blurb-box {
      font-size: 13px;
      line-height: 1.6;
      color: var(--text-regular);
      background: rgba(148, 163, 184, 0.05);
      padding: 12px;
      border-radius: 8px;
    }

    .empty-tip {
      text-align: center;
      padding: 20px;
      color: var(--text-secondary);
      font-size: 13px;
    }
  }
}
</style>
