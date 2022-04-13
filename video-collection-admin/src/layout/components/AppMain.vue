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
  flex: 1;
  overflow-y: auto;
  padding: 16px;
  background-color: var(--bg-color);
  position: relative;
}
</style>
