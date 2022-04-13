<template>
  <div class="layout-wrapper">
    <Sidebar />
    <div class="main-container">
      <Navbar />
      <TagsView />
      <AppMain />
    </div>
  </div>
</template>

<script setup lang="ts">
import Sidebar from './components/Sidebar.vue'
import Navbar from './components/Navbar.vue'
import TagsView from './components/TagsView.vue'
import AppMain from './components/AppMain.vue'
</script>

<style scoped lang="scss">
.layout-wrapper {
  display: flex;
  width: 100vw;
  height: 100vh;
  overflow: hidden;

  .main-container {
    flex: 1;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    background-color: var(--bg-color);
  }
}
</style>
