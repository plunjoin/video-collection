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
  display: flex;
  flex-shrink: 0;
  height: 56px;
  align-items: center;
  justify-content: space-between;
  padding: 0 14px 0 10px;
  background: transparent;
  border-bottom: 1px solid var(--nav-border-light, rgba(20, 32, 57, 0.05));
  border-radius: var(--radius-lg) var(--radius-lg) 0 0;
  user-select: none;

  .left-panel {
    display: flex;
    min-width: 0;
    align-items: center;
    gap: 8px;

    .rail-toggle {
      display: inline-flex;
      width: 34px;
      height: 34px;
      flex: 0 0 34px;
      align-items: center;
      justify-content: center;
      padding: 0;
      color: var(--text-secondary);
      background: transparent;
      border: 0;
      border-radius: var(--radius-sm);
      cursor: pointer;
      outline: none;
      transition: background 180ms ease, color 180ms ease;

      &:hover {
        color: var(--text-primary);
        background: var(--nav-bg-subtle, rgba(255, 255, 255, 0.55));
      }

      &:focus-visible {
        box-shadow: 0 0 0 2px rgba(79, 110, 242, 0.45);
      }
    }

    .page-heading {
      display: flex;
      min-width: 0;
      align-items: center;
      gap: 8px;

      .page-title {
        overflow: hidden;
        margin: 0;
        color: var(--text-primary);
        font-size: 13px;
        font-weight: 700;
        letter-spacing: -0.02em;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .page-env {
        padding: 1px 6px;
        color: var(--text-secondary);
        background: rgba(20, 32, 57, 0.04);
        border: 1px solid var(--nav-border-light, rgba(20, 32, 57, 0.05));
        border-radius: var(--radius-pill);
        font-size: 9px;
        font-weight: 700;
        line-height: 1.3;
        text-transform: uppercase;
      }
    }
  }

  .right-panel {
    display: flex;
    align-items: center;
    gap: 4px;

    .tool-btn {
      display: inline-flex;
      width: 32px;
      height: 32px;
      align-items: center;
      justify-content: center;
      color: var(--text-secondary);
      background: transparent;
      border: 0;
      border-radius: var(--radius-sm);
      cursor: pointer;
      outline: none;
      transition: background 160ms ease, color 160ms ease;

      &:hover {
        color: var(--text-primary);
        background: var(--nav-bg-subtle, rgba(255, 255, 255, 0.55));
      }

      &:focus-visible {
        box-shadow: 0 0 0 2px rgba(79, 110, 242, 0.45);
      }
    }
  }
}

html.dark .topbar {
  border-bottom-color: var(--nav-border-light, rgba(255, 255, 255, 0.06));

  .page-env {
    background: rgba(255, 255, 255, 0.06);
    border-color: rgba(255, 255, 255, 0.08);
  }

  .left-panel .rail-toggle:hover,
  .right-panel .tool-btn:hover {
    background: rgba(255, 255, 255, 0.06);
  }
}
</style>
