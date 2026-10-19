<template>
  <div class="logs-page">
    <r-card shadow="never" class="table-card">
      <div class="table-header">
        <div class="header-left">
          <span class="page-title">运行日志</span>
          <span class="sub-desc">后台操作与服务运行记录</span>
        </div>
        <div class="header-right">
          <r-button @click="loadData" :loading="loading">刷新</r-button>
        </div>
      </div>
      <r-table :data="tableData" v-loading="loading" border stripe style="width: 100%">
        <r-table-column prop="level" label="级别" width="100" />
        <r-table-column prop="message" label="内容" min-width="280" show-overflow-tooltip />
        <r-table-column prop="created_at" label="时间" width="180" />
      </r-table>
    </r-card>
  </div>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { getLogs } from '@/api/admin'

const loading = ref(false)
const tableData = ref<any[]>([])

async function loadData() {
  loading.value = true
  try {
    const res = await getLogs(100)
    tableData.value = (res as any)?.data || (res as any) || []
  } catch {
    tableData.value = []
  } finally {
    loading.value = false
  }
}

onMounted(loadData)
</script>

<style scoped>
.logs-page { padding: 0; }
.table-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px; }
.page-title { font-size: 18px; font-weight: 600; margin-right: 12px; }
.sub-desc { color: #94a3b8; font-size: 13px; }
</style>
