<template>
  <div class="navbar-container">
    <!-- 左侧面包屑与折叠开关 -->
    <div class="left-panel">
      <el-icon class="hamburger" :size="20" @click="appStore.toggleSidebar">
        <Fold v-if="!appStore.sidebarCollapse" />
        <Expand v-else />
      </el-icon>

      <el-breadcrumb separator="/" class="breadcrumb">
        <el-breadcrumb-item :to="{ path: '/' }">首页</el-breadcrumb-item>
        <el-breadcrumb-item v-if="currentTitle">{{ currentTitle }}</el-breadcrumb-item>
      </el-breadcrumb>
    </div>

    <!-- 右侧工具栏 -->
    <div class="right-panel">
      <!-- 前台门户链接 -->
      <el-tooltip content="在新窗口打开客户端影视门户" placement="bottom">
        <el-link :underline="false" href="http://localhost:80/" target="_blank" class="nav-tool-btn portal-btn">
          <el-icon :size="16"><Link /></el-icon>
          <span class="btn-text">客户端门户</span>
        </el-link>
      </el-tooltip>

      <!-- Swagger 文档 -->
      <el-tooltip content="查看 OpenAPI 3.0 交互式接口文档" placement="bottom">
        <el-link :underline="false" href="http://localhost:80/docs" target="_blank" class="nav-tool-btn">
          <el-icon :size="16"><Reading /></el-icon>
          <span class="btn-text">API文档</span>
        </el-link>
      </el-tooltip>

      <!-- 暗色/明亮切换 -->
      <el-tooltip :content="appStore.isDark ? '切换至明亮模式' : '切换至暗黑模式'" placement="bottom">
        <div class="icon-btn" @click="appStore.toggleDarkMode()">
          <el-icon :size="18">
            <Sunny v-if="appStore.isDark" />
            <Moon v-else />
          </el-icon>
        </div>
      </el-tooltip>

      <!-- 全屏切换 -->
      <el-tooltip content="全屏切换" placement="bottom">
        <div class="icon-btn" @click="toggleFullScreen">
          <el-icon :size="18"><FullScreen /></el-icon>
        </div>
      </el-tooltip>

      <!-- 用户下拉 -->
      <el-dropdown trigger="click" @command="handleCommand">
        <div class="user-profile">
          <el-avatar
            :size="32"
            class="user-avatar"
            src="https://cube.elemecdn.com/0/88/03b0d39583f48206768a7534e55bcpng.png"
          />
          <div class="user-meta">
            <span class="username">{{ userStore.userInfo?.nickname || userStore.userInfo?.username || '管理员' }}</span>
            <el-tag size="small" type="primary" effect="dark" class="role-tag">
              {{ userStore.userInfo?.role === 'admin' ? '超管' : '用户' }}
            </el-tag>
          </div>
          <el-icon class="arrow-icon"><CaretBottom /></el-icon>
        </div>
        <template #dropdown>
          <el-dropdown-menu>
            <el-dropdown-item command="profile">
              <el-icon><User /></el-icon>个人中心
            </el-dropdown-item>
            <el-dropdown-item command="docs" divided>
              <el-icon><Document /></el-icon>接口文档
            </el-dropdown-item>
            <el-dropdown-item command="logout" divided style="color: #f43f5e;">
              <el-icon><SwitchButton /></el-icon>退出登录
            </el-dropdown-item>
          </el-dropdown-menu>
        </template>
      </el-dropdown>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAppStore } from '@/store/app'
import { useUserStore } from '@/store/user'
import { ElMessageBox, ElMessage } from 'element-plus'
import {
  Fold,
  Expand,
  Link,
  Reading,
  Sunny,
  Moon,
  FullScreen,
  CaretBottom,
  User,
  Document,
  SwitchButton
} from '@element-plus/icons-vue'

const appStore = useAppStore()
const userStore = useUserStore()
const route = useRoute()
const router = useRouter()

const currentTitle = computed(() => {
  return (route.meta?.title as string) || ''
})

const toggleFullScreen = () => {
  if (!document.fullscreenElement) {
    document.documentElement.requestFullscreen()
  } else {
    if (document.exitFullscreen) {
      document.exitFullscreen()
    }
  }
}

const handleCommand = async (command: string) => {
  if (command === 'logout') {
    ElMessageBox.confirm('确定要退出当前管理员登录状态吗？', '安全退出提示', {
      confirmButtonText: '确定退出',
      cancelButtonText: '取消',
      type: 'warning'
    }).then(async () => {
      await userStore.logout()
      ElMessage.success('已安全退出')
      router.push('/login')
    }).catch(() => {})
  } else if (command === 'profile') {
    router.push('/users')
  } else if (command === 'docs') {
    window.open('http://localhost:80/docs', '_blank')
  }
}
</script>

<style scoped lang="scss">
.navbar-container {
  height: 56px;
  background-color: var(--navbar-bg);
  border-bottom: 1px solid var(--navbar-border);
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 20px;
  user-select: none;
  transition: all 0.25s;

  .left-panel {
    display: flex;
    align-items: center;
    gap: 16px;

    .hamburger {
      cursor: pointer;
      color: var(--text-regular);
      transition: color 0.2s;
      &:hover {
        color: var(--text-primary);
      }
    }
  }

  .right-panel {
    display: flex;
    align-items: center;
    gap: 12px;

    .nav-tool-btn {
      display: flex;
      align-items: center;
      gap: 6px;
      padding: 6px 12px;
      border-radius: 8px;
      font-size: 13px;
      color: var(--text-regular);
      transition: all 0.2s;
      background: rgba(148, 163, 184, 0.1);

      &:hover {
        color: var(--text-primary);
        background: rgba(148, 163, 184, 0.18);
      }

      &.portal-btn {
        background: rgba(99, 102, 241, 0.12);
        color: #6366f1;
        font-weight: 500;
        &:hover {
          background: rgba(99, 102, 241, 0.2);
        }
      }
    }

    .icon-btn {
      width: 34px;
      height: 34px;
      display: flex;
      align-items: center;
      justify-content: center;
      border-radius: 8px;
      cursor: pointer;
      color: var(--text-regular);
      transition: all 0.2s;
      &:hover {
        background: rgba(148, 163, 184, 0.15);
        color: var(--text-primary);
      }
    }

    .user-profile {
      display: flex;
      align-items: center;
      gap: 10px;
      cursor: pointer;
      padding: 4px 8px;
      border-radius: 8px;
      transition: background 0.2s;

      &:hover {
        background: rgba(148, 163, 184, 0.12);
      }

      .user-avatar {
        background-color: #6366f1;
      }

      .user-meta {
        display: flex;
        align-items: center;
        gap: 6px;

        .username {
          font-size: 14px;
          font-weight: 600;
          color: var(--text-primary);
        }

        .role-tag {
          font-size: 11px;
          padding: 0 6px;
          height: 20px;
          line-height: 20px;
          border-radius: 4px;
        }
      }

      .arrow-icon {
        font-size: 12px;
        color: var(--text-secondary);
      }
    }
  }
}
</style>
