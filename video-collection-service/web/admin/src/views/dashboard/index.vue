<template>
  <div class="dashboard-container">
    <!-- 1. 核心数据指标卡片 -->
    <r-row :gutter="12" class="stats-row">
      <r-col :xs="12" :sm="8" :md="4" v-for="item in statCards" :key="item.key">
        <r-card shadow="hover" class="stat-card" :body-style="{ padding: '12px 14px' }">
          <div class="card-header">
            <span class="card-label">{{ item.label }}</span>
            <div class="card-icon" :style="{ background: item.iconBg, color: item.iconColor }">
              <r-icon><component :is="item.icon" /></r-icon>
            </div>
          </div>
          <div class="card-value">
            <span class="num">{{ stats[item.key] ?? 0 }}</span>
            <span v-if="item.sub" class="sub-badge">{{ item.sub }}</span>
          </div>
        </r-card>
      </r-col>
    </r-row>

    <!-- 2. 快捷操作栏 & 采集调度状态 -->
    <r-card shadow="never" class="section-card quick-actions-card">
      <div class="action-header">
        <div class="title-wrap">
          <r-icon class="title-icon"><Lightning /></r-icon>
          <span class="title-text">快速调度与即时操作</span>
        </div>
        <div class="action-buttons">
          <r-button type="primary" :loading="collectingAll" @click="handleCollectAll(24)">
            <r-icon><Refresh /></r-icon>全网近24小时增量采集
          </r-button>
          <r-button type="warning" plain :loading="collectingAll" @click="handleCollectAll(0)">
            <r-icon><Download /></r-icon>全网历史全量采集
          </r-button>
          <r-button @click="$router.push('/sources')">
            <r-icon><Plus /></r-icon>添加采集点
          </r-button>
        </div>
      </div>
    </r-card>

    <!-- 2.5 埋点流量概览（网站 + App 上报汇总） -->
    <r-card shadow="never" class="section-card analytics-card">
      <div class="analytics-header">
        <div class="title-wrap">
          <r-icon class="title-icon"><TrendCharts /></r-icon>
          <span class="title-text">埋点流量概览</span>
          <span class="title-aux">网站 / App 上报汇总</span>
        </div>
        <r-button link type="primary" @click="$router.push('/analytics')">
          埋点详情 &rarr;
        </r-button>
      </div>

      <div v-loading="loadingAnalytics" class="analytics-body">
        <div class="an-metrics">
          <div v-for="m in analyticsMetrics" :key="m.key" class="an-metric">
            <span class="an-label">{{ m.label }}</span>
            <span class="an-value-row">
              <span class="an-value">{{ formatNumber(m.value) }}</span>
              <span
                v-if="m.delta !== null"
                class="an-delta"
                :class="m.delta >= 0 ? 'is-up' : 'is-down'"
              >{{ m.delta >= 0 ? '+' : '' }}{{ m.delta.toFixed(1) }}%</span>
            </span>
            <span class="an-sub">{{ m.sub }}</span>
          </div>
        </div>

        <div v-if="trendBars.length" class="an-trend">
          <div class="an-trend-head">
            <span>近 7 天浏览量</span>
            <span class="an-trend-max">峰值 {{ formatNumber(trendMax) }}</span>
          </div>
          <div class="an-bars">
            <div
              v-for="p in trendBars"
              :key="p.day"
              class="an-bar-col"
              :title="`${p.day} · PV ${formatNumber(p.pv)} · UV ${formatNumber(p.uv)}`"
            >
              <div class="an-bar-track">
                <div class="an-bar" :style="{ height: p.height }"></div>
              </div>
              <span class="an-bar-label">{{ p.label }}</span>
            </div>
          </div>
        </div>
        <div v-else-if="!loadingAnalytics" class="an-empty">
          暂无埋点数据，部署后产生首批访问即可统计
        </div>
      </div>
    </r-card>

    <!-- 3. 采集源即时状态与图表分布 -->
    <r-row :gutter="12" class="content-row">
      <!-- 采集点即时触发列表 -->
      <r-col :xs="24" :lg="14">
        <r-card shadow="never" class="section-card">
          <template #header>
            <div class="card-title-bar">
              <span class="title">活跃采集点与即时触发</span>
              <r-button link type="primary" @click="$router.push('/sources')">
                管理采集点 &rarr;
              </r-button>
            </div>
          </template>

          <div v-loading="loadingSources" class="source-list">
            <div v-if="sources.length === 0" class="empty-tip">暂无配置采集源</div>
            <div v-for="src in sources" :key="src.id" class="source-item">
              <div class="source-info">
                <div class="name-row">
                  <span class="name">{{ src.name }}</span>
                  <r-tag size="small" :type="src.active ? 'success' : 'info'">
                    {{ src.active ? '启用中' : '已停用' }}
                  </r-tag>
                  <r-tag size="small" type="warning" effect="plain">{{ src.type.toUpperCase() }}</r-tag>
                </div>
                <div class="api-url" :title="src.api">{{ src.api }}</div>
              </div>
              <div class="source-ops">
                <r-button
                  size="small"
                  type="primary"
                  plain
                  :loading="triggeringId === src.id + '_24'"
                  @click="handleTrigger(src.id, 24)"
                >
                  增量采集
                </r-button>
                <r-button
                  size="small"
                  type="warning"
                  plain
                  :loading="triggeringId === src.id + '_0'"
                  @click="handleTrigger(src.id, 0)"
                >
                  全量补全
                </r-button>
              </div>
            </div>
          </div>
        </r-card>
      </r-col>

      <!-- 系统状态与分类概览 -->
      <r-col :xs="24" :lg="10">
        <r-card shadow="never" class="section-card">
          <template #header>
            <div class="card-title-bar">
              <span class="title">分类视频分布概览</span>
              <r-button link type="primary" @click="$router.push('/videos')">
                视频仓库 &rarr;
              </r-button>
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
                <r-link type="primary" href="/openapi.json" target="_blank">
                  v3.0.0 规范 JSON
                </r-link>
              </div>
            </div>
          </div>
        </r-card>
      </r-col>
    </r-row>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import {
  getAdminStats,
  getAnalyticsOverview,
  getSources,
  triggerCollect,
  triggerCollectAll
} from '@/api/admin'
import { getCategories } from '@/api/videos'
import type { AdminStats, AnalyticsOverview, SourceConfig, Category } from '@/types'
import { notify }  from '@/components/radix/feedback'
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
  Plus,
  TrendCharts
} from '@/components/radix/icons'

const stats = ref<Partial<AdminStats>>({})
const sources = ref<SourceConfig[]>([])
const categories = ref<Category[]>([])
const loadingSources = ref(false)
const loadingCategories = ref(false)
const collectingAll = ref(false)
const triggeringId = ref('')

// 埋点流量概览
const analytics = ref<AnalyticsOverview | null>(null)
const loadingAnalytics = ref(false)

const formatNumber = (value?: number) => (value ?? 0).toLocaleString('zh-CN')

// 今日 vs 昨日变化率；昨日为 0 时返回 null（无基准）
const pctDelta = (current?: number, previous?: number): number | null => {
  if (!previous) return null
  return (((current ?? 0) - previous) / previous) * 100
}

const analyticsMetrics = computed(() => {
  const today = analytics.value?.today
  const yesterday = analytics.value?.yesterday
  const total = analytics.value?.total
  return [
    {
      key: 'today_pv',
      label: '今日浏览量 PV',
      value: today?.pv ?? 0,
      delta: pctDelta(today?.pv, yesterday?.pv),
      sub: `网站 ${formatNumber(today?.web_pv)} · App ${formatNumber(today?.app_pv)}`
    },
    {
      key: 'today_uv',
      label: '今日访客 UV',
      value: today?.uv ?? 0,
      delta: pctDelta(today?.uv, yesterday?.uv),
      sub: `网站 ${formatNumber(today?.web_uv)} · App ${formatNumber(today?.app_uv)}`
    },
    {
      key: 'total_pv',
      label: '累计浏览量',
      value: total?.pv ?? 0,
      delta: null,
      sub: `网站 ${formatNumber(total?.web_pv)} · App ${formatNumber(total?.app_pv)}`
    },
    {
      key: 'total_uv',
      label: '累计访客',
      value: total?.uv ?? 0,
      delta: null,
      sub: `网站 ${formatNumber(total?.web_uv)} · App ${formatNumber(total?.app_uv)}`
    }
  ]
})

const trendWindow = computed(() => (analytics.value?.trend || []).slice(-7))

const trendMax = computed(() => Math.max(0, ...trendWindow.value.map((point) => point.pv)))

const trendBars = computed(() => {
  const max = Math.max(1, trendMax.value)
  return trendWindow.value.map((point) => ({
    day: point.day,
    label: point.day.slice(5),
    pv: point.pv,
    uv: point.uv,
    height: `${Math.max(4, Math.round((point.pv / max) * 100))}%`
  }))
})

const loadAnalytics = async () => {
  loadingAnalytics.value = true
  try {
    const res = await getAnalyticsOverview()
    analytics.value = res.data ?? null
  } catch (e) {
    analytics.value = null
  } finally {
    loadingAnalytics.value = false
  }
}

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
      notify(res.msg || '采集任务已在后台启动', 'success')
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
      notify(res.msg || '全网并发采集任务已启动', 'success')
      loadStats()
    }
  } catch (e) {
  } finally {
    collectingAll.value = false
  }
}

onMounted(() => {
  loadStats()
  loadAnalytics()
  loadSources()
  loadCategoriesData()
})
</script>

<style scoped lang="scss">
.dashboard-container {
  display: flex;
  flex-direction: column;
  gap: 12px;

  .stats-row {
    .stat-card {
      transition: all 0.2s ease;

      &:hover {
        transform: translateY(-1px);
        border-color: rgba(79, 110, 242, 0.25);
      }

      .card-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 6px;

        .card-label {
          font-size: 11px;
          color: var(--text-secondary);
          font-weight: 600;
        }

        .card-icon {
          width: 28px;
          height: 28px;
          border-radius: var(--radius-sm);
          display: flex;
          align-items: center;
          justify-content: center;
        }
      }

      .card-value {
        display: flex;
        align-items: baseline;
        gap: 6px;

        .num {
          font-size: 20px;
          font-weight: 700;
          color: var(--text-primary);
          letter-spacing: -0.02em;
        }

        .sub-badge {
          font-size: 9px;
          color: var(--success);
          font-weight: 650;
        }
      }
    }
  }

  .quick-actions-card {
    .action-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      flex-wrap: wrap;
      gap: 10px;

      .title-wrap {
        display: flex;
        align-items: center;
        gap: 6px;
        color: var(--brand);

        .title-icon {
          font-size: 15px;
        }

        .title-text {
          font-size: 12px;
          font-weight: 650;
          color: var(--text-primary);
        }
      }

      .action-buttons {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
      }
    }
  }

  /* 埋点流量概览 */
  .analytics-card {
    .analytics-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 10px;
      flex-wrap: wrap;
      margin-bottom: 10px;

      .title-wrap {
        display: flex;
        align-items: center;
        gap: 6px;
        min-width: 0;
        color: var(--brand);

        .title-icon {
          font-size: 15px;
        }

        .title-text {
          font-size: 12px;
          font-weight: 650;
          color: var(--text-primary);
          white-space: nowrap;
        }

        .title-aux {
          font-size: 10px;
          color: var(--text-secondary);
          white-space: nowrap;
        }
      }
    }

    .analytics-body {
      display: grid;
      grid-template-columns: minmax(0, 1fr) 220px;
      align-items: stretch;
      gap: 10px;
      min-height: 76px;
    }

    .an-metrics {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 10px;
      min-width: 0;
    }

    .an-metric {
      display: flex;
      flex-direction: column;
      gap: 3px;
      min-width: 0;
      padding: 8px 10px;
      border-radius: var(--radius-sm);
      background: rgba(20, 32, 57, 0.03);
      border: 1px solid var(--border-color);

      .an-label {
        font-size: 10.5px;
        font-weight: 600;
        color: var(--text-secondary);
        white-space: nowrap;
      }

      .an-value-row {
        display: flex;
        align-items: baseline;
        gap: 6px;
        min-width: 0;
      }

      .an-value {
        font-size: 17px;
        font-weight: 700;
        color: var(--text-primary);
        letter-spacing: -0.02em;
        font-variant-numeric: tabular-nums;
      }

      .an-delta {
        padding: 0 5px;
        border-radius: var(--radius-pill);
        font-size: 9.5px;
        font-weight: 650;
        font-variant-numeric: tabular-nums;
        white-space: nowrap;

        &.is-up {
          color: #1d7a52;
          background: rgba(47, 158, 110, 0.12);
        }

        &.is-down {
          color: #b93c3c;
          background: rgba(229, 72, 77, 0.1);
        }
      }

      .an-sub {
        overflow: hidden;
        color: var(--text-secondary);
        font-size: 9.5px;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    }

    .an-trend {
      display: flex;
      flex-direction: column;
      gap: 4px;
      min-width: 0;
      padding: 8px 10px;
      border-radius: var(--radius-sm);
      border: 1px solid var(--border-color);
      background: rgba(79, 110, 242, 0.04);

      .an-trend-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
        font-size: 10px;
        color: var(--text-secondary);

        .an-trend-max {
          color: var(--text-regular);
          font-weight: 600;
        }
      }

      .an-bars {
        display: grid;
        grid-template-columns: repeat(7, 1fr);
        align-items: end;
        gap: 4px;
        height: 54px;
      }

      .an-bar-col {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 3px;
        height: 100%;
        min-width: 0;
      }

      .an-bar-track {
        display: flex;
        flex: 1;
        width: 100%;
        align-items: flex-end;
        justify-content: center;
      }

      .an-bar {
        width: 100%;
        max-width: 30px;
        border-radius: 3px 3px 2px 2px;
        background: linear-gradient(180deg, rgba(79, 110, 242, 0.9), rgba(79, 110, 242, 0.45));
        transition: height 0.4s cubic-bezier(0.22, 1, 0.36, 1);
      }

      .an-bar-label {
        color: var(--text-secondary);
        font-size: 8.5px;
        white-space: nowrap;
      }
    }

    .an-empty {
      display: grid;
      grid-column: 1 / -1;
      min-height: 76px;
      place-items: center;
      border: 1px dashed var(--border-color);
      border-radius: var(--radius-sm);
      color: var(--text-secondary);
      font-size: 11px;
    }

    @media (max-width: 1180px) {
      .analytics-body {
        grid-template-columns: minmax(0, 1fr);
      }
    }

    @media (max-width: 900px) {
      .an-metrics {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    }
  }

  .content-row {
    .section-card {
      height: 100%;

      .card-title-bar {
        display: flex;
        align-items: center;
        justify-content: space-between;

        .title {
          font-size: 12px;
          font-weight: 650;
          color: var(--text-primary);
        }
      }

      .source-list {
        display: flex;
        flex-direction: column;
        gap: 8px;

        .source-item {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 8px 10px;
          background: rgba(20, 32, 57, 0.035);
          border: 1px solid var(--border-color);
          border-radius: var(--radius-sm);
          gap: 8px;
          transition: background 0.16s ease, border-color 0.16s ease;

          &:hover {
            background: var(--nav-bg-subtle);
            border-color: rgba(79, 110, 242, 0.25);
          }

          .source-info {
            flex: 1;
            min-width: 0;

            .name-row {
              display: flex;
              align-items: center;
              gap: 6px;
              margin-bottom: 2px;

              .name {
                font-size: 12px;
                font-weight: 650;
                color: var(--text-primary);
              }
            }

            .api-url {
              font-size: 10px;
              color: var(--text-secondary);
              overflow: hidden;
              text-overflow: ellipsis;
              white-space: nowrap;
            }
          }

          .source-ops {
            display: flex;
            gap: 4px;
            flex-shrink: 0;
          }
        }
      }

      .category-summary {
        display: flex;
        flex-direction: column;
        gap: 10px;

        .cat-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(95px, 1fr));
          gap: 6px;

          .cat-chip {
            padding: 5px 8px;
            background: rgba(79, 110, 242, 0.06);
            border: 1px solid rgba(79, 110, 242, 0.16);
            border-radius: var(--radius-xs);
            display: flex;
            flex-direction: column;

            .cat-name {
              font-size: 11px;
              font-weight: 650;
              color: var(--brand);
            }

            .cat-id {
              font-size: 9px;
              color: var(--text-secondary);
            }
          }
        }

        .system-status-box {
          border-top: 1px solid var(--nav-border-light);
          padding-top: 10px;
          display: flex;
          flex-direction: column;
          gap: 6px;
          font-size: 11px;

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
        padding: 20px;
        color: var(--text-secondary);
        font-size: 11px;
      }
    }
  }
}

html.dark .analytics-card {
  .an-metric {
    background: rgba(255, 255, 255, 0.04);
  }

  .an-trend {
    background: rgba(126, 148, 255, 0.07);
  }

  .an-delta.is-up {
    color: #67d3a1;
    background: rgba(47, 158, 110, 0.18);
  }

  .an-delta.is-down {
    color: #f28b8e;
    background: rgba(229, 72, 77, 0.16);
  }
}
</style>
