<template>
  <div class="videos-page">
    <div class="page-action-row">
      <r-button type="primary" @click="newVideo">
        <r-icon><Plus /></r-icon>新增视频资料
      </r-button>
    </div>
    <r-card shadow="never" class="filter-card">
      <r-form :inline="true" :model="queryForm" class="filter-form">
        <r-form-item label="片名搜索">
          <r-input
            v-model="queryForm.keyword"
            placeholder="输入影片关键词"
            clearable
            style="width: 200px"
            @keyup.enter="handleSearch"
          />
        </r-form-item>
        <r-form-item label="所属分类">
          <r-select
            v-model="queryForm.type_id"
            placeholder="全部分类"
            clearable
            filterable
            style="width: 170px"
            @change="handleSearch"
            @clear="handleSearch"
          >
            <r-option label="全部分类" :value="0" />
            <r-option
              v-for="opt in categoryOptions"
              :key="opt.value"
              :label="opt.label"
              :value="opt.value"
            />
          </r-select>
        </r-form-item>
        <r-form-item>
          <r-button type="primary" @click="handleSearch">
            <r-icon><Search /></r-icon>查询
          </r-button>
          <r-button @click="resetQuery">
            <r-icon><RefreshRight /></r-icon>重置
          </r-button>
        </r-form-item>
      </r-form>
    </r-card>

    <r-card shadow="never" class="table-card">
      <!-- 批量操作栏 -->
      <div class="batch-bar" v-if="selectedIds.length > 0">
        <span class="selected-text">已选中 {{ selectedIds.length }} 部视频</span>
        <r-button type="danger" size="small" @click="handleBatchDelete">
          <r-icon><Delete /></r-icon>批量删除所选
        </r-button>
      </div>

      <!-- 数据表格 -->
      <r-table
        :data="tableData"
        v-loading="loading"
        border
        stripe
        style="width: 100%"
        @selection-change="handleSelectionChange"
      >
        <r-table-column type="selection" width="50" align="center" />
        <r-table-column prop="id" label="ID" width="80" align="center" />
        <r-table-column label="封面" width="80" align="center">
          <template #default="{ row }">
            <r-image
              style="width: 50px; height: 70px; border-radius: 4px"
              :src="row.pic || row.picture"
              :preview-src-list="[row.pic || row.picture]"
              fit="cover"
              preview-teleported
            >
              <template #error>
                <div class="image-slot">
                  <r-icon><Picture /></r-icon>
                </div>
              </template>
            </r-image>
          </template>
        </r-table-column>
        <r-table-column prop="name" label="片名 / 备注" min-width="180">
          <template #default="{ row }">
            <div class="title-cell">
              <span class="main-title font-bold">{{ row.name }}</span>
              <span v-if="row.remarks" class="sub-remarks">{{ row.remarks }}</span>
            </div>
          </template>
        </r-table-column>
        <r-table-column prop="type_name" label="分类" width="110" align="center">
          <template #default="{ row }">
            <r-tag size="small">{{ row.type_name || '未分类' }}</r-tag>
          </template>
        </r-table-column>
        <r-table-column label="地区/年份" width="130" align="center">
          <template #default="{ row }">
            <span class="meta-tag">{{ row.area || '-' }} / {{ row.year || '-' }}</span>
          </template>
        </r-table-column>
        <r-table-column label="聚合线路 / 节点" width="130" align="center">
          <template #default="{ row }">
            <r-tag :type="getRoutesCount(row) > 1 ? 'success' : 'warning'" size="small">
              {{ getRoutesCount(row) }} 条线路
            </r-tag>
            <div v-if="row.source_ids && row.source_ids.length > 1" class="multi-node-badge">
              多节点({{ row.source_ids.length }})
            </div>
          </template>
        </r-table-column>
        <r-table-column prop="hits" label="播放热度" width="90" align="center" />
        <r-table-column prop="updated_at" label="更新时间" width="160" align="center">
          <template #default="{ row }">
            <span class="date-text">{{ formatDate(row.updated_at) }}</span>
          </template>
        </r-table-column>
        <r-table-column label="操作" width="200" align="center" fixed="right">
          <template #default="{ row }">
            <r-button size="small" type="primary" plain @click="viewDetail(row)">详情</r-button>
            <r-button size="small" type="warning" plain @click="editVideo(row)">编辑</r-button>
            <r-button size="small" type="danger" plain @click="deleteSingleVideo(row)">删除</r-button>
          </template>
        </r-table-column>
      </r-table>

      <!-- 分页栏 -->
      <div class="pagination-bar">
        <r-pagination
          v-model:current-page="queryForm.page"
          v-model:page-size="queryForm.page_size"
          :page-sizes="[10, 20, 50, 100]"
          :total="total"
          @size-change="handleSearch"
          @current-change="loadData"
        />
      </div>
    </r-card>

    <!-- 视频详情与多线路播放抽屉 -->
    <r-drawer v-model="detailVisible" title="影视剧聚合线路详情" size="580px" destroy-on-close>
      <div v-if="currentDetail" class="detail-drawer-content">
        <div class="video-meta-header">
          <r-image
            :src="currentDetail.pic || currentDetail.picture"
            style="width: 90px; height: 125px; border-radius: 6px"
            fit="cover"
          />
          <div class="meta-texts">
            <h3 class="meta-title">{{ currentDetail.name }}</h3>
            <div class="badges">
              <r-tag size="small">{{ currentDetail.type_name }}</r-tag>
              <r-tag size="small" type="success">{{ currentDetail.area }}</r-tag>
              <r-tag size="small" type="info">{{ currentDetail.year }}</r-tag>
            </div>
            <p class="staff"><strong>导演：</strong>{{ currentDetail.director || '暂无' }}</p>
            <p class="staff"><strong>主演：</strong>{{ currentDetail.actor || '暂无' }}</p>
          </div>
        </div>

        <r-divider content-position="left">聚合播放线路 ({{ getRoutesList(currentDetail).length }})</r-divider>

        <r-tabs type="border-card" v-if="getRoutesList(currentDetail).length">
          <r-tab-pane
            v-for="(route, idx) in getRoutesList(currentDetail)"
            :key="idx"
            :label="getRouteLabel(route, idx)"
          >
            <div class="route-info">
              <span>采集节点：<r-tag size="small" type="success">{{ route.source_name || route.source_id || '默认节点' }}</r-tag></span>
              <span>播放器编码：<code>{{ route.player_code || route.from }}</code></span>
              <span v-if="route.server && route.server !== 'no'">解析服务器：{{ route.server }}</span>
              <span>总集数：{{ route.episodes?.length || 0 }} 集</span>
            </div>
            <div class="episodes-list">
              <div v-for="(ep, epIdx) in route.episodes" :key="epIdx" class="episode-chip">
                <span class="ep-name">{{ ep.name }}</span>
                <r-link
                  type="primary"
                  :href="ep.url"
                  target="_blank"
                  class="ep-link"
                  title="在新窗口打开播放地址"
                >
                  播放地址
                </r-link>
              </div>
            </div>
          </r-tab-pane>
        </r-tabs>
        <div v-else class="empty-tip">该视频暂无可用的播放集数线路</div>

        <r-divider content-position="left">影片简介</r-divider>
        <div class="blurb-box">{{ currentDetail.blurb || currentDetail.content || '暂无简介' }}</div>
      </div>
    </r-drawer>

    <!-- 视频编辑对话框 -->
    <r-dialog v-model="editDialogVisible" title="编辑视频资料" width="600px">
      <r-form :model="editForm" label-width="90px">
        <r-form-item label="片名" required>
          <r-input v-model="editForm.name" />
        </r-form-item>
        <r-form-item label="副标题/备注">
          <r-input v-model="editForm.remarks" placeholder="如：第10集 / HD国语" />
        </r-form-item>
        <r-form-item label="所属分类">
          <r-select v-model="editForm.type_id" filterable style="width: 100%">
            <r-option
              v-for="opt in categoryOptions"
              :key="opt.value"
              :label="opt.label"
              :value="opt.value"
            />
          </r-select>
        </r-form-item>
        <r-form-item label="海报图片">
          <r-input v-model="editForm.picture" placeholder="http://..." />
        </r-form-item>
        <r-form-item label="年份 / 地区">
          <r-row :gutter="10">
            <r-col :span="12">
              <r-input v-model="editForm.year" placeholder="年份" />
            </r-col>
            <r-col :span="12">
              <r-input v-model="editForm.area" placeholder="地区" />
            </r-col>
          </r-row>
        </r-form-item>
        <r-form-item label="主演">
          <r-input v-model="editForm.actor" />
        </r-form-item>
        <r-form-item label="导演">
          <r-input v-model="editForm.director" />
        </r-form-item>
        <r-form-item label="简介">
          <r-input v-model="editForm.content" type="textarea" :rows="3" />
        </r-form-item>
        <r-form-item label="播放线路"><r-input v-model="routesJSON" type="textarea" :rows="5" placeholder='[{"player_code":"hls","server":"no","note":"","episodes":[{"name":"第1集","url":"https://..."}]}]' /></r-form-item>
      </r-form>
      <template #footer>
        <r-button @click="editDialogVisible = false">取消</r-button>
        <r-button type="primary" :loading="saving" @click="submitEditVideo">保存修改</r-button>
      </template>
    </r-dialog>
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
import { notify, confirmAction }  from '@/components/radix/feedback'
import { Search, RefreshRight, Delete, Picture } from '@/components/radix/icons'

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
    let routes:any;try{routes=JSON.parse(routesJSON.value);if(!Array.isArray(routes))throw new Error()}catch{notify('播放线路必须为 JSON 数组', 'error');return}
    const {id,name,sub_name,type_id,type_name,picture,actor,director,area,language,year,remarks,content,source_id}=editForm
    const res = await saveVideo({id,name,sub_name,type_id,type_name,picture,actor,director,area,language,year,remarks,content,source_id,play_groups:routes})
    if (res.code === 1) {
      notify(res.msg || '视频资料已保存', 'success')
      editDialogVisible.value = false
      loadData()
    }
  } finally {
    saving.value = false
  }
}

const deleteSingleVideo = (row: VideoRecord) => {
  confirmAction(`确定要删除影片 [${row.name}] 吗？`, '删除确认', {
    confirmButtonText: '确定删除',
    cancelButtonText: '取消',
    type: 'error'
  }).then(async () => {
    await deleteVideo(row.id)
    notify('已删除该影片', 'success')
    loadData()
  }).catch(() => {})
}

const handleBatchDelete = () => {
  if (selectedIds.value.length === 0) return
  confirmAction(
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
      notify(res.msg || '批量删除成功', 'success')
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

<style scoped>
.videos-page {
  display: flex;
  flex-direction: column;
  gap: 10px;

  .page-action-row {
    display: flex;
    align-items: center;
    justify-content: flex-start;
  }

  .filter-card {
    :deep(.r-form-item) {
      margin-bottom: 0;
    }
  }

  .table-card {
    .batch-bar {
      display: flex;
      align-items: center;
      gap: 10px;
      padding: 6px 12px;
      margin-bottom: 10px;
      background: rgba(229, 72, 77, 0.08);
      border: 1px solid rgba(229, 72, 77, 0.22);
      border-radius: var(--radius-sm);

      .selected-text {
        font-size: 11px;
        color: var(--danger);
        font-weight: 650;
      }
    }

    .title-cell {
      display: flex;
      flex-direction: column;
      gap: 2px;
      .main-title {
        font-size: 12px;
        font-weight: 650;
        color: var(--text-primary);
      }
      .sub-remarks {
        font-size: 10px;
        color: var(--brand);
      }
    }

    .meta-tag {
      font-size: 11px;
      color: var(--text-secondary);
    }

    .multi-node-badge {
      font-size: 9px;
      color: var(--success);
      background: rgba(47, 158, 110, 0.1);
      padding: 1px 5px;
      border-radius: var(--radius-xs);
      margin-top: 2px;
      display: inline-block;
      font-weight: 600;
    }

    .date-text {
      font-size: 10px;
      color: var(--text-secondary);
    }

    .pagination-bar {
      display: flex;
      justify-content: flex-end;
      margin-top: 10px;
    }

    .image-slot {
      display: flex;
      justify-content: center;
      align-items: center;
      width: 100%;
      height: 100%;
      background: rgba(20, 32, 57, 0.04);
      color: var(--text-secondary);
    }
  }

  .detail-drawer-content {
    .video-meta-header {
      display: flex;
      gap: 12px;

      .meta-texts {
        display: flex;
        flex-direction: column;
        gap: 4px;

        .meta-title {
          margin: 0;
          font-size: 14px;
          font-weight: 700;
          color: var(--text-primary);
        }

        .badges {
          display: flex;
          gap: 4px;
        }

        .staff {
          margin: 0;
          font-size: 11px;
          color: var(--text-regular);
        }
      }
    }

    .route-info {
      font-size: 11px;
      color: var(--text-secondary);
      margin-bottom: 8px;
      display: flex;
      gap: 10px;
    }

    .episodes-list {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(90px, 1fr));
      gap: 6px;
      max-height: 240px;
      overflow-y: auto;

      .episode-chip {
        padding: 5px 6px;
        background: rgba(20, 32, 57, 0.035);
        border: 1px solid var(--border-color);
        border-radius: var(--radius-xs);
        text-align: center;
        font-size: 11px;
        display: flex;
        flex-direction: column;
        gap: 2px;

        .ep-name {
          font-weight: 600;
          color: var(--text-primary);
        }

        .ep-link {
          font-size: 9px;
          color: var(--text-secondary);
        }
      }
    }

    .blurb-box {
      font-size: 11px;
      line-height: 1.55;
      color: var(--text-regular);
      background: rgba(20, 32, 57, 0.03);
      padding: 10px;
      border-radius: var(--radius-sm);
    }

    .empty-tip {
      text-align: center;
      padding: 16px;
      color: var(--text-secondary);
      font-size: 11px;
    }
  }
}
</style>
