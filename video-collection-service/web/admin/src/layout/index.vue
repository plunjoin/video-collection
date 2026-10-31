<template>
  <div class="layout-wrapper">
    <Sidebar />
    <div class="main-container">
      <Navbar />
      <r-alert
        v-if="userStore.userInfo?.role === 'observer'"
        title="观察员模式：可查看全部后台信息，业务操作需要管理员权限。"
        type="info"
        :closable="false"
        class="role-alert"
      />
      <r-alert
        v-if="userStore.userInfo?.role === 'operator'"
        title="运营工作台：视频、资讯、社区及评论提交后均需管理员审核。审核期间已公开的版本保持展示。"
        type="warning"
        :closable="false"
        class="role-alert"
      />
      <AppMain />
    </div>
  </div>
</template>

<script setup lang="ts">
import Sidebar from './components/Sidebar.vue'
import Navbar from './components/Navbar.vue'
import AppMain from './components/AppMain.vue'
import { useUserStore } from '@/store/user'
const userStore = useUserStore()
</script>

<style scoped>
.layout-wrapper {
  display: flex;
  gap: 14px;
  width: 100vw;
  height: 100vh;
  overflow: hidden;
  /* 背景系统由 body 提供（基础色 + 环境光 + 局部空间光），外壳保持透明 */
  background-color: transparent;

  .main-container {
    min-width: 0;
    flex: 1;
    height: 100%;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    position: relative;
    color: var(--text-primary);
    background: var(--glass-panel);
    border: 1px solid var(--border-color);
    border-radius: var(--radius-lg);
    box-shadow: 0 1px 2px rgba(22, 33, 58, 0.04), 0 8px 24px rgba(22, 33, 58, 0.05), var(--glass-highlight);
    backdrop-filter: var(--glass-blur);
    -webkit-backdrop-filter: var(--glass-blur);
  }

  .role-alert {
    margin: 10px 14px 0;
    padding: 7px 12px;
    font-size: 11px;
    border-radius: var(--radius-sm);
    border: 1px solid var(--glass-border);
    backdrop-filter: var(--glass-blur);
    -webkit-backdrop-filter: var(--glass-blur);
  }
}
</style>
