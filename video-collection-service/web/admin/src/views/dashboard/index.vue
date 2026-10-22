<template>
  <div class="dashboard-container">
    <r-card shadow="never" class="section-card welcome-card">
      <div class="welcome-row">
        <div class="welcome-copy">
          <span class="eyebrow">内容运营工作台</span>
          <h1>视频、资讯与业务数据，一站管理</h1>
          <p>资源库按类型浏览；使魔负责采集入库；系统日志记录登录与关键操作。</p>
        </div>
        <div class="welcome-actions">
          <r-button type="primary" @click="$router.push('/resources')">进入资源库</r-button>
          <r-button @click="$router.push('/business-types')">业务类型</r-button>
          <r-button @click="$router.push('/scheduler')">使魔调度</r-button>
        </div>
      </div>
    </r-card>

    <r-row :gutter="12" class="stats-row">
      <r-col :xs="12" :sm="8" :md="4" v-for="item in statCards" :key="item.key">
        <r-card
          shadow="hover"
          class="stat-card is-clickable"
          :body-style="{ padding: '12px 14px' }"
          @click="item.to && $router.push(item.to)"
        >
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

    <r-card shadow="never" class="section-card shortcuts-card">
      <div class="action-header">
        <div class="title-wrap">
          <r-icon class="title-icon"><Lightning /></r-icon>
          <span class="title-text">常用入口</span>
          <span class="title-aux">按内容类型快速跳转</span>
        </div>
      </div>
      <div class="shortcut-grid">
        <button
          v-for="item in shortcuts"
          :key="item.path"
          type="button"
          class="shortcut-item"
          @click="$router.push(item.path)"
        >
          <div class="shortcut-icon" :style="{ background: item.iconBg, color: item.iconColor }">
            <r-icon><component :is="item.icon" /></r-icon>
          </div>
          <div class="shortcut-copy">
            <strong>{{ item.title }}</strong>
            <span>{{ item.desc }}</span>
          </div>
          <span class="shortcut-arrow">→</span>
        </button>
      </div>
    </r-card>

    <r-card shadow="never" class="section-card quick-actions-card">
      <div class="action-header">
        <div class="title-wrap">
          <r-icon class="title-icon"><Refresh /></r-icon>
          <span class="title-text">使魔即时采集</span>
          <span class="title-aux">可按业务类型入库到视频 / 资讯 / 自定义表</span>
        </div>
        <div class="action-buttons">
          <r-button type="primary" :loading="collectingAll" @click="handleCollectAll(24)">
            <r-icon><Refresh /></r-icon>近 24 小时增量
          </r-button>
          <r-button type="warning" plain :loading="collectingAll" @click="handleCollectAll(0)">
            <r-icon><Download /></r-icon>历史全量
          </r-button>
          <r-button @click="$router.push('/sources')">
            <r-icon><Plus /></r-icon>管理使魔节点
          </r-button>
        </div>
      </div>
    </r-card>

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

    <r-row :gutter="12" class="content-row">
      <r-col :xs="24" :lg="14">
        <r-card shadow="never" class="section-card">
          <template #header>
            <div class="card-title-bar">
              <span class="title">活跃使魔节点</span>
              <r-button link type="primary" @click="$router.push('/sources')">
                管理节点 &rarr;
              </r-button>
            </div>
          </template>

          <div v-loading="loadingSources" class="source-list">
            <div v-if="sources.length === 0" class="empty-tip">暂无配置采集源，可先添加使魔节点</div>
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
                  增量
                </r-button>
                <r-button
                  size="small"
                  type="warning"
                  plain
                  :loading="triggeringId === src.id + '_0'"
                  @click="handleTrigger(src.id, 0)"
                >
                  全量
                </r-button>
              </div>
            </div>
          </div>
        </r-card>
      </r-col>

      <r-col :xs="24" :lg="10">
        <r-card shadow="never" class="section-card">
          <template #header>
            <div class="card-title-bar">
              <span class="title">内容库速览</span>
              <r-button link type="primary" @click="$router.push('/resources')">
                打开资源库 &rarr;
              </r-button>
            </div>
          </template>

          <div class="content-overview">
            <button
              v-for="item in contentOverview"
              :key="item.path"
              type="button"
              class="overview-item"
              @click="$router.push(item.path)"
            >
              <div class="overview-top">
                <span class="overview-label">{{ item.label }}</span>
                <span class="overview-count">{{ item.count }}</span>
              </div>
              <p>{{ item.desc }}</p>
            </button>

            <div v-loading="loadingCategories" class="category-summary">
              <div class="cat-head">
                <span>视频分类</span>
                <r-button link type="primary" @click="$router.push('/resources/video')">查看 →</r-button>
              </div>
              <div v-if="categories.length === 0" class="empty-tip">暂无分类数据</div>
              <div v-else class="cat-grid">
                <div v-for="cat in categories.slice(0, 6)" :key="cat.id ?? cat.type_id" class="cat-chip">
                  <span class="cat-name">{{ cat.name ?? cat.type_name }}</span>
                  <span class="cat-id">ID: {{ cat.id ?? cat.type_id }}</span>
                </div>
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
import { notify } from '@/components/radix/feedback'
import {
  Connection,
  Film,
  Calendar,
  User,
  Lightning,
  Refresh,
  Download,
  Plus,
  TrendCharts,
  Document,
  Reading,
  Clock,
  SetUp
} from '@/components/radix/icons'

const stats = ref<Partial<AdminStats>>({})
const sources = ref<SourceConfig[]>([])
const categories = ref<Category[]>([])
const loadingSources = ref(false)
const loadingCategories = ref(false)
const collectingAll = ref(false)
const triggeringId = ref('')

const analytics = ref<AnalyticsOverview | null>(null)
const loadingAnalytics = ref(false)

const formatNumber = (value?: number) => (value ?? 0).toLocaleString('zh-CN')

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
  } catch {
    analytics.value = null
  } finally {
    loadingAnalytics.value = false
  }
}

const shortcuts = [
  {
    path: '/resources/video',
    title: '视频资源',
    desc: '番剧与点播内容',
    icon: Film,
    iconBg: 'rgba(16, 185, 129, 0.15)',
    iconColor: '#10b981'
  },
  {
    path: '/resources/news',
    title: '资讯文章',
    desc: '发布与维护站内资讯',
    icon: Reading,
    iconBg: 'rgba(59, 130, 246, 0.15)',
    iconColor: '#3b82f6'
  },
  {
    path: '/business-types',
    title: '业务类型',
    desc: '自定义字段与入库结构',
    icon: Document,
    iconBg: 'rgba(139, 92, 246, 0.15)',
    iconColor: '#8b5cf6'
  },
  {
    path: '/resources',
    title: '资源库总览',
    desc: '视频 / 资讯 / 业务数据',
    icon: SetUp,
    iconBg: 'rgba(99, 102, 241, 0.15)',
    iconColor: '#6366f1'
  },
  {
    path: '/scheduler',
    title: '使魔调度',
    desc: '定时采集与任务进度',
    icon: Clock,
    iconBg: 'rgba(245, 158, 11, 0.15)',
    iconColor: '#f59e0b'
  },
  {
    path: '/system-logs',
    title: '系统日志',
    desc: '登录、业务与操作记录',
    icon: Document,
    iconBg: 'rgba(244, 63, 94, 0.12)',
    iconColor: '#f43f5e'
  }
]

const contentOverview = computed(() => [
  {
    path: '/resources/video',
    label: '视频',
    count: formatNumber(stats.value.total_videos),
    desc: '资源库 · 视频页'
  },
  {
    path: '/resources/news',
    label: '资讯',
    count: formatNumber(stats.value.total_news),
    desc: '资源库 · 资讯页'
  },
  {
    path: '/business-types',
    label: '业务类型',
    count: formatNumber(stats.value.total_business_types),
    desc: '含系统内置与自定义'
  }
])

const statCards = computed(() => [
  {
    key: 'total_videos' as const,
    label: '视频库存',
    icon: Film,
    iconBg: 'rgba(16, 185, 129, 0.15)',
    iconColor: '#10b981',
    to: '/resources/video'
  },
  {
    key: 'total_news' as const,
    label: '资讯文章',
    icon: Reading,
    iconBg: 'rgba(59, 130, 246, 0.15)',
    iconColor: '#3b82f6',
    to: '/resources/news'
  },
  {
    key: 'total_business_types' as const,
    label: '业务类型',
    icon: Document,
    iconBg: 'rgba(139, 92, 246, 0.15)',
    iconColor: '#8b5cf6',
    to: '/business-types'
  },
  {
    key: 'total_sources' as const,
    label: '使魔节点',
    icon: Connection,
    iconBg: 'rgba(99, 102, 241, 0.15)',
    iconColor: '#6366f1',
    sub: `启用 ${stats.value.active_sources ?? 0}`,
    to: '/sources'
  },
  {
    key: 'today_updated' as const,
    label: '今日视频更新',
    icon: Calendar,
    iconBg: 'rgba(245, 158, 11, 0.15)',
    iconColor: '#f59e0b',
    to: '/resources/video'
  },
  {
    key: 'total_users' as const,
    label: '系统用户',
    icon: User,
    iconBg: 'rgba(14, 165, 233, 0.15)',
    iconColor: '#0ea5e9',
    to: '/users'
  }
])

const loadStats = async () => {
  try {
    const res = await getAdminStats()
    if (res.code === 1 && res.data) {
      stats.value = res.data
    }
  } catch {}
}

const loadSources = async () => {
  loadingSources.value = true
  try {
    const res = await getSources()
    if (res.code === 1 && res.data) {
      sources.value = res.data
    }
  } catch {
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
  } catch {
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
  } catch {
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
  } catch {
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

  .welcome-card {
    .welcome-row {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: 16px;
      flex-wrap: wrap;
    }

    .welcome-copy {
      min-width: 0;
      max-width: 720px;

      .eyebrow {
        display: inline-block;
        margin-bottom: 6px;
        color: var(--brand);
        font-size: 11px;
        font-weight: 700;
        letter-spacing: 0.04em;
      }

      h1 {
        margin: 0 0 6px;
        color: var(--text-primary);
        font-size: 18px;
        font-weight: 700;
        letter-spacing: -0.02em;
        line-height: 1.35;
      }

      p {
        margin: 0;
        color: var(--text-secondary);
        font-size: 12px;
        line-height: 1.55;
      }
    }

    .welcome-actions {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
    }
  }

  .stats-row {
    .stat-card {
      transition: all 0.2s ease;

      &.is-clickable {
        cursor: pointer;
      }

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

  .shortcuts-card,
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
        min-width: 0;

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

      .action-buttons {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
      }
    }
  }

  .shortcut-grid {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 10px;
    margin-top: 12px;
  }

  .shortcut-item {
    display: flex;
    align-items: center;
    gap: 10px;
    width: 100%;
    padding: 10px 12px;
    border: 1px solid var(--border-color);
    border-radius: var(--radius-sm);
    background: rgba(20, 32, 57, 0.03);
    text-align: left;
    cursor: pointer;
    transition: border-color 0.16s ease, background 0.16s ease, transform 0.16s ease;

    &:hover {
      border-color: rgba(79, 110, 242, 0.28);
      background: var(--nav-bg-subtle);
      transform: translateY(-1px);
    }

    .shortcut-icon {
      width: 34px;
      height: 34px;
      border-radius: var(--radius-sm);
      display: grid;
      place-items: center;
      flex-shrink: 0;
    }

    .shortcut-copy {
      min-width: 0;
      flex: 1;
      display: flex;
      flex-direction: column;
      gap: 2px;

      strong {
        color: var(--text-primary);
        font-size: 12px;
        font-weight: 650;
      }

      span {
        color: var(--text-secondary);
        font-size: 10px;
        line-height: 1.4;
      }
    }

    .shortcut-arrow {
      color: var(--text-secondary);
      font-size: 12px;
      flex-shrink: 0;
    }
  }

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

      .content-overview {
        display: flex;
        flex-direction: column;
        gap: 10px;

        .overview-item {
          display: block;
          width: 100%;
          padding: 10px 12px;
          border: 1px solid var(--border-color);
          border-radius: var(--radius-sm);
          background: rgba(20, 32, 57, 0.03);
          text-align: left;
          cursor: pointer;
          transition: border-color 0.16s ease, background 0.16s ease;

          &:hover {
            border-color: rgba(79, 110, 242, 0.28);
            background: var(--nav-bg-subtle);
          }

          .overview-top {
            display: flex;
            align-items: baseline;
            justify-content: space-between;
            gap: 8px;
            margin-bottom: 2px;
          }

          .overview-label {
            color: var(--text-secondary);
            font-size: 11px;
            font-weight: 600;
          }

          .overview-count {
            color: var(--text-primary);
            font-size: 18px;
            font-weight: 700;
            letter-spacing: -0.02em;
            font-variant-numeric: tabular-nums;
          }

          p {
            margin: 0;
            color: var(--text-secondary);
            font-size: 10px;
          }
        }
      }

      .category-summary {
        display: flex;
        flex-direction: column;
        gap: 8px;
        padding-top: 4px;

        .cat-head {
          display: flex;
          align-items: center;
          justify-content: space-between;
          color: var(--text-primary);
          font-size: 11px;
          font-weight: 650;
        }

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
      }

      .empty-tip {
        text-align: center;
        padding: 20px;
        color: var(--text-secondary);
        font-size: 11px;
      }
    }
  }

  @media (max-width: 1100px) {
    .shortcut-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }

  @media (max-width: 640px) {
    .shortcut-grid {
      grid-template-columns: minmax(0, 1fr);
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
