<template>
  <div class="analytics-page">
    <!-- 页头：标题 + 数据口径 + 刷新 -->
    <header class="page-header">
      <div class="heading-copy">
        <h1 class="page-title">埋点信息预览</h1>
        <p class="page-subtitle">
          网站 / App 浏览量（PV）与独立访客（UV）统计。PV 按 page_view 埋点事件计数，UV 按当日去重访客统计。
        </p>
      </div>
      <r-button :loading="loading" @click="loadData">
        <r-icon><Refresh /></r-icon>刷新
      </r-button>
    </header>

    <div v-loading="loading" class="analytics-body">
      <!-- 空态：埋点尚未产生数据 -->
      <r-card v-if="!loading && isEmpty" shadow="never" class="empty-card">
        <r-empty description="暂无埋点数据">
          <p class="empty-hint">
            网站端已内置 tracker.js 自动上报；App 端在进入首页、详情、播放与搜索时上报。
            部署后产生首批访问即可看到 PV / UV 统计。
          </p>
        </r-empty>
      </r-card>

      <template v-else>
        <!-- 1. 核心指标：今日 / 累计 -->
        <r-card shadow="never" class="kpi-card">
          <div class="kpi-grid">
            <div class="kpi-item">
              <span class="kpi-label">今日浏览量 PV</span>
              <span class="kpi-value">{{ formatNumber(overview?.today.pv) }}</span>
              <span class="kpi-meta">
                <span class="delta" :class="deltaClass(delta('pv'))">{{ deltaText(delta('pv')) }}</span>
                <span class="kpi-sub">网站 {{ formatNumber(overview?.today.web_pv) }} · App {{ formatNumber(overview?.today.app_pv) }}</span>
              </span>
            </div>
            <div class="kpi-item">
              <span class="kpi-label">今日访客 UV</span>
              <span class="kpi-value">{{ formatNumber(overview?.today.uv) }}</span>
              <span class="kpi-meta">
                <span class="delta" :class="deltaClass(delta('uv'))">{{ deltaText(delta('uv')) }}</span>
                <span class="kpi-sub">网站 {{ formatNumber(overview?.today.web_uv) }} · App {{ formatNumber(overview?.today.app_uv) }}</span>
              </span>
            </div>
            <div class="kpi-item">
              <span class="kpi-label">累计浏览量</span>
              <span class="kpi-value">{{ formatNumber(overview?.total.pv) }}</span>
              <span class="kpi-meta">
                <span class="kpi-sub">网站 {{ formatNumber(overview?.total.web_pv) }} · App {{ formatNumber(overview?.total.app_pv) }}</span>
              </span>
            </div>
            <div class="kpi-item">
              <span class="kpi-label">累计访客</span>
              <span class="kpi-value">{{ formatNumber(overview?.total.uv) }}</span>
              <span class="kpi-meta">
                <span class="kpi-sub">网站 {{ formatNumber(overview?.total.web_uv) }} · App {{ formatNumber(overview?.total.app_uv) }}</span>
              </span>
            </div>
          </div>
        </r-card>

        <!-- 2. 趋势 + 平台分布 -->
        <div class="section-grid">
          <r-card shadow="never" class="trend-card">
            <div class="card-title-bar">
              <span class="title">近 30 天 PV / UV 趋势</span>
              <span class="title-aux">网站与 App 浏览量堆叠 · 访客折线</span>
            </div>
            <v-chart class="trend-chart" :option="trendOption" autoresize />
          </r-card>

          <r-card shadow="never" class="platform-card">
            <div class="card-title-bar">
              <span class="title">平台分布</span>
              <span class="title-aux">近 30 天</span>
            </div>
            <div class="platform-list">
              <div v-for="item in overview?.platforms || []" :key="item.platform" class="platform-item" :data-platform="item.platform">
                <span class="platform-icon" aria-hidden="true">
                  <Monitor v-if="item.platform === 'web'" :size="18" />
                  <Smartphone v-else :size="18" />
                </span>
                <div class="platform-copy">
                  <strong>{{ item.platform === 'web' ? '网站 Web' : 'App 客户端' }}</strong>
                  <div class="platform-bar">
                    <div class="platform-bar-fill" :style="{ width: Math.min(100, item.share) + '%' }" />
                  </div>
                </div>
                <div class="platform-nums">
                  <span class="num">{{ formatNumber(item.pv) }} <small>PV</small></span>
                  <span class="num num-soft">{{ formatNumber(item.uv) }} <small>UV</small></span>
                  <span class="share">{{ item.share }}%</span>
                </div>
              </div>
            </div>
            <p class="platform-note">UV 按匿名访客 ID 去重；同一访客当日跨平台访问按设备分别计数。</p>
          </r-card>
        </div>

        <!-- 3. 热门页面 + 事件分布 -->
        <div class="section-grid section-grid--details">
          <r-card shadow="never" class="pages-card">
            <div class="card-title-bar">
              <span class="title">热门页面 TOP 8</span>
              <span class="title-aux">近 7 天 · 按浏览量</span>
            </div>
            <r-table :data="overview?.top_pages || []" empty-text="近 7 天暂无页面浏览数据">
              <r-table-column label="页面" min-width="220">
                <template #default="{ row }">
                  <code class="page-path">{{ row.page }}</code>
                </template>
              </r-table-column>
              <r-table-column label="浏览量" width="110" align="right">
                <template #default="{ row }">
                  <span class="num">{{ formatNumber(row.pv) }}</span>
                </template>
              </r-table-column>
              <r-table-column label="平均停留" width="110" align="right">
                <template #default="{ row }">
                  <span class="num num-soft">{{ formatDwell(row.avg_dwell_ms) }}</span>
                </template>
              </r-table-column>
            </r-table>
          </r-card>

          <r-card shadow="never" class="events-card">
            <div class="card-title-bar">
              <span class="title">埋点事件分布</span>
              <span class="title-aux">近 7 天</span>
            </div>
            <div v-if="!(overview?.events || []).length" class="empty-tip">近 7 天暂无埋点事件</div>
            <ul v-else class="event-list">
              <li v-for="item in overview?.events || []" :key="item.event" class="event-item">
                <span class="event-name">{{ item.name }}</span>
                <div class="event-bar">
                  <div class="event-bar-fill" :style="{ width: eventWidth(item.count) }" />
                </div>
                <span class="event-count">{{ formatNumber(item.count) }}</span>
              </li>
            </ul>
          </r-card>
        </div>
      </template>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { use } from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import { BarChart, LineChart } from 'echarts/charts'
import { GridComponent, LegendComponent, TooltipComponent } from 'echarts/components'
import VChart from 'vue-echarts'
import { getAnalyticsOverview } from '@/api/admin'
import type { AnalyticsOverview } from '@/types'
import { useAppStore } from '@/store/app'
import { Monitor, Refresh, Smartphone } from '@/components/radix/icons'

use([CanvasRenderer, BarChart, LineChart, GridComponent, LegendComponent, TooltipComponent])

const appStore = useAppStore()
const overview = ref<AnalyticsOverview | null>(null)
const loading = ref(false)

const isEmpty = computed(() => (overview.value?.total.pv ?? 0) === 0 && (overview.value?.total.uv ?? 0) === 0)

async function loadData() {
  loading.value = true
  try {
    const res = await getAnalyticsOverview()
    overview.value = res.data ?? null
  } catch {
    overview.value = null
  } finally {
    loading.value = false
  }
}

// ---------- 格式化 ----------

function formatNumber(value?: number) {
  return (value ?? 0).toLocaleString('zh-CN')
}

function formatDwell(ms?: number) {
  const total = Math.max(0, Math.round((ms ?? 0) / 1000))
  if (total < 60) return `${total}s`
  const minutes = Math.floor(total / 60)
  const seconds = total % 60
  return seconds ? `${minutes}m${seconds}s` : `${minutes}m`
}

// 今日 vs 昨日变化率（昨日为 0 时返回 null 表示无基准）
function delta(key: 'pv' | 'uv'): number | null {
  const today = overview.value?.today[key] ?? 0
  const yesterday = overview.value?.yesterday[key] ?? 0
  if (!yesterday) return null
  return ((today - yesterday) / yesterday) * 100
}

function deltaText(value: number | null) {
  if (value === null) return '—'
  const sign = value > 0 ? '+' : ''
  return `${sign}${value.toFixed(1)}%`
}

function deltaClass(value: number | null) {
  if (value === null || value === 0) return 'delta--flat'
  return value > 0 ? 'delta--up' : 'delta--down'
}

function eventWidth(count: number) {
  const max = Math.max(1, ...(overview.value?.events || []).map((item) => item.count))
  return `${Math.max(3, Math.round((count / max) * 100))}%`
}

// ---------- 趋势图 ----------

const trendOption = computed(() => {
  const trend = overview.value?.trend || []
  const inkColor = appStore.isDark ? '#e8ecf6' : '#1c2a47'
  const labelColor = appStore.isDark ? '#8f9cb5' : '#71809b'
  const splitColor = appStore.isDark ? 'rgba(143,156,181,0.14)' : 'rgba(113,128,155,0.14)'
  return {
    animationDuration: 420,
    grid: { top: 40, left: 8, right: 12, bottom: 8, containLabel: true },
    tooltip: {
      trigger: 'axis',
      backgroundColor: 'rgba(255,255,255,0.88)',
      borderColor: 'rgba(255,255,255,0.6)',
      textStyle: { color: '#182136' },
      extraCssText:
        'backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px); border-radius: 12px; box-shadow: 0 12px 32px rgba(22,33,58,0.16);',
      axisPointer: { type: 'shadow', shadowStyle: { color: 'rgba(79,110,242,0.06)' } },
    },
    legend: {
      top: 4,
      right: 4,
      itemWidth: 10,
      itemHeight: 10,
      icon: 'roundRect',
      textStyle: { color: labelColor, fontSize: 11 },
    },
    xAxis: {
      type: 'category',
      data: trend.map((point) => point.day.slice(5)),
      axisLine: { lineStyle: { color: splitColor } },
      axisTick: { show: false },
      axisLabel: { color: labelColor, fontSize: 10.5 },
    },
    yAxis: {
      type: 'value',
      minInterval: 1,
      splitLine: { lineStyle: { color: splitColor } },
      axisLabel: { color: labelColor, fontSize: 10.5 },
    },
    series: [
      {
        name: '网站 PV',
        type: 'bar',
        stack: 'pv',
        barMaxWidth: 14,
        itemStyle: { color: 'rgba(79,110,242,0.72)' },
        data: trend.map((point) => point.web_pv),
      },
      {
        name: 'App PV',
        type: 'bar',
        stack: 'pv',
        barMaxWidth: 14,
        itemStyle: { color: 'rgba(43,185,168,0.78)', borderRadius: [4, 4, 0, 0] },
        data: trend.map((point) => point.app_pv),
      },
      {
        name: 'UV',
        type: 'line',
        smooth: true,
        symbol: 'circle',
        symbolSize: 5,
        lineStyle: { width: 2, color: inkColor },
        itemStyle: { color: inkColor, borderColor: 'rgba(255,255,255,0.85)', borderWidth: 1 },
        data: trend.map((point) => point.uv),
      },
    ],
  }
})

onMounted(loadData)
</script>

<style scoped lang="scss">
.analytics-page {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.page-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;

  .heading-copy {
    min-width: 0;
  }

  .page-title {
    margin: 0 0 3px;
    font-size: 13px;
    font-weight: 700;
    color: var(--text-primary);
    letter-spacing: -0.01em;
  }

  .page-subtitle {
    margin: 0;
    font-size: 10px;
    color: var(--text-secondary);
  }
}

.analytics-body {
  display: flex;
  flex-direction: column;
  gap: 12px;
  min-height: 240px;
}

.empty-card {
  .empty-hint {
    margin: 8px 0 0;
    color: var(--text-secondary);
    font-size: 11px;
    line-height: 1.6;
  }
}

// ---------- KPI ----------

.kpi-card :deep(.r-card__body) {
  padding: 0;
}

.kpi-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
}

.kpi-item {
  display: flex;
  flex-direction: column;
  gap: 4px;
  padding: 12px 14px;

  & + .kpi-item {
    border-left: 1px solid var(--border-color-lighter);
  }

  .kpi-label {
    color: var(--text-secondary);
    font-size: 10.5px;
    font-weight: 600;
    letter-spacing: 0.02em;
  }

  .kpi-value {
    color: var(--text-primary);
    font-size: 20px;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    letter-spacing: -0.02em;
    line-height: 1.15;
  }

  .kpi-meta {
    display: flex;
    align-items: center;
    gap: 8px;
    flex-wrap: wrap;
  }

  .kpi-sub {
    color: var(--text-secondary);
    font-size: 10px;
  }
}

.delta {
  padding: 1px 6px;
  border-radius: var(--radius-pill);
  font-size: 9.5px;
  font-weight: 650;
  font-variant-numeric: tabular-nums;

  &.delta--up {
    color: #1d7a52;
    background: rgba(47, 158, 110, 0.12);
  }

  &.delta--down {
    color: #b93c3c;
    background: rgba(229, 72, 77, 0.1);
  }

  &.delta--flat {
    color: var(--text-secondary);
    background: rgba(113, 128, 155, 0.1);
  }
}

// ---------- 分区 ----------

.section-grid {
  display: grid;
  grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
  gap: 12px;

  &--details {
    grid-template-columns: minmax(0, 7fr) minmax(0, 5fr);
  }
}

.card-title-bar {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 12px;

  .title {
    color: var(--text-primary);
    font-size: 12px;
    font-weight: 650;
  }

  .title-aux {
    color: var(--text-secondary);
    font-size: 10px;
  }
}

.trend-chart {
  width: 100%;
  height: 280px;
}

// ---------- 平台分布 ----------

.platform-list {
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.platform-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 14px;
  border-radius: var(--radius-md);
  background: rgba(20, 32, 57, 0.03);
  transition: background 0.16s ease;

  &:hover {
    background: rgba(79, 110, 242, 0.06);
  }

  .platform-icon {
    display: inline-flex;
    width: 36px;
    height: 36px;
    flex: 0 0 36px;
    align-items: center;
    justify-content: center;
    border-radius: var(--radius-sm);
    color: #fff;
    background: linear-gradient(135deg, #5d7af5, #3d5ce0);
    box-shadow: 0 2px 8px rgba(79, 110, 242, 0.22);
  }

  &[data-platform='app'] .platform-icon {
    background: linear-gradient(135deg, #3fbfae, #2b9c8f);
    box-shadow: 0 2px 8px rgba(43, 185, 168, 0.22);
  }

  .platform-copy {
    display: flex;
    flex: 1;
    min-width: 0;
    flex-direction: column;
    gap: 6px;

    strong {
      color: var(--text-primary);
      font-size: 12.5px;
      font-weight: 650;
    }
  }

  .platform-bar {
    height: 5px;
    border-radius: var(--radius-pill);
    background: rgba(20, 32, 57, 0.07);
    overflow: hidden;

    .platform-bar-fill {
      height: 100%;
      border-radius: var(--radius-pill);
      background: linear-gradient(90deg, rgba(79, 110, 242, 0.85), rgba(43, 185, 168, 0.85));
      transition: width 0.45s cubic-bezier(0.22, 1, 0.36, 1);
    }
  }

  .platform-nums {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    gap: 2px;
    font-variant-numeric: tabular-nums;

    .num {
      color: var(--text-primary);
      font-size: 13px;
      font-weight: 650;

      small {
        color: var(--text-secondary);
        font-size: 10px;
        font-weight: 500;
      }
    }

    .num-soft {
      color: var(--text-regular);
      font-weight: 550;
    }

    .share {
      color: var(--text-secondary);
      font-size: 10.5px;
    }
  }
}

.platform-note {
  margin: 14px 0 0;
  color: var(--text-secondary);
  font-size: 11px;
  line-height: 1.7;
}

// ---------- 热门页面 / 事件 ----------

.page-path {
  padding: 2px 8px;
  border-radius: var(--radius-xs);
  background: rgba(20, 32, 57, 0.05);
  color: var(--text-regular);
  font-size: 11.5px;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  word-break: break-all;
}

.num {
  color: var(--text-primary);
  font-variant-numeric: tabular-nums;
  font-weight: 600;
}

.num-soft {
  color: var(--text-regular);
  font-weight: 500;
}

.event-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
  margin: 0;
  padding: 0;
  list-style: none;
}

.event-item {
  display: flex;
  align-items: center;
  gap: 12px;

  .event-name {
    width: 84px;
    flex: 0 0 84px;
    color: var(--text-regular);
    font-size: 12px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .event-bar {
    flex: 1;
    height: 8px;
    border-radius: var(--radius-pill);
    background: rgba(20, 32, 57, 0.05);
    overflow: hidden;

    .event-bar-fill {
      height: 100%;
      border-radius: var(--radius-pill);
      background: linear-gradient(90deg, rgba(79, 110, 242, 0.85), rgba(139, 124, 246, 0.8));
      transition: width 0.45s cubic-bezier(0.22, 1, 0.36, 1);
    }
  }

  .event-count {
    width: 64px;
    flex: 0 0 64px;
    color: var(--text-primary);
    font-size: 12px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    text-align: right;
  }
}

// ---------- 响应式 ----------

@media (max-width: 1080px) {
  .section-grid,
  .section-grid--details {
    grid-template-columns: minmax(0, 1fr);
  }
}

@media (max-width: 768px) {
  .kpi-grid {
    grid-template-columns: repeat(2, 1fr);
  }

  .kpi-item + .kpi-item {
    border-left: 0;
  }

  .kpi-item:nth-child(even) {
    border-left: 1px solid var(--border-color-lighter);
  }

  .kpi-item:nth-child(n + 3) {
    border-top: 1px solid var(--border-color-lighter);
  }
}

// ---------- 暗黑模式 ----------
html.dark .platform-item {
  background: rgba(255, 255, 255, 0.04);

  &:hover {
    background: rgba(126, 148, 255, 0.08);
  }
}

html.dark .platform-bar,
html.dark .event-bar {
  background: rgba(255, 255, 255, 0.07);
}

html.dark .page-path {
  background: rgba(255, 255, 255, 0.06);
}

html.dark .delta--up {
  color: #67d3a1;
  background: rgba(47, 158, 110, 0.18);
}

html.dark .delta--down {
  color: #f28b8e;
  background: rgba(229, 72, 77, 0.16);
}
</style>
