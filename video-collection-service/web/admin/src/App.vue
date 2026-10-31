<template>
  <router-view />
  <FeedbackHost />
</template>

<script setup lang="ts">
import FeedbackHost from './components/radix/FeedbackHost.vue'
</script>

<style>
#root {
  width: 100%;
  height: 100%;
}
</style>
