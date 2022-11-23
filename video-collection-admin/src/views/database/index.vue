<template>
  <div class="database-page">
    <!-- 数据库信息卡 -->
    <el-card shadow="never" class="table-card info-card">
      <div class="table-header">
        <div class="header-left">
          <span class="page-title">数据库管理</span>
          <span class="sub-desc">引擎信息、表统计、数据浏览、备份恢复、清理维护与 SQL 控制台</span>
        </div>
        <div class="header-right">
          <el-button type="primary" :loading="backingUp" @click="handleBackup">
            <el-icon><FolderAdd /></el-icon>立即备份
          </el-button>
          <el-button @click="loadInfo" :loading="infoLoading">
            <el-icon><RefreshRight /></el-icon>刷新
          </el-button>
        </div>
      </div>

      <el-descriptions v-if="info" :column="3" border>
        <el-descriptions-item label="存储引擎">
          <el-tag :type="info.engine === 'postgres' ? 'primary' : 'warning'" effect="plain">
            {{ info.engine === 'postgres' ? 'PostgreSQL' : 'SQLite（降级模式）' }}
          </el-tag>
        </el-descriptions-item>
        <el-descriptions-item label="数据库版本">
          <span class="mono-text">{{ info.version || '-' }}</span>
        </el-descriptions-item>
        <el-descriptions-item label="业务表数量">{{ info.table_count }} 张</el-descriptions-item>
        <el-descriptions-item label="连接目标">
          <span class="mono-text" v-if="info.engine === 'postgres'">
            {{ info.host }} / {{ info.database }}
          </span>
          <span class="mono-text" v-else>{{ info.file_path }}</span>
        </el-descriptions-item>
        <el-descriptions-item label="库整体大小">{{ formatBytes(info.size_bytes) }}</el-descriptions-item>
        <el-descriptions-item label="备份目录">
          <span class="mono-text">{{ info.backups_dir }}</span>
        </el-descriptions-item>
      </el-descriptions>
    </el-card>

    <!-- 功能区 -->
    <el-card shadow="never" class="table-card">
      <el-tabs v-model="activeTab" @tab-change="handleTabChange">
        <!-- 数据表 -->
        <el-tab-pane label="数据表" name="tables">
          <el-table :data="dbTables" v-loading="tablesLoading" border stripe style="width: 100%">
            <el-table-column prop="name" label="表名" min-width="160">
              <template #default="{ row }">
                <el-link type="primary" @click="openBrowse(row.name)">
                  <el-icon><View /></el-icon>{{ row.name }}
                </el-link>
              </template>
            </el-table-column>
            <el-table-column prop="rows" label="行数" width="130" align="right">
              <template #default="{ row }">
                <span>{{ row.rows.toLocaleString() }}</span>
                <el-tooltip v-if="row.approximate" content="PostgreSQL 统计估算值，可能略有偏差" placement="top">
                  <el-tag size="small" type="info" effect="plain" class="approx-tag">估算</el-tag>
                </el-tooltip>
              </template>
            </el-table-column>
            <el-table-column prop="size_bytes" label="表大小" width="110" align="right">
              <template #default="{ row }">
                <span>{{ row.size_bytes > 0 ? formatBytes(row.size_bytes) : '-' }}</span>
              </template>
            </el-table-column>
            <el-table-column prop="column_count" label="字段数" width="90" align="center" />
            <el-table-column prop="index_count" label="索引数" width="90" align="center" />
            <el-table-column prop="comment" label="表注释" min-width="160">
              <template #default="{ row }">
                <span>{{ row.comment || '-' }}</span>
              </template>
            </el-table-column>
            <el-table-column label="操作" width="100" align="center" fixed="right">
              <template #default="{ row }">
                <el-button size="small" type="primary" plain @click="openBrowse(row.name)">浏览</el-button>
              </template>
            </el-table-column>
          </el-table>
        </el-tab-pane>

        <!-- 备份与恢复 -->
        <el-tab-pane label="备份与恢复" name="backups">
          <div class="tab-toolbar">
            <el-button type="primary" size="small" :loading="backingUp" @click="handleBackup">
              <el-icon><FolderAdd /></el-icon>立即备份
            </el-button>
            <el-button size="small" @click="loadBackups" :loading="backupsLoading">
              <el-icon><RefreshRight /></el-icon>刷新列表
            </el-button>
            <span class="toolbar-tip">备份为 JSON 格式，保存在服务端备份目录</span>
          </div>
          <el-table :data="backups" v-loading="backupsLoading" border stripe style="width: 100%">
            <el-table-column prop="filename" label="备份文件" min-width="220">
              <template #default="{ row }">
                <span class="mono-text">{{ row.filename }}</span>
              </template>
            </el-table-column>
            <el-table-column prop="engine" label="来源引擎" width="110" align="center">
              <template #default="{ row }">
                <el-tag size="small" :type="row.engine === 'postgres' ? 'primary' : 'warning'" effect="plain">
                  {{ row.engine === 'postgres' ? 'PostgreSQL' : 'SQLite' }}
                </el-tag>
              </template>
            </el-table-column>
            <el-table-column prop="tables" label="表数" width="80" align="right" />
            <el-table-column prop="rows" label="行数" width="110" align="right">
              <template #default="{ row }">{{ row.rows.toLocaleString() }}</template>
            </el-table-column>
            <el-table-column prop="size_bytes" label="体积" width="100" align="right">
              <template #default="{ row }">{{ formatBytes(row.size_bytes) }}</template>
            </el-table-column>
            <el-table-column prop="created_at" label="创建时间" width="170" align="center">
              <template #default="{ row }">
                <span class="date-text">{{ formatDate(row.created_at) }}</span>
              </template>
            </el-table-column>
            <el-table-column label="操作" width="170" align="center" fixed="right">
              <template #default="{ row }">
                <el-button size="small" type="warning" plain @click="openRestore(row.filename)">恢复</el-button>
                <el-button size="small" type="danger" plain @click="handleDeleteBackup(row.filename)">删除</el-button>
              </template>
            </el-table-column>
          </el-table>
        </el-tab-pane>

        <!-- 清理维护 -->
        <el-tab-pane label="清理维护" name="cleanup">
          <div class="cleanup-wrap">
            <el-checkbox-group v-model="selectedActions" class="cleanup-group">
              <div v-for="item in cleanupActions" :key="item.value" class="cleanup-item">
                <el-checkbox :value="item.value">
                  <span class="cleanup-label">{{ item.label }}</span>
                </el-checkbox>
                <div class="cleanup-desc">{{ item.desc }}</div>
              </div>
            </el-checkbox-group>
            <div class="cleanup-footer">
              <el-button
                type="danger"
                :disabled="selectedActions.length === 0"
                :loading="cleaning"
                @click="handleCleanup"
              >
                <el-icon><Brush /></el-icon>执行清理（{{ selectedActions.length }} 项）
              </el-button>
              <span class="toolbar-tip">清理动作将直接删除数据，执行前请确认</span>
            </div>
            <el-table
              v-if="cleanupResults.length > 0"
              :data="cleanupResults"
              border
              stripe
              style="width: 100%; margin-top: 16px"
            >
              <el-table-column prop="action" label="动作" min-width="180">
                <template #default="{ row }">
                  <span class="mono-text">{{ row.action }}</span>
                </template>
              </el-table-column>
              <el-table-column prop="affected" label="影响行数" width="120" align="right">
                <template #default="{ row }">{{ row.affected.toLocaleString() }}</template>
              </el-table-column>
              <el-table-column prop="error" label="结果说明" min-width="240">
                <template #default="{ row }">
                  <span v-if="row.error" class="error-text">{{ row.error }}</span>
                  <el-tag v-else size="small" type="success" effect="plain">执行成功</el-tag>
                </template>
              </el-table-column>
            </el-table>
          </div>
        </el-tab-pane>

        <!-- SQL 控制台 -->
        <el-tab-pane label="SQL 控制台" name="sql">
          <div class="sql-wrap">
            <el-input
              v-model="sqlText"
              type="textarea"
              :rows="6"
              placeholder="输入单条 SQL 语句（引号内的分号不计）；SELECT / WITH / EXPLAIN / SHOW / PRAGMA 等只读语句直接执行，写语句与 DDL 需确认"
              class="sql-input"
            />
            <div class="sql-toolbar">
              <el-button type="primary" :loading="sqlRunning" :disabled="!sqlText.trim()" @click="handleSQL">
                <el-icon><CaretRight /></el-icon>执行
              </el-button>
              <span class="toolbar-tip">仅支持单条语句；查询最多返回 1000 行，超时 30~60 秒</span>
            </div>

            <template v-if="sqlResult">
              <el-alert
                v-if="sqlResult.truncated"
                title="查询结果已截断，仅显示前 1000 行"
                type="warning"
                :closable="false"
                style="margin-bottom: 12px"
              />
              <el-table
                v-if="sqlResult.type === 'select' && sqlResult.rows"
                :data="sqlResult.rows"
                border
                stripe
                style="width: 100%"
                max-height="420"
              >
                <el-table-column
                  v-for="col in sqlResult.columns"
                  :key="col"
                  :prop="col"
                  :label="col"
                  min-width="140"
                  show-overflow-tooltip
                >
                  <template #default="{ row }">
                    <span class="mono-text">{{ formatCellValue(row[col]) }}</span>
                  </template>
                </el-table-column>
              </el-table>
              <el-descriptions v-else :column="3" border>
                <el-descriptions-item label="语句类型">
                  <el-tag size="small" :type="sqlResult.type === 'write' ? 'warning' : 'info'" effect="plain">
                    {{ sqlResult.type === 'write' ? '写语句' : 'DDL' }}
                  </el-tag>
                </el-descriptions-item>
                <el-descriptions-item label="影响行数">
                  {{ (sqlResult.affected ?? 0).toLocaleString() }}
                </el-descriptions-item>
                <el-descriptions-item label="执行说明">{{ sqlResult.message || '执行成功' }}</el-descriptions-item>
              </el-descriptions>
              <div v-if="sqlResult.type === 'select'" class="sql-rowcount">
                共 {{ (sqlResult.row_count ?? 0).toLocaleString() }} 行
              </div>
            </template>
          </div>
        </el-tab-pane>
      </el-tabs>
    </el-card>

    <!-- 数据浏览对话框 -->
    <el-dialog v-model="browse.visible" :title="`浏览表数据 - ${browse.table}`" width="960px" top="6vh">
      <div class="browse-toolbar">
        <el-select v-model="browse.orderBy" placeholder="排序字段" size="small" style="width: 180px" @change="loadBrowse">
          <el-option v-for="c in browse.columns" :key="c.name" :value="c.name" :label="c.name" />
        </el-select>
        <el-switch v-model="browse.orderDesc" active-text="降序" inactive-text="升序" size="small" @change="loadBrowse" />
        <el-input
          v-model="browse.keyword"
          size="small"
          placeholder="全列模糊搜索（% 与 _ 按字面匹配）"
          style="width: 240px"
          clearable
          @keyup.enter="loadBrowse"
          @clear="loadBrowse"
        >
          <template #append>
            <el-button @click="loadBrowse"><el-icon><Search /></el-icon></el-button>
          </template>
        </el-input>
      </div>
      <el-table :data="browse.rows" v-loading="browse.loading" border stripe style="width: 100%" max-height="440">
        <el-table-column
          v-for="col in browse.columns"
          :key="col.name"
          :prop="col.name"
          :label="`${col.name} (${col.data_type})`"
          min-width="150"
          show-overflow-tooltip
        >
          <template #default="{ row }">
            <span class="mono-text">{{ formatCellValue(row[col.name]) }}</span>
          </template>
        </el-table-column>
      </el-table>
      <el-pagination
        v-model:current-page="browse.page"
        v-model:page-size="browse.pageSize"
        :total="browse.total"
        :page-sizes="[20, 50, 100, 200]"
        layout="total, sizes, prev, pager, next, jumper"
        style="margin-top: 14px; justify-content: flex-end"
        @current-change="loadBrowse"
        @size-change="loadBrowse"
      />
    </el-dialog>

    <!-- 恢复对话框 -->
    <el-dialog v-model="restore.visible" title="从备份恢复数据" width="680px">
      <el-alert
        title="恢复将向数据库写入数据，正式执行前请确认备份内容无误"
        type="warning"
        :closable="false"
        style="margin-bottom: 16px"
      />
      <el-descriptions v-if="restore.preview" :column="2" border style="margin-bottom: 16px">
        <el-descriptions-item label="备份文件">
          <span class="mono-text">{{ restore.preview.file }}</span>
        </el-descriptions-item>
        <el-descriptions-item label="备份创建时间">{{ formatDate(restore.preview.created_at) }}</el-descriptions-item>
      </el-descriptions>

      <el-form label-width="90px">
        <el-form-item label="恢复模式">
          <el-radio-group v-model="restore.mode" @change="loadRestorePreview">
            <el-radio value="merge">合并导入（冲突跳过）</el-radio>
            <el-radio value="replace">清空重导（危险）</el-radio>
          </el-radio-group>
        </el-form-item>
      </el-form>

      <el-table v-if="restore.preview" :data="restore.preview.tables" border stripe size="small" max-height="260">
        <el-table-column prop="name" label="表名" min-width="160">
          <template #default="{ row }"><span class="mono-text">{{ row.name }}</span></template>
        </el-table-column>
        <el-table-column prop="rows" label="备份行数" width="110" align="right">
          <template #default="{ row }">{{ row.rows.toLocaleString() }}</template>
        </el-table-column>
        <el-table-column prop="exists" label="目标表" width="120" align="center">
          <template #default="{ row }">
            <el-tag size="small" :type="row.exists ? 'success' : 'info'" effect="plain">
              {{ row.exists ? '已存在' : '不存在' }}
            </el-tag>
          </template>
        </el-table-column>
      </el-table>

      <div v-if="restore.previewLoading" v-loading="true" style="height: 80px" />

      <template #footer>
        <el-button @click="restore.visible = false">取消</el-button>
        <el-button type="danger" :loading="restoring" :disabled="!restore.preview" @click="confirmRestore">
          确认恢复
        </el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import {
  getDBInfo,
  getDBTables,
  browseTable,
  createBackup,
  getBackups,
  deleteBackup,
  previewRestore,
  restoreDatabase,
  runCleanup,
  execSQL
} from '@/api/admin'
import type { DBInfo, DBTableInfo, BackupMeta, RestorePreview, CleanupResult, SQLExecResult } from '@/types'
import { ElMessage, ElMessageBox } from 'element-plus'
import { FolderAdd, RefreshRight, View, Brush, CaretRight, Search } from '@element-plus/icons-vue'

// ---------- 信息卡 ----------
const info = ref<DBInfo | null>(null)
const infoLoading = ref(false)

const loadInfo = async () => {
  infoLoading.value = true
  try {
    const res = await getDBInfo()
    if (res.code === 1 && res.data) {
      info.value = res.data
    }
  } finally {
    infoLoading.value = false
  }
}

// ---------- 标签页 ----------
const activeTab = ref('tables')
const loadedTabs = new Set(['tables'])

const handleTabChange = (tab: string | number) => {
  const name = String(tab)
  if (loadedTabs.has(name)) {
    // 已加载过，切回备份页时轻量刷新列表
    if (name === 'backups') loadBackups()
    return
  }
  loadedTabs.add(name)
  if (name === 'backups') loadBackups()
}

// ---------- 数据表 ----------
const dbTables = ref<DBTableInfo[]>([])
const tablesLoading = ref(false)

const loadTables = async () => {
  tablesLoading.value = true
  try {
    const res = await getDBTables()
    if (res.code === 1 && res.data) {
      dbTables.value = res.data
    }
  } finally {
    tablesLoading.value = false
  }
}

// ---------- 数据浏览 ----------
const browse = reactive({
  visible: false,
  table: '',
  loading: false,
  columns: [] as { name: string; data_type: string }[],
  rows: [] as Record<string, any>[],
  total: 0,
  page: 1,
  pageSize: 50,
  orderBy: '',
  orderDesc: false,
  keyword: ''
})

const openBrowse = (table: string) => {
  browse.table = table
  browse.visible = true
  browse.page = 1
  browse.orderBy = ''
  browse.orderDesc = false
  browse.keyword = ''
  loadBrowse()
}

const loadBrowse = async () => {
  browse.loading = true
  try {
    const res = await browseTable({
      table: browse.table,
      page: browse.page,
      page_size: browse.pageSize,
      order_by: browse.orderBy || undefined,
      order_desc: browse.orderDesc ? 1 : undefined,
      keyword: browse.keyword || undefined
    })
    if (res.code === 1 && res.data) {
      browse.columns = res.data.columns || []
      browse.rows = res.data.rows || []
      browse.total = res.data.total || 0
    }
  } finally {
    browse.loading = false
  }
}

// ---------- 备份与恢复 ----------
const backups = ref<BackupMeta[]>([])
const backupsLoading = ref(false)
const backingUp = ref(false)

const loadBackups = async () => {
  backupsLoading.value = true
  try {
    const res = await getBackups()
    if (res.code === 1 && res.data) {
      backups.value = res.data
    }
  } finally {
    backupsLoading.value = false
  }
}

const handleBackup = async () => {
  backingUp.value = true
  try {
    const res = await createBackup()
    if (res.code === 1 && res.data) {
      ElMessage.success(`备份完成：${res.data.tables} 张表 / ${res.data.rows.toLocaleString()} 行`)
      if (loadedTabs.has('backups')) loadBackups()
      loadInfo()
    }
  } finally {
    backingUp.value = false
  }
}

const handleDeleteBackup = (filename: string) => {
  ElMessageBox.confirm(`确定要删除备份文件 [${filename}] 吗？删除后不可恢复。`, '删除确认', {
    confirmButtonText: '确定删除',
    cancelButtonText: '取消',
    type: 'error'
  })
    .then(async () => {
      await deleteBackup(filename)
      ElMessage.success('备份文件已删除')
      loadBackups()
    })
    .catch(() => {})
}

// 恢复流程：打开对话框 → dry_run 预览 → 确认后 confirm=true 执行
const restore = reactive({
  visible: false,
  file: '',
  mode: 'merge' as 'merge' | 'replace',
  preview: null as RestorePreview | null,
  previewLoading: false
})
const restoring = ref(false)

const openRestore = (filename: string) => {
  restore.file = filename
  restore.mode = 'merge'
  restore.visible = true
  restore.preview = null
  loadRestorePreview()
}

const loadRestorePreview = async () => {
  restore.preview = null
  restore.previewLoading = true
  try {
    const res = await previewRestore(restore.file, restore.mode)
    if (res.code === 1 && res.data) {
      restore.preview = res.data
    }
  } finally {
    restore.previewLoading = false
  }
}

const confirmRestore = () => {
  if (!restore.preview) return
  const modeText =
    restore.mode === 'replace'
      ? 'replace 模式将清空目标表后整体导入，PostgreSQL 下 TRUNCATE 会级联清空引用表'
      : 'merge 模式将逐行合并导入，主键冲突的行会跳过'
  ElMessageBox.confirm(
    `确定要从备份恢复数据吗？\n文件：${restore.preview.file}\n模式：${modeText}`,
    '恢复确认',
    {
      confirmButtonText: '确认执行恢复',
      cancelButtonText: '取消',
      type: restore.mode === 'replace' ? 'error' : 'warning'
    }
  )
    .then(async () => {
      restoring.value = true
      try {
        const res = await restoreDatabase(restore.file, restore.mode)
        if (res.code === 1 && res.data) {
          ElMessage.success(
            `恢复完成：插入 ${res.data.inserted.toLocaleString()} 行 / 跳过 ${res.data.skipped.toLocaleString()} 行`
          )
          restore.visible = false
          loadTables()
          loadInfo()
        }
      } finally {
        restoring.value = false
      }
    })
    .catch(() => {})
}

// ---------- 清理维护 ----------
const selectedActions = ref<string[]>([])
const cleaning = ref(false)
const cleanupResults = ref<CleanupResult[]>([])

const cleanupActions = [
  { value: 'vacuum', label: 'VACUUM 空间回收', desc: 'PostgreSQL 执行 VACUUM (ANALYZE)，SQLite 执行 VACUUM' },
  { value: 'orphan_play_sources', label: '清理失效播放线路', desc: '删除目标视频已不存在的线路记录（仅 SQLite 引擎）' },
  { value: 'dup_play_sources', label: '播放线路去重', desc: '按 视频+播放器+来源 去重并保留最新一条（仅 SQLite 引擎）' },
  { value: 'orphan_comments', label: '清理失效评论', desc: '删除目标视频已不存在的影视评论' },
  { value: 'orphan_user_history', label: '清理失效播放历史', desc: '删除目标视频已不存在的用户播放历史' },
  { value: 'orphan_user_favorites', label: '清理失效收藏', desc: '删除目标视频已不存在的用户收藏' },
  { value: 'clear_user_history', label: '清空全部播放历史', desc: '删除所有用户的播放历史（不可恢复）' },
  { value: 'clear_feedbacks', label: '清空全部反馈', desc: '删除所有求片与报错反馈（不可恢复）' }
]

const handleCleanup = () => {
  ElMessageBox.confirm(
    `即将执行 ${selectedActions.value.length} 项清理动作，将直接删除数据且不可恢复。确定继续吗？`,
    '清理确认',
    { confirmButtonText: '确认执行', cancelButtonText: '取消', type: 'error' }
  )
    .then(async () => {
      cleaning.value = true
      try {
        const res = await runCleanup(selectedActions.value)
        if (res.code === 1 && res.data) {
          cleanupResults.value = res.data
          ElMessage.success('清理动作执行完毕，详见结果列表')
          loadTables()
        }
      } finally {
        cleaning.value = false
      }
    })
    .catch(() => {})
}

// ---------- SQL 控制台 ----------
const sqlText = ref('')
const sqlRunning = ref(false)
const sqlResult = ref<SQLExecResult | null>(null)

// 与后端 ClassifySQL 一致的只读语句前缀
const READONLY_SQL_RE = /^\s*(select|with|explain|show|pragma|values|describe)\b/i

const handleSQL = async () => {
  const sql = sqlText.value.trim()
  if (!sql) return

  const readonly = READONLY_SQL_RE.test(sql)
  if (!readonly) {
    try {
      await ElMessageBox.confirm(
        `检测到写语句或 DDL，执行将修改数据库数据：\n\n${sql.length > 120 ? sql.slice(0, 120) + '……' : sql}`,
        'SQL 执行确认',
        {
          confirmButtonText: '确认执行',
          cancelButtonText: '取消',
          type: 'warning'
        }
      )
    } catch {
      return
    }
  }

  sqlRunning.value = true
  try {
    const res = await execSQL(sql, !readonly)
    if (res.code === 1 && res.data) {
      sqlResult.value = res.data
    }
  } finally {
    sqlRunning.value = false
  }
}

// ---------- 通用工具 ----------
const formatBytes = (bytes: number): string => {
  if (!bytes || bytes <= 0) return '-'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  let v = bytes
  let i = 0
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024
    i++
  }
  return `${v >= 100 ? v.toFixed(0) : v.toFixed(i === 0 ? 0 : 1)} ${units[i]}`
}

const formatDate = (val?: string) => {
  if (!val) return '-'
  return val.replace('T', ' ').substring(0, 19)
}

const formatCellValue = (v: any): string => {
  if (v === null || v === undefined) return 'NULL'
  if (typeof v === 'object') return JSON.stringify(v)
  return String(v)
}

onMounted(() => {
  loadInfo()
  loadTables()
})
</script>

<style scoped lang="scss">
.database-page {
  display: flex;
  flex-direction: column;
  gap: 16px;

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
  }

  .mono-text {
    font-family: 'JetBrains Mono', Consolas, monospace;
    font-size: 12px;
  }

  .date-text {
    font-size: 12px;
    color: var(--text-secondary);
  }

  .approx-tag {
    margin-left: 6px;
  }

  .tab-toolbar {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-bottom: 14px;
    flex-wrap: wrap;

    .toolbar-tip {
      font-size: 12px;
      color: var(--text-secondary);
    }
  }

  .cleanup-wrap {
    .cleanup-group {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
      gap: 12px;
      margin-bottom: 18px;

      .cleanup-item {
        border: 1px solid var(--border-color);
        border-radius: 8px;
        padding: 10px 14px;

        .cleanup-label {
          font-weight: 600;
        }

        .cleanup-desc {
          font-size: 12px;
          color: var(--text-secondary);
          margin-top: 2px;
          padding-left: 24px;
        }
      }
    }

    .cleanup-footer {
      display: flex;
      align-items: center;
      gap: 12px;

      .toolbar-tip {
        font-size: 12px;
        color: var(--text-secondary);
      }
    }
  }

  .sql-wrap {
    .sql-input {
      :deep(textarea) {
        font-family: 'JetBrains Mono', Consolas, monospace;
        font-size: 13px;
      }
    }

    .sql-toolbar {
      display: flex;
      align-items: center;
      gap: 12px;
      margin: 12px 0 16px;

      .toolbar-tip {
        font-size: 12px;
        color: var(--text-secondary);
      }
    }

    .sql-rowcount {
      margin-top: 8px;
      font-size: 12px;
      color: var(--text-secondary);
      text-align: right;
    }
  }

  .browse-toolbar {
    display: flex;
    align-items: center;
    gap: 14px;
    margin-bottom: 14px;
    flex-wrap: wrap;
  }

  .error-text {
    font-size: 12px;
    color: var(--el-color-danger);
  }
}
</style>
