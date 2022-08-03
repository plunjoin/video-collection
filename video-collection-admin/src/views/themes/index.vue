<template>
  <div class="themes-page">
    <el-card shadow="never" class="main-card">
      <div class="page-header">
        <div class="header-left">
          <span class="page-title">客户端主题引擎管理</span>
          <span class="sub-desc">支持多套前端主题无缝热切换，支持通过 ZIP 压缩包一键导入第三方主题包</span>
        </div>
        <div class="header-right">
          <el-upload
            action="#"
            :auto-upload="false"
            :show-file-list="false"
            :on-change="handleUploadFile"
            accept=".zip"
          >
            <el-button type="primary">
              <el-icon><Upload /></el-icon>上传导入主题包 (.zip)
            </el-button>
          </el-upload>
          <el-button @click="loadData" :loading="loading">
            <el-icon><RefreshRight /></el-icon>刷新
          </el-button>
        </div>
      </div>

      <!-- 主题卡片网格 -->
      <div v-loading="loading" class="theme-grid">
        <div v-if="themeList.length === 0" class="empty-tip">暂无已安装的主题包</div>
        <el-card
          v-for="item in themeList"
          :key="item.id"
          class="theme-card"
          :class="{ 'is-active': item.is_active }"
          shadow="hover"
        >
          <div class="card-cover-wrap">
            <el-image
              class="theme-preview"
              :src="item.preview || 'https://images.unsplash.com/photo-1579546929518-9e396f3cc809?w=600'"
              fit="cover"
            />
            <div v-if="item.is_active" class="active-badge">
              <el-icon><Check /></el-icon> 当前生效中
            </div>
          </div>
          <div class="theme-info">
            <div class="title-row">
              <span class="theme-name">{{ item.name }}</span>
              <el-tag size="small" type="info">v{{ item.version }}</el-tag>
            </div>
            <div class="author-row">作者：{{ item.author || '官方提供' }}</div>
            <div class="desc-row">{{ item.description || '精美自适应流媒体暗色视听主题' }}</div>
            <div class="action-row">
              <el-button
                v-if="!item.is_active"
                type="primary"
                size="small"
                :loading="switchingId === item.id"
                @click="handleSwitch(item)"
              >
                应用此主题
              </el-button>
              <el-button v-else type="success" size="small" disabled>
                已是当前主题
              </el-button>
            </div>
          </div>
        </el-card>
      </div>
    </el-card>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { getThemes, switchTheme, uploadTheme } from '@/api/admin'
import type { ThemeInfo } from '@/types'
import { ElMessage, type UploadFile } from 'element-plus'
import { Upload, RefreshRight, Check } from '@element-plus/icons-vue'

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
      ElMessage.success(`已成功切换至主题 [${theme.name}]`)
      loadData()
    }
  } finally {
    switchingId.value = ''
  }
}

const handleUploadFile = async (file: UploadFile) => {
  if (!file.raw) return
  if (!file.name.toLowerCase().endsWith('.zip')) {
    ElMessage.error('仅支持上传 .zip 格式的主题扩展包')
    return
  }
  const formData = new FormData()
  formData.append('file', file.raw)

  loading.value = true
  try {
    const res = await uploadTheme(formData)
    if (res.code === 1) {
      ElMessage.success('主题扩展包导入成功！')
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

    .theme-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
      gap: 20px;

      .theme-card {
        border-radius: 12px;
        border: 1px solid var(--border-color);
        transition: all 0.25s;
        overflow: hidden;

        &.is-active {
          border-color: #6366f1;
          box-shadow: 0 0 0 1px #6366f1;
        }

        :deep(.el-card__body) {
          padding: 0;
        }

        .card-cover-wrap {
          height: 160px;
          position: relative;
          background: #1e293b;

          .theme-preview {
            width: 100%;
            height: 100%;
          }

          .active-badge {
            position: absolute;
            top: 10px;
            right: 10px;
            background: rgba(16, 185, 129, 0.9);
            color: #fff;
            font-size: 11px;
            font-weight: 600;
            padding: 3px 8px;
            border-radius: 6px;
            display: flex;
            align-items: center;
            gap: 4px;
            backdrop-filter: blur(4px);
          }
        }

        .theme-info {
          padding: 16px;
          display: flex;
          flex-direction: column;
          gap: 6px;

          .title-row {
            display: flex;
            align-items: center;
            justify-content: space-between;

            .theme-name {
              font-size: 15px;
              font-weight: 700;
              color: var(--text-primary);
            }
          }

          .author-row {
            font-size: 12px;
            color: var(--text-secondary);
          }

          .desc-row {
            font-size: 12px;
            color: var(--text-regular);
            margin: 4px 0 10px;
            height: 36px;
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
        padding: 40px;
        color: var(--text-secondary);
      }
    }
  }
}
</style>
