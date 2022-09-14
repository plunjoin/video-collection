<template>
  <div class="logs-page">
    <el-card shadow="never" class="main-card">
      <div class="page-header">
        <div class="header-left">
          <span class="page-title">系统采集与运行审计日志</span>
          <span class="sub-desc">实时监控多源数据采集、任务调度及后台接口操作日志</span>
        </div>
        <div class="header-right">
          <el-select v-model="limit" style="width: 120px" @change="loadData">
            <el-option label="最近 50 条" :value="50" />
            <el-option label="最近 100 条" :value="100" />
            <el-option label="最近 200 条" :value="200" />
            <el-option label="最近 500 条" :value="500" />
          </el-select>

          <el-switch
            v-model="autoRefresh"
            active-text="每5s自动刷新"
            @change="handleAutoRefreshChange"
          />

          <el-button @click="loadData" :loading="loading">
            <el-icon><RefreshRight /></el-icon>刷新
          </el-button>
        </div>
      </div>

      <!-- 控制台风格日志视窗 -->
      <div class="terminal-box" v-loading="loading">
        <div class="terminal-header">
          <div class="dots">
            <span class="dot dot-red"></span>
            <span class="dot dot-yellow"></span>
            <span class="dot dot-green"></span>
          </div>
          <span class="terminal-title">COLLECTION ENGINE LOG STREAM</span>
          <span class="log-count">共 {{ logList.length }} 条</span>
        </div>
        <div class="terminal-body" ref="terminalBodyRef">
          <div v-if="logList.length === 0" class="empty-log">暂无最新日志记录</div>
          <div
            v-for="(log, idx) in logList"
            :key="idx"
            class="log-row"
            :class="'level-' + (log.level || 'info').toLowerCase()"
          >
            <span class="log-time">[{{ formatDate(log.time) }}]</span>
            <span class="log-level">[{{ (log.level || 'INFO').toUpperCase() }}]</span>
            <span class="log-module" v-if="log.module">[{{ log.module }}]</span>
            <span class="log-msg">{{ log.message }}</span>
          </div>
        </div>
      </div>
    </el-card>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { getLogs } from '@/api/admin'
import type { LogEntry } from '@/types'
import { RefreshRight } from '@element-plus/icons-vue'

const loading = ref(false)
const limit = ref(100)
const autoRefresh = ref(false)
const logList = ref<LogEntry[]>([])
const terminalBodyRef = ref<HTMLElement>()
let timer: any = null

const formatDate = (val?: string) => {
  if (!val) return '-'
  return val.replace('T', ' ').substring(0, 19)
}

const loadData = async () => {
  try {
    const res = await getLogs(limit.value)
    if (res.code === 1 && res.data) {
      logList.value = res.data
    }
  } catch (e) {}
}

const handleAutoRefreshChange = (val: boolean) => {
  if (timer) {
    clearInterval(timer)
    timer = null
  }
  if (val) {
    timer = setInterval(() => {
      loadData()
    }, 5000)
  }
}

onMounted(() => {
  loadData()
})

onUnmounted(() => {
  if (timer) {
    clearInterval(timer)
  }
})
</script>

<style scoped lang="scss">
.logs-page {
  .main-card {
    border-radius: 12px;
    border: 1px solid var(--border-color);

    .page-header {
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
        align-items: center;
        gap: 16px;
      }
    }

    .terminal-box {
      border-radius: 10px;
      background-color: #0b0f19;
      border: 1px solid #1e293b;
      overflow: hidden;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;

      .terminal-header {
        height: 36px;
        background-color: #0f172a;
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 0 16px;
        border-bottom: 1px solid #1e293b;

        .dots {
          display: flex;
          gap: 6px;
          .dot {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            &.dot-red { background: #ef4444; }
            &.dot-yellow { background: #f59e0b; }
            &.dot-green { background: #10b981; }
          }
        }

        .terminal-title {
          font-size: 11px;
          letter-spacing: 1px;
          color: #94a3b8;
          font-weight: 600;
        }

        .log-count {
          font-size: 11px;
          color: #64748b;
        }
      }

      .terminal-body {
        padding: 16px;
        max-height: 600px;
        min-height: 360px;
        overflow-y: auto;
        display: flex;
        flex-direction: column;
        gap: 6px;
        font-size: 12px;
        line-height: 1.6;

        .log-row {
          display: flex;
          gap: 8px;
          white-space: pre-wrap;
          word-break: break-all;

          .log-time {
            color: #64748b;
            flex-shrink: 0;
          }

          .log-level {
            font-weight: 600;
            flex-shrink: 0;
          }

          .log-module {
            color: #38bdf8;
            flex-shrink: 0;
          }

          .log-msg {
            color: #cbd5e1;
          }

          &.level-info .log-level { color: #3b82f6; }
          &.level-warn .log-level { color: #f59e0b; }
          &.level-warn .log-msg { color: #fef08a; }
          &.level-error .log-level { color: #ef4444; }
          &.level-error .log-msg { color: #fca5a5; }
        }

        .empty-log {
          text-align: center;
          padding: 40px;
          color: #475569;
        }
      }
    }
  }
}
</style>
