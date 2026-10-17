<template>
  <div class="app-main-container">
    <router-view v-slot="{ Component, route }">
      <transition name="fade-transform" mode="out-in">
        <component :is="Component" :key="route.path" />
      </transition>
    </router-view>
  </div>
</template>

<script setup lang="ts">
</script>

<style scoped lang="scss">
.app-main-container {
  position: relative;
  flex: 1 1 auto;
  min-height: 0;
  padding: 14px 16px 24px;
  overflow-x: hidden;
  overflow-y: auto;
  background-color: transparent;
  scrollbar-width: thin;
  scrollbar-color: rgba(113, 128, 155, 0.32) transparent;

  @media (max-width: 720px) {
    padding: 10px 10px 18px;
  }
}
</style>
