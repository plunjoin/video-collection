<template>
  <div class="sidebar-container" :class="{ 'is-collapsed': appStore.sidebarCollapse }">
    <!-- Logo 区域 -->
    <div class="logo-box">
      <div class="logo-icon">
        <el-icon :size="22" color="#fff"><VideoCameraFilled /></el-icon>
      </div>
      <transition name="fade">
        <div v-show="!appStore.sidebarCollapse" class="logo-text">
          <span class="title">采集管理中心</span>
          <span class="badge">v1.0 Pro</span>
        </div>
      </transition>
    </div>

    <!-- 侧边导航菜单 -->
    <el-scrollbar class="menu-scrollbar">
      <el-menu
        :default-active="activeMenu"
        :collapse="appStore.sidebarCollapse"
        :collapse-transition="false"
        background-color="transparent"
        text-color="#94a3b8"
        active-text-color="#ffffff"
        router
      >
        <template v-for="item in menuList" :key="item.path">
          <el-menu-item :index="item.path">
            <el-icon><component :is="item.icon" /></el-icon>
            <template #title>{{ item.title }}</template>
          </el-menu-item>
        </template>
      </el-menu>
    </el-scrollbar>

    <!-- 底部快捷折叠开关 -->
    <div class="collapse-toggle" @click="appStore.toggleSidebar">
      <el-icon :size="18">
        <Fold v-if="!appStore.sidebarCollapse" />
        <Expand v-else />
      </el-icon>
      <span v-if="!appStore.sidebarCollapse" class="toggle-text">收起侧栏</span>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { useAppStore } from '@/store/app'
import { useUserStore } from '@/store/user'
import { canVisit } from '@/utils/permissions'
import {
  VideoCameraFilled,
  Odometer,
  Connection,
  SetUp,
  Film,
  Notification,
  ChatDotRound,
  Clock,
  ChatLineRound,
  User,
  Brush,
  VideoPlay,
  Setting,
  Coin,
  Document,
  Fold,
  Expand
} from '@element-plus/icons-vue'

const appStore = useAppStore()
const route = useRoute()

const activeMenu = computed(() => {
  return route.path
})

const allMenus = [
  { path: '/reviews', title: '内容审核中心', icon: Document },
  { path: '/growth', title: '日活 / 积分 / 装扮', icon: Coin },
  { path: '/notifications', title: '消息通知', icon: Notification },
  { path: '/dashboard', title: '系统仪表盘', icon: Odometer },
  { path: '/sources', title: '采集节点管理', icon: Connection },
  { path: '/collection-rules', title: '采集规则工作台', icon: SetUp },
  { path: '/videos', title: '视频仓库', icon: Film },
  { path: '/news', title: '资讯管理', icon: Notification },
  { path: '/community', title: '社区管理', icon: ChatDotRound },
  { path: '/scheduler', title: '定时采集调度', icon: Clock },
  { path: '/feedbacks', title: '求片与反馈', icon: ChatLineRound },
  { path: '/users', title: '用户账号管理', icon: User },
  { path: '/themes', title: '客户端主题', icon: Brush },
  { path: '/players', title: '播放器管理', icon: VideoPlay },
  { path: '/settings', title: '系统配置', icon: Setting },
  { path: '/database', title: '数据库管理', icon: Coin },
  { path: '/logs', title: '运行审计日志', icon: Document }
]
const userStore = useUserStore()
const menuList = computed(() => allMenus.filter(item => canVisit(userStore.userInfo?.role || '', item.path)))
</script>

<style scoped lang="scss">
.sidebar-container {
  width: 240px;
  height: 100%;
  background-color: var(--sidebar-bg);
  display: flex;
  flex-direction: column;
  border-right: 1px solid rgba(255, 255, 255, 0.05);
  transition: width 0.28s cubic-bezier(0.4, 0, 0.2, 1);
  user-select: none;
  overflow: hidden;

  &.is-collapsed {
    width: 64px;

    .logo-box {
      justify-content: center;
      padding: 0;
    }
  }

  .logo-box {
    height: 60px;
    display: flex;
    align-items: center;
    padding: 0 18px;
    gap: 12px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.08);

    .logo-icon {
      width: 36px;
      height: 36px;
      border-radius: 10px;
      background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%);
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 4px 12px rgba(99, 102, 241, 0.35);
      flex-shrink: 0;
    }

    .logo-text {
      display: flex;
      flex-direction: column;
      white-space: nowrap;

      .title {
        font-size: 15px;
        font-weight: 700;
        color: #f8fafc;
        letter-spacing: 0.3px;
      }
      .badge {
        font-size: 10px;
        color: #818cf8;
        font-weight: 600;
      }
    }
  }

  .menu-scrollbar {
    flex: 1;

    :deep(.el-menu) {
      border-right: none;

      .el-menu-item {
        height: 48px;
        line-height: 48px;
        margin: 4px 10px;
        border-radius: 8px;
        font-weight: 500;
        transition: all 0.2s;

        &:hover {
          background-color: rgba(255, 255, 255, 0.06);
          color: #f1f5f9;
        }

        &.is-active {
          background-color: var(--sidebar-active-bg);
          color: var(--sidebar-active-text);
          box-shadow: 0 4px 14px rgba(99, 102, 241, 0.35);
          font-weight: 600;
        }
      }
    }
  }

  .collapse-toggle {
    height: 48px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 20px;
    color: #64748b;
    border-top: 1px solid rgba(255, 255, 255, 0.06);
    cursor: pointer;
    transition: all 0.2s;

    &:hover {
      color: #cbd5e1;
      background: rgba(255, 255, 255, 0.04);
    }

    .toggle-text {
      font-size: 13px;
      white-space: nowrap;
    }
  }
}
</style>
