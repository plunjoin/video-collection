<template>
  <router-view />
  <FeedbackHost />
</template>

<script setup lang="ts">
import FeedbackHost from './components/radix/FeedbackHost.vue'
</script>

<style>
#app {
  width: 100%;
  height: 100%;
}
</style>
