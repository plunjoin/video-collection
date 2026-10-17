<template>
  <div class="themes-page">
    <r-card shadow="never" class="main-card">
      <div class="page-header">
        <div class="header-left">
          <span class="page-title">客户端主题引擎管理</span>
          <span class="sub-desc">支持多套前端主题无缝热切换，支持通过 ZIP 压缩包一键导入第三方主题包</span>
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
              <r-icon><Upload /></r-icon>上传导入主题包 (.zip)
            </r-button>
          </r-upload>
          <r-button @click="loadData" :loading="loading">
            <r-icon><RefreshRight /></r-icon>刷新
          </r-button>
        </div>
      </div>

      <!-- 主题卡片网格 -->
      <div v-loading="loading" class="theme-grid">
        <div v-if="themeList.length === 0" class="empty-tip">暂无已安装的主题包</div>
        <r-card
          v-for="item in themeList"
          :key="item.id"
          class="theme-card"
          :class="{ 'is-active': item.is_active }"
          shadow="hover"
        >
          <div class="card-cover-wrap">
            <r-image
              class="theme-preview"
              :src="item.preview || 'https://images.unsplash.com/photo-1579546929518-9e396f3cc809?w=600'"
              fit="cover"
            />
            <div v-if="item.is_active" class="active-badge">
              <r-icon><Check /></r-icon> 当前生效中
            </div>
          </div>
          <div class="theme-info">
            <div class="title-row">
              <span class="theme-name">{{ item.name }}</span>
              <r-tag size="small" type="info">v{{ item.version }}</r-tag>
            </div>
            <div class="author-row">作者：{{ item.author || '官方提供' }}</div>
            <div class="desc-row">{{ item.description || '精美自适应流媒体暗色视听主题' }}</div>
            <div class="action-row">
              <r-button
                v-if="!item.is_active"
                type="primary"
                size="small"
                :loading="switchingId === item.id"
                @click="handleSwitch(item)"
              >
                应用此主题
              </r-button>
              <r-button v-else type="success" size="small" disabled>
                已是当前主题
              </r-button>
            </div>
          </div>
        </r-card>
      </div>
    </r-card>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { getThemes, switchTheme, uploadTheme } from '@/api/admin'
import type { ThemeInfo } from '@/types'
import { notify } from '@/components/radix/feedback'
import type { UploadFile }  from '@/components/radix/types'
import { Upload, RefreshRight, Check } from '@/components/radix/icons'

const loading = ref(false)
const themeList = ref<ThemeInfo[]>([])
const switchingId = ref('')

const loadData = async () => {
  loading.value = true
  try {
    const res = await getThemes()
    if (res.code === 1 && res.data) {
      themeList.value = res.data
    }
  } finally {
    loading.value = false
  }
}

const handleSwitch = async (theme: ThemeInfo) => {
  switchingId.value = theme.id
  try {
    const res = await switchTheme(theme.id)
    if (res.code === 1) {
      notify(`已成功切换至主题 [${theme.name}]`, 'success')
      loadData()
    }
  } finally {
    switchingId.value = ''
  }
}

const handleUploadFile = async (file: UploadFile) => {
  if (!file.raw) return
  if (!file.name.toLowerCase().endsWith('.zip')) {
    notify('仅支持上传 .zip 格式的主题扩展包', 'error')
    return
  }
  const formData = new FormData()
  formData.append('file', file.raw)

  loading.value = true
  try {
    const res = await uploadTheme(formData)
    if (res.code === 1) {
      notify('主题扩展包导入成功！', 'success')
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
.themes-page {
  .main-card {
    .page-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 12px;
      flex-wrap: wrap;
      gap: 8px;

      .header-left {
        display: flex;
        flex-direction: column;
        gap: 2px;

        .page-title {
          font-size: 13px;
          font-weight: 700;
          letter-spacing: -0.02em;
          color: var(--text-primary);
        }
        .sub-desc {
          font-size: 10px;
          color: var(--text-secondary);
        }
      }

      .header-right {
        display: flex;
        gap: 6px;
      }
    }

    .theme-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
      gap: 12px;

      .theme-card {
        border-radius: var(--radius-md);
        border: 1px solid var(--border-color);
        transition: all 0.2s ease;
        overflow: hidden;

        &.is-active {
          border-color: var(--brand);
          box-shadow: 0 0 0 1px var(--brand);
        }

        :deep(.r-card__body) {
          padding: 0;
        }

        .card-cover-wrap {
          height: 140px;
          position: relative;
          background: #1e293b;

          .theme-preview {
            width: 100%;
            height: 100%;
          }

          .active-badge {
            position: absolute;
            top: 8px;
            right: 8px;
            background: rgba(47, 158, 110, 0.9);
            color: #fff;
            font-size: 9px;
            font-weight: 650;
            padding: 2px 6px;
            border-radius: var(--radius-xs);
            display: flex;
            align-items: center;
            gap: 3px;
            backdrop-filter: blur(4px);
          }
        }

        .theme-info {
          padding: 12px;
          display: flex;
          flex-direction: column;
          gap: 4px;

          .title-row {
            display: flex;
            align-items: center;
            justify-content: space-between;

            .theme-name {
              font-size: 12px;
              font-weight: 650;
              color: var(--text-primary);
            }
          }

          .author-row {
            font-size: 10px;
            color: var(--text-secondary);
          }

          .desc-row {
            font-size: 11px;
            color: var(--text-regular);
            margin: 2px 0 8px;
            height: 32px;
            overflow: hidden;
            text-overflow: ellipsis;
            display: -webkit-box;
            -webkit-line-clamp: 2;
            -webkit-box-orient: vertical;
          }

          .action-row {
            display: flex;
            justify-content: flex-end;
          }
        }
      }

      .empty-tip {
        grid-column: 1 / -1;
        text-align: center;
        padding: 30px;
        color: var(--text-secondary);
        font-size: 11px;
      }
    }
  }
}
</style>
