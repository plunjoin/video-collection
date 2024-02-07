<template>
  <div class="layout-wrapper">
    <Sidebar />
    <div class="main-container">
      <Navbar />
      <TagsView />
      <el-alert v-if="userStore.userInfo?.role === 'observer'" title="观察员模式：可查看全部后台信息，业务操作需要管理员权限。" type="info" :closable="false" />
      <el-alert v-if="userStore.userInfo?.role === 'operator'" title="运营工作台：视频、资讯、社区及评论提交后均需管理员审核。审核期间已公开的版本保持展示。" type="warning" :closable="false" />
      <AppMain />
    </div>
  </div>
</template>

<script setup lang="ts">
import Sidebar from './components/Sidebar.vue'
import Navbar from './components/Navbar.vue'
import TagsView from './components/TagsView.vue'
import AppMain from './components/AppMain.vue'
import { useUserStore } from '@/store/user'
const userStore = useUserStore()
</script>

<style scoped lang="scss">
.layout-wrapper {
  display: flex;
  width: 100vw;
  height: 100vh;
  overflow: hidden;

  .main-container {
	min-width: 0;
    flex: 1;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    background-color: var(--bg-color);
  }
}
</style>
