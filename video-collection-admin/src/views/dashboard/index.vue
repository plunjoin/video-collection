<template>
  <div class="dashboard-container">
    <!-- 1. 核心数据指标卡片 -->
    <el-row :gutter="16" class="stats-row">
      <el-col :xs="12" :sm="8" :md="4" v-for="item in statCards" :key="item.key">
        <el-card shadow="hover" class="stat-card" :body-style="{ padding: '16px' }">
          <div class="card-header">
            <span class="card-label">{{ item.label }}</span>
            <div class="card-icon" :style="{ background: item.iconBg, color: item.iconColor }">
              <el-icon><component :is="item.icon" /></el-icon>
            </div>
          </div>
          <div class="card-value">
            <span class="num">{{ stats[item.key] ?? 0 }}</span>
            <span v-if="item.sub" class="sub-badge">{{ item.sub }}</span>
          </div>
        </el-card>
      </el-col>
    </el-row>

    <!-- 2. 快捷操作栏 & 采集调度状态 -->
    <el-card shadow="never" class="section-card quick-actions-card">
      <div class="action-header">
        <div class="title-wrap">
          <el-icon class="title-icon"><Lightning /></el-icon>
          <span class="title-text">快速调度与即时操作</span>
        </div>
        <div class="action-buttons">
          <el-button type="primary" :loading="collectingAll" @click="handleCollectAll(24)">
            <el-icon><Refresh /></el-icon>全网近24小时增量采集
          </el-button>
          <el-button type="warning" plain :loading="collectingAll" @click="handleCollectAll(0)">
            <el-icon><Download /></el-icon>全网历史全量采集
          </el-button>
          <el-button @click="$router.push('/sources')">
            <el-icon><Plus /></el-icon>添加采集点
          </el-button>
        </div>
      </div>
    </el-card>

    <!-- 3. 采集源即时状态与图表分布 -->
    <el-row :gutter="16" class="content-row">
      <!-- 采集点即时触发列表 -->
      <el-col :xs="24" :lg="14">
        <el-card shadow="never" class="section-card">
          <template #header>
            <div class="card-title-bar">
              <span class="title">活跃采集点与即时触发</span>
              <el-button link type="primary" @click="$router.push('/sources')">
                管理采集点 &rarr;
              </el-button>
            </div>
          </template>

          <div v-loading="loadingSources" class="source-list">
            <div v-if="sources.length === 0" class="empty-tip">暂无配置采集源</div>
            <div v-for="src in sources" :key="src.id" class="source-item">
              <div class="source-info">
                <div class="name-row">
                  <span class="name">{{ src.name }}</span>
                  <el-tag size="small" :type="src.active ? 'success' : 'info'">
                    {{ src.active ? '启用中' : '已停用' }}
                  </el-tag>
                  <el-tag size="small" type="warning" effect="plain">{{ src.type.toUpperCase() }}</el-tag>
                </div>
                <div class="api-url" :title="src.api">{{ src.api }}</div>
              </div>
              <div class="source-ops">
                <el-button
                  size="small"
                  type="primary"
                  plain
                  :loading="triggeringId === src.id + '_24'"
                  @click="handleTrigger(src.id, 24)"
                >
                  增量采集
                </el-button>
                <el-button
                  size="small"
                  type="warning"
                  plain
                  :loading="triggeringId === src.id + '_0'"
                  @click="handleTrigger(src.id, 0)"
                >
                  全量补全
                </el-button>
              </div>
            </div>
          </div>
        </el-card>
      </el-col>

      <!-- 系统状态与分类概览 -->
      <el-col :xs="24" :lg="10">
        <el-card shadow="never" class="section-card">
          <template #header>
            <div class="card-title-bar">
              <span class="title">分类视频分布概览</span>
              <el-button link type="primary" @click="$router.push('/videos')">
                视频仓库 &rarr;
              </el-button>
            </div>
          </template>

          <div v-loading="loadingCategories" class="category-summary">
            <div v-if="categories.length === 0" class="empty-tip">暂无分类数据</div>
            <div class="cat-grid">
              <div v-for="cat in categories.slice(0, 8)" :key="cat.id ?? cat.type_id" class="cat-chip">
                <span class="cat-name">{{ cat.name ?? cat.type_name }}</span>
                <span class="cat-id">ID: {{ cat.id ?? cat.type_id }}</span>
              </div>
            </div>
            <div class="system-status-box">
              <div class="sys-item">
                <span class="label">服务端架构：</span>
                <span class="val">Go 1.24 + Gin/Net.HTTP 纯 RESTful</span>
              </div>
              <div class="sys-item">
                <span class="label">数据库支持：</span>
                <span class="val">PostgreSQL JSONB / SQLite 本地降级</span>
              </div>
              <div class="sys-item">
                <span class="label">OpenAPI 规范：</span>
                <el-link type="primary" href="/openapi.json" target="_blank">
                  v3.0.0 规范 JSON
                </el-link>
              </div>
            </div>
          </div>
        </el-card>
      </el-col>
    </el-row>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import {
  getAdminStats,
  getSources,
  triggerCollect,
  triggerCollectAll
} from '@/api/admin'
import { getCategories } from '@/api/videos'
import type { AdminStats, SourceConfig, Category } from '@/types'
import { ElMessage } from 'element-plus'
import {
  Connection,
  Film,
  Calendar,
  Share,
  User,
  ChatDotRound,
  Lightning,
  Refresh,
  Download,
  Plus
} from '@element-plus/icons-vue'

const stats = ref<Partial<AdminStats>>({})
const sources = ref<SourceConfig[]>([])
const categories = ref<Category[]>([])
const loadingSources = ref(false)
const loadingCategories = ref(false)
const collectingAll = ref(false)
const triggeringId = ref('')

const statCards = computed(() => [
  {
    key: 'total_sources' as const,
    label: '采集源数量',
    icon: Connection,
    iconBg: 'rgba(99, 102, 241, 0.15)',
    iconColor: '#6366f1',
    sub: `启用 ${stats.value.active_sources ?? 0}`
  },
  {
    key: 'total_videos' as const,
    label: '已入库总视频',
    icon: Film,
    iconBg: 'rgba(16, 185, 129, 0.15)',
    iconColor: '#10b981'
  },
  {
    key: 'today_updated' as const,
    label: '今日更新数据',
    icon: Calendar,
    iconBg: 'rgba(245, 158, 11, 0.15)',
    iconColor: '#f59e0b'
  },
  {
    key: 'total_play_groups' as const,
    label: '聚合播放线路',
    icon: Share,
    iconBg: 'rgba(139, 92, 246, 0.15)',
    iconColor: '#8b5cf6'
  },
  {
    key: 'total_users' as const,
    label: '系统用户数',
    icon: User,
    iconBg: 'rgba(14, 165, 233, 0.15)',
    iconColor: '#0ea5e9'
  },
  {
    key: 'total_feedbacks' as const,
    label: '求片留言反馈',
    icon: ChatDotRound,
    iconBg: 'rgba(244, 63, 94, 0.15)',
    iconColor: '#f43f5e'
  }
])

const loadStats = async () => {
  try {
    const res = await getAdminStats()
    if (res.code === 1 && res.data) {
      stats.value = res.data
    }
  } catch (e) {}
}

const loadSources = async () => {
  loadingSources.value = true
  try {
    const res = await getSources()
    if (res.code === 1 && res.data) {
      sources.value = res.data
    }
  } catch (e) {
  } finally {
    loadingSources.value = false
  }
}

const loadCategoriesData = async () => {
  loadingCategories.value = true
  try {
    const res = await getCategories()
    if (res.code === 1 && res.data) {
      categories.value = res.data
    }
  } catch (e) {
  } finally {
    loadingCategories.value = false
  }
}

const handleTrigger = async (sourceId: string, hours: number) => {
  const triggerKey = `${sourceId}_${hours}`
  triggeringId.value = triggerKey
  try {
    const res = await triggerCollect(sourceId, hours)
    if (res.code === 1) {
      ElMessage.success(res.msg || '采集任务已在后台启动')
      loadStats()
    }
  } catch (e) {
  } finally {
    triggeringId.value = ''
  }
}

const handleCollectAll = async (hours: number) => {
  collectingAll.value = true
  try {
    const res = await triggerCollectAll(hours)
    if (res.code === 1) {
      ElMessage.success(res.msg || '全网并发采集任务已启动')
      loadStats()
    }
  } catch (e) {
  } finally {
    collectingAll.value = false
  }
}

onMounted(() => {
  loadStats()
  loadSources()
  loadCategoriesData()
})
</script>

<style scoped lang="scss">
.dashboard-container {
  display: flex;
  flex-direction: column;
  gap: 16px;

  .stats-row {
    .stat-card {
      border-radius: 12px;
      border: 1px solid var(--border-color);
      transition: all 0.25s;

      &:hover {
        transform: translateY(-2px);
      }

      .card-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 8px;

        .card-label {
          font-size: 12px;
          color: var(--text-secondary);
          font-weight: 600;
        }

        .card-icon {
          width: 32px;
          height: 32px;
          border-radius: 8px;
          display: flex;
          align-items: center;
          justify-content: center;
        }
      }

      .card-value {
        display: flex;
        align-items: baseline;
        gap: 8px;

        .num {
          font-size: 24px;
          font-weight: 700;
          color: var(--text-primary);
        }

        .sub-badge {
          font-size: 11px;
          color: #10b981;
          font-weight: 500;
        }
      }
    }
  }

  .quick-actions-card {
    border-radius: 12px;
    border: 1px solid var(--border-color);

    .action-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      flex-wrap: wrap;
      gap: 12px;

      .title-wrap {
        display: flex;
        align-items: center;
        gap: 8px;
        color: #6366f1;

        .title-icon {
          font-size: 18px;
        }

        .title-text {
          font-size: 14px;
          font-weight: 600;
          color: var(--text-primary);
        }
      }

      .action-buttons {
        display: flex;
        gap: 10px;
        flex-wrap: wrap;
      }
    }
  }

  .content-row {
    .section-card {
      border-radius: 12px;
      border: 1px solid var(--border-color);
      height: 100%;

      .card-title-bar {
        display: flex;
        align-items: center;
        justify-content: space-between;

        .title {
          font-size: 14px;
          font-weight: 600;
          color: var(--text-primary);
        }
      }

      .source-list {
        display: flex;
        flex-direction: column;
        gap: 12px;

        .source-item {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 12px 14px;
          background-color: rgba(148, 163, 184, 0.06);
          border: 1px solid var(--border-color);
          border-radius: 8px;
          gap: 12px;

          .source-info {
            flex: 1;
            min-width: 0;

            .name-row {
              display: flex;
              align-items: center;
              gap: 8px;
              margin-bottom: 4px;

              .name {
                font-size: 13px;
                font-weight: 600;
                color: var(--text-primary);
              }
            }

            .api-url {
              font-size: 11px;
              color: var(--text-secondary);
              overflow: hidden;
              text-overflow: ellipsis;
              white-space: nowrap;
            }
          }

          .source-ops {
            display: flex;
            gap: 6px;
            flex-shrink: 0;
          }
        }
      }

      .category-summary {
        display: flex;
        flex-direction: column;
        gap: 16px;

        .cat-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(110px, 1fr));
          gap: 8px;

          .cat-chip {
            padding: 8px 10px;
            background: rgba(99, 102, 241, 0.08);
            border: 1px solid rgba(99, 102, 241, 0.2);
            border-radius: 6px;
            display: flex;
            flex-direction: column;

            .cat-name {
              font-size: 13px;
              font-weight: 600;
              color: #6366f1;
            }

            .cat-id {
              font-size: 10px;
              color: var(--text-secondary);
            }
          }
        }

        .system-status-box {
          border-top: 1px solid var(--border-color);
          padding-top: 14px;
          display: flex;
          flex-direction: column;
          gap: 8px;
          font-size: 12px;

          .sys-item {
            display: flex;
            align-items: center;
            justify-content: space-between;

            .label {
              color: var(--text-secondary);
            }
            .val {
              color: var(--text-primary);
              font-weight: 500;
            }
          }
        }
      }

      .empty-tip {
        text-align: center;
        padding: 30px;
        color: var(--text-secondary);
        font-size: 13px;
      }
    }
  }
}
</style>
