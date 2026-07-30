<template>
  <div class="players-page">
    <r-card shadow="never" class="main-card">
      <div class="page-header">
        <div class="header-left">
          <span class="page-title">播放器引擎与解析插件管理</span>
          <span class="sub-desc">支持多款 H5 原生播放器及第三方云解析接口热切换与自定义配置</span>
        </div>
        <div class="header-right">
          <r-upload
            action="#"
            :auto-upload="false"
            :show-file-list="false"
            :on-change="handleUploadFile"
            accept=".zip"
          >
            <r-button type="primary">
              <r-icon><Upload /></r-icon>上传播放器插件 (.zip)
            </r-button>
          </r-upload>
          <r-button @click="loadData" :loading="loading">
            <r-icon><RefreshRight /></r-icon>刷新
          </r-button>
        </div>
      </div>

      <div v-loading="loading" class="player-grid">
        <div v-if="playerList.length === 0" class="empty-tip">暂无可用播放器</div>
        <r-card
          v-for="item in playerList"
          :key="item.id"
          class="player-card"
          :class="{ 'is-active': item.is_active }"
          shadow="hover"
        >
          <div class="card-header">
            <div class="icon-wrap">
              <r-icon :size="24" color="#6366f1"><VideoPlay /></r-icon>
            </div>
            <div class="name-meta">
              <span class="name">{{ item.name }}</span>
              <span class="version">v{{ item.version || '1.0' }}</span>
            </div>
            <r-tag v-if="item.is_active" type="success" size="small" effect="dark">当前激活</r-tag>
          </div>

          <div class="card-body">
            <div class="info-row">
              <span class="label">插件作者：</span>
              <span class="val">{{ item.author || '系统内置' }}</span>
            </div>
            <div class="info-row">
              <span class="label">插件标识：</span>
              <code class="val-code">{{ item.id }}</code>
            </div>
          </div>

          <div class="card-footer">
            <r-button size="small" @click="openConfig(item)">配置参数</r-button>
            <r-button
              v-if="!item.is_active"
              size="small"
              type="primary"
              :loading="switchingId === item.id"
              @click="handleSwitch(item)"
            >
              设为默认
            </r-button>
            <r-button v-else size="small" type="success" disabled>默认播放器</r-button>
          </div>
        </r-card>
      </div>
    </r-card>

    <!-- 配置模态框 -->
    <r-dialog v-model="configDialogVisible" title="播放器扩展参数配置" width="550px">
      <r-form label-position="top">
        <r-form-item label="配置 JSON 参数">
          <r-input
            v-model="configJsonStr"
            type="textarea"
            :rows="8"
            placeholder="{ ... }"
          />
        </r-form-item>
      </r-form>
      <template #footer>
        <r-button @click="configDialogVisible = false">取消</r-button>
        <r-button type="primary" :loading="savingConfig" @click="savePlayerConfig">保存配置</r-button>
      </template>
    </r-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import {
  getPlayers,
  switchPlayer,
  updatePlayerConfig,
  uploadPlayer
} from '@/api/admin'
import type { PlayerInfo } from '@/types'
import { notify } from '@/components/radix/feedback'
import type { UploadFile }  from '@/components/radix/types'
import { Upload, RefreshRight, VideoPlay } from '@/components/radix/icons'

const loading = ref(false)
const playerList = ref<PlayerInfo[]>([])
const switchingId = ref('')
const configDialogVisible = ref(false)
const savingConfig = ref(false)
const currentItem = ref<PlayerInfo | null>(null)
const configJsonStr = ref('')

const loadData = async () => {
  loading.value = true
  try {
    const res = await getPlayers()
    if (res.code === 1 && res.data) {
      playerList.value = res.data
    }
  } finally {
    loading.value = false
  }
}

const handleSwitch = async (item: PlayerInfo) => {
  switchingId.value = item.id
  try {
    const res = await switchPlayer(item.id)
    if (res.code === 1) {
      notify(`已设置 [${item.name}] 为默认播放器`, 'success')
      loadData()
    }
  } finally {
    switchingId.value = ''
  }
}

const openConfig = (item: PlayerInfo) => {
  currentItem.value = item
  configJsonStr.value = JSON.stringify(item.config || {}, null, 2)
  configDialogVisible.value = true
}

const savePlayerConfig = async () => {
  if (!currentItem.value) return
  let parsed: any = {}
  try {
    parsed = JSON.parse(configJsonStr.value || '{}')
  } catch (e) {
    notify('JSON 格式不合法，请检查', 'error')
    return
  }
  savingConfig.value = true
  try {
    const res = await updatePlayerConfig(currentItem.value.id, parsed)
    if (res.code === 1) {
      notify('播放器配置已更新', 'success')
      configDialogVisible.value = false
      loadData()
    }
  } finally {
    savingConfig.value = false
  }
}

const handleUploadFile = async (file: UploadFile) => {
  if (!file.raw) return
  if (!file.name.toLowerCase().endsWith('.zip')) {
    notify('仅支持上传 .zip 格式的播放器扩展包', 'error')
    return
  }
  const formData = new FormData()
  formData.append('file', file.raw)

  loading.value = true
  try {
    const res = await uploadPlayer(formData)
    if (res.code === 1) {
      notify('播放器扩展包导入成功！', 'success')
      loadData()
    }
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  loadData()
})
</script>

<style scoped lang="scss">
.players-page {
  .main-card {
    border-radius: 12px;
    border: 1px solid var(--border-color);

    .page-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 24px;
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

    .player-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
      gap: 20px;

      .player-card {
        border-radius: 12px;
        border: 1px solid var(--border-color);
        transition: all 0.25s;

        &.is-active {
          border-color: #6366f1;
          box-shadow: 0 0 0 1px #6366f1;
        }

        .card-header {
          display: flex;
          align-items: center;
          gap: 12px;
          margin-bottom: 14px;

          .icon-wrap {
            width: 42px;
            height: 42px;
            background: rgba(99, 102, 241, 0.12);
            border-radius: 10px;
            display: flex;
            align-items: center;
            justify-content: center;
          }

          .name-meta {
            flex: 1;
            display: flex;
            flex-direction: column;

            .name {
              font-size: 15px;
              font-weight: 700;
              color: var(--text-primary);
            }
            .version {
              font-size: 11px;
              color: var(--text-secondary);
            }
          }
        }

        .card-body {
          display: flex;
          flex-direction: column;
          gap: 8px;
          margin-bottom: 16px;
          font-size: 12px;

          .info-row {
            display: flex;
            align-items: center;
            justify-content: space-between;

            .label {
              color: var(--text-secondary);
            }
            .val {
              color: var(--text-regular);
            }
            .val-code {
              background: rgba(148, 163, 184, 0.15);
              padding: 2px 6px;
              border-radius: 4px;
              color: #6366f1;
            }
          }
        }

        .card-footer {
          display: flex;
          justify-content: flex-end;
          gap: 8px;
          border-top: 1px solid var(--border-color);
          padding-top: 12px;
        }
      }

      .empty-tip {
        grid-column: 1 / -1;
        text-align: center;
        padding: 40px;
        color: var(--text-secondary);
      }
    }
  }
}
</style>
