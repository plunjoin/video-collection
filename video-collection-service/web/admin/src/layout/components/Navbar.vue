<template>
  <header class="topbar">
    <!-- 左侧：折叠开关 + 当前页标题 -->
    <div class="left-panel">
      <button class="rail-toggle" type="button" :aria-label="appStore.sidebarCollapse ? '打开边栏' : '收起边栏'" :aria-expanded="!appStore.sidebarCollapse" @click="appStore.toggleSidebar">
        <PanelLeftOpen v-if="appStore.sidebarCollapse" :size="19" />
        <PanelLeft v-else :size="19" />
      </button>
      <div class="page-heading">
        <h1 class="page-title">{{ currentTitle }}</h1>
        <span class="page-env">{{ envLabel }}</span>
      </div>
    </div>

    <!-- 右侧工具栏 -->
    <div class="right-panel">
      <r-tooltip content="客户端影视门户" placement="bottom">
        <r-link underline="never" :href="portalUrl" target="_blank" class="tool-btn">
          <r-icon :size="16"><Monitor /></r-icon>
        </r-link>
      </r-tooltip>

      <r-tooltip content="OpenAPI 接口文档" placement="bottom">
        <r-link underline="never" href="/docs" target="_blank" class="tool-btn">
          <r-icon :size="16"><Reading /></r-icon>
        </r-link>
      </r-tooltip>

      <r-tooltip :content="appStore.isDark ? '切换至明亮模式' : '切换至暗黑模式'" placement="bottom">
        <div class="tool-btn" @click="appStore.toggleDarkMode()">
          <r-icon :size="17">
            <Sunny v-if="appStore.isDark" />
            <Moon v-else />
          </r-icon>
        </div>
      </r-tooltip>

      <r-tooltip content="全屏切换" placement="bottom">
        <div class="tool-btn" @click="toggleFullScreen">
          <r-icon :size="17"><FullScreen /></r-icon>
        </div>
      </r-tooltip>

      <r-tooltip content="消息通知" placement="bottom">
        <r-badge :value="unread" :hidden="!unread" :max="99">
          <div class="tool-btn" @click="router.push('/notifications')">
            <r-icon :size="17"><Bell /></r-icon>
          </div>
        </r-badge>
      </r-tooltip>
    </div>
  </header>
</template>

<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import request from '@/utils/request'
import { useAppStore } from '@/store/app'
import {
  PanelLeft,
  PanelLeftOpen,
  Monitor,
  Reading,
  Sunny,
  Moon,
  FullScreen,
  Bell
} from '@/components/radix/icons'

const appStore = useAppStore()
const route = useRoute()
const router = useRouter()
const portalUrl = import.meta.env.VITE_PORTAL_URL || '/'
const envLabel = import.meta.env.DEV ? 'dev' : 'prod'

const unread = ref(0)
let inboxTimer: ReturnType<typeof setInterval>
async function refreshInbox() {
  try {
    const r: any = await request.get('/api/user/notifications/unread-count')
    unread.value = r.data?.unread_count || 0
  } catch {}
}
onMounted(() => {
  refreshInbox()
  inboxTimer = setInterval(refreshInbox, 30000)
  window.addEventListener('inbox-updated', refreshInbox)
})
onUnmounted(() => {
  clearInterval(inboxTimer)
  window.removeEventListener('inbox-updated', refreshInbox)
})

const currentTitle = computed(() => (route.meta?.title as string) || '视频采集管理')

const toggleFullScreen = () => {
  if (!document.fullscreenElement) {
    document.documentElement.requestFullscreen()
  } else {
    document.exitFullscreen()
  }
}
</script>

<style scoped lang="scss">
.topbar {
  height: 60px;
  flex-shrink: 0;
  background: var(--surface);
  border-bottom: 1px solid var(--border-color);
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 20px 0 12px;
  user-select: none;

  .left-panel {
    display: flex;
    align-items: center;
    gap: 14px;
    min-width: 0;

    .rail-toggle {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      cursor: pointer;
      color: var(--text-regular);
      padding: 6px;
      border: 0;
      background: transparent;
      border-radius: var(--radius-sm);
      transition: all 0.2s;
      &:hover {
        color: var(--text-primary);
        background: var(--surface-hover);
      }
    }

    .page-heading {
      display: flex;
      align-items: baseline;
      gap: 10px;
      min-width: 0;

      .page-title {
        font-size: 17px;
        font-weight: 500;
        color: var(--text-primary);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .page-env {
        font-size: 11px;
        color: var(--text-secondary);
        border: 1px solid var(--border-color);
        border-radius: 999px;
        padding: 1px 8px;
      }
    }
  }

  .right-panel {
    display: flex;
    align-items: center;
    gap: 6px;

    .tool-btn {
      width: 36px;
      height: 36px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      border-radius: 999px;
      cursor: pointer;
      color: var(--text-regular);
      transition: all 0.16s ease;

      &:hover {
        background: var(--surface-hover);
        color: var(--text-primary);
      }
    }
  }
}
</style>
