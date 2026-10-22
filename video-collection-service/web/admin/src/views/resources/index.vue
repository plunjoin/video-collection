<template>
  <div class="resources-page">
    <header class="page-heading">
      <div>
        <h1>资源库</h1>
        <p>集中浏览视频、资讯、通用采集数据和自定义业务数据。</p>
      </div>
      <r-button @click="loadTypes" :loading="loading">刷新业务类型</r-button>
    </header>

    <r-tabs :model-value="activeTab" type="border-card" @tab-change="selectTab">
      <r-tab-pane v-for="tab in tabs" :key="tab.name" :name="tab.name" :label="tab.label" />
    </r-tabs>
    <div class="resource-content">
      <router-view />
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { listBusinessTypes } from '@/api/businessTypes'
import type { BusinessType } from '@/api/businessTypes'

const route = useRoute()
const router = useRouter()
const types = ref<BusinessType[]>([])
const loading = ref(false)

const tabs = computed(() => [
  { name: 'video', label: '视频库' },
  { name: 'news', label: '资讯' },
  { name: 'record', label: '通用数据' },
  ...types.value
    .filter((item) => !item.is_system && item.writer === 'table')
    .map((item) => ({ name: `biz:${item.slug}`, label: item.name || item.slug }))
])

const activeTab = computed(() => {
  if (route.name === 'ResourcesVideo') return 'video'
  if (route.name === 'ResourcesNews') return 'news'
  if (route.name === 'ResourcesRecord') return 'record'
  if (route.name === 'ResourcesBiz') return `biz:${String(route.params.slug || '')}`
  return 'video'
})

function selectTab(name: string | number) {
  const tab = String(name)
  if (tab === 'video') void router.push('/resources/video')
  else if (tab === 'news') void router.push('/resources/news')
  else if (tab === 'record') void router.push('/resources/record')
  else if (tab.startsWith('biz:')) void router.push(`/resources/biz/${encodeURIComponent(tab.slice(4))}`)
}

async function loadTypes() {
  loading.value = true
  try {
    types.value = (await listBusinessTypes()).data || []
  } finally {
    loading.value = false
  }
}

onMounted(loadTypes)
</script>

<style scoped>
.resources-page { padding: 24px; }
.page-heading { display: flex; align-items: center; justify-content: space-between; gap: 16px; margin-bottom: 20px; }
h1 { margin: 0; font-size: 24px; }
p { margin: 8px 0 0; color: var(--text-secondary); font-size: 13px; }
.resource-content { margin-top: 18px; }
@media (max-width: 720px) { .resources-page { padding: 12px; } .page-heading { align-items: flex-start; flex-wrap: wrap; } }
</style>
