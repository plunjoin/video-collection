<template>
  <div class="scheduler-page">
    <el-row :gutter="16">
      <!-- 状态概览卡片 -->
      <el-col :xs="24" :md="10">
        <el-card shadow="never" class="status-card">
          <template #header>
            <div class="card-header">
              <span class="card-title">定时调度引擎状态</span>
              <el-tag :type="statusData.running ? 'danger' : 'success'">
                {{ statusData.running ? '正在采集运行中' : '空闲待命' }}
              </el-tag>
            </div>
          </template>

          <div class="status-content" v-loading="loading">
            <div class="status-item">
              <span class="label">自动采集服务：</span>
              <el-tag :type="statusData.enabled ? 'success' : 'info'">
                {{ statusData.enabled ? '已开启' : '已暂停' }}
              </el-tag>
            </div>
            <div class="status-item">
              <span class="label">执行周期频率：</span>
              <span class="val font-bold">每 {{ statusData.interval_hours || 2 }} 小时自动执行</span>
            </div>
            <div class="status-item">
              <span class="label">下次调度时间：</span>
              <span class="val">{{ formatDate(statusData.next_run_time) }}</span>
            </div>
            <div class="status-item">
              <span class="label">上次完成时间：</span>
              <span class="val">{{ formatDate(statusData.last_run_time) }}</span>
            </div>

            <el-divider />

            <div class="quick-manual">
              <span class="manual-title">即时手动触发：</span>
              <div class="btns">
                <el-button type="primary" :loading="triggering" @click="handleManualTrigger(24)">
                  即时增量采集 (24h)
                </el-button>
                <el-button type="warning" plain :loading="triggering" @click="handleManualTrigger(0)">
                  即时全量采集 (0h)
                </el-button>
              </div>
            </div>
          </div>
        </el-card>
      </el-col>

      <!-- 调度配置表单 -->
      <el-col :xs="24" :md="14">
        <el-card shadow="never" class="config-card">
          <template #header>
            <span class="card-title">自动采集计划参数配置</span>
          </template>

          <el-form :model="form" label-width="140px" class="config-form">
            <el-form-item label="开启自动定时采集">
              <el-switch
                v-model="form.enabled"
                active-text="启用后台定时巡检"
                inactive-text="关闭"
              />
            </el-form-item>

            <el-form-item label="巡检执行周期">
              <el-input-number
                v-model="form.interval_hours"
                :min="1"
                :max="72"
                :step="1"
              />
              <span class="unit-text">小时 / 次（推荐 2 小时）</span>
            </el-form-item>

            <el-form-item label="增量策略模式">
              <el-radio-group v-model="collectMode">
                <el-radio value="24">智能增量 (仅同步近24小时有更新的影视)</el-radio>
              </el-radio-group>
            </el-form-item>

            <el-form-item>
              <el-button type="primary" :loading="saving" @click="saveConfig">
                保存定时配置
              </el-button>
              <el-button @click="loadStatus">重置表单</el-button>
            </el-form-item>
          </el-form>

          <div class="cron-tips">
            <h4 class="tips-title">💡 调度运行机制说明：</h4>
            <ul>
              <li>系统在后台以轻量级 Goroutine 持续运行高精度定时轮询器。</li>
              <li>定时任务触发时，会自动遍历所有处于<strong>「启用」</strong>状态的采集源并发拉取最新增量数据。</li>
              <li>采集过程中会自动进行去重清洗、智能线路合并、剧集更新比对。</li>
            </ul>
          </div>
        </el-card>
      </el-col>
    </el-row>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { getAutoCollectStatus, saveAutoCollectConfig, triggerCollectAll } from '@/api/admin'
import type { AutoCollectStatus } from '@/types'
import { ElMessage } from 'element-plus'

const loading = ref(false)
const saving = ref(false)
const triggering = ref(false)
const collectMode = ref('24')

const statusData = ref<AutoCollectStatus>({
  enabled: false,
  interval_hours: 2,
  running: false
})

const form = reactive({
  enabled: false,
  interval_hours: 2
})

const formatDate = (val?: string) => {
  if (!val) return '尚未调度或计算中'
  return val.replace('T', ' ').substring(0, 19)
}

const loadStatus = async () => {
  loading.value = true
  try {
    const res = await getAutoCollectStatus()
    if (res.code === 1 && res.data) {
      statusData.value = res.data
      form.enabled = res.data.enabled
      form.interval_hours = res.data.interval_hours || 2
    }
  } finally {
    loading.value = false
  }
}

const saveConfig = async () => {
  saving.value = true
  try {
    const res = await saveAutoCollectConfig({
      enabled: form.enabled,
      interval_hours: form.interval_hours
    })
    if (res.code === 1) {
      ElMessage.success('定时自动采集配置已成功更新')
      loadStatus()
    }
  } finally {
    saving.value = false
  }
}

const handleManualTrigger = async (hours: number) => {
  triggering.value = true
  try {
    const res = await triggerCollectAll(hours)
    if (res.code === 1) {
      ElMessage.success(res.msg || '采集任务已在后台启动')
      loadStatus()
    }
  } finally {
    triggering.value = false
  }
}

onMounted(() => {
  loadStatus()
})
</script>

<style scoped lang="scss">
.scheduler-page {
  .status-card, .config-card {
    border-radius: 12px;
    border: 1px solid var(--border-color);

    .card-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
    }

    .card-title {
      font-size: 15px;
      font-weight: 700;
      color: var(--text-primary);
    }
  }

  .status-content {
    display: flex;
    flex-direction: column;
    gap: 14px;

    .status-item {
      display: flex;
      align-items: center;
      justify-content: space-between;
      font-size: 13px;

      .label {
        color: var(--text-secondary);
      }
      .val {
        color: var(--text-primary);
      }
    }

    .quick-manual {
      .manual-title {
        font-size: 13px;
        font-weight: 600;
        color: var(--text-regular);
        margin-bottom: 8px;
        display: block;
      }
      .btns {
        display: flex;
        gap: 10px;
        flex-wrap: wrap;
      }
    }
  }

  .config-form {
    .unit-text {
      margin-left: 12px;
      font-size: 12px;
      color: var(--text-secondary);
    }
  }

  .cron-tips {
    margin-top: 24px;
    padding: 14px;
    background: rgba(99, 102, 241, 0.05);
    border: 1px solid rgba(99, 102, 241, 0.15);
    border-radius: 8px;

    .tips-title {
      margin: 0 0 8px;
      font-size: 13px;
      color: #6366f1;
    }

    ul {
      margin: 0;
      padding-left: 18px;
      font-size: 12px;
      color: var(--text-regular);
      line-height: 1.8;
    }
  }
}
</style>
