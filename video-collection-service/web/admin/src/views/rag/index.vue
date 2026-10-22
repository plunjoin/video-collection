<template>
  <div class="rag-page">
    <r-card shadow="never">
      <div class="toolbar">
        <div>
          <h2>RAG 知识库</h2>
          <p class="muted">检索 Wiki、资讯与社区内容，依据资料生成带引用的回答。内容变更后自动增量索引。</p>
        </div>
        <r-button type="primary" :loading="rebuilding" :disabled="readOnly || searching || asking" @click="rebuild">
          重建全部索引
        </r-button>
      </div>
      <p class="muted" role="status">{{ rebuildNote || '索引随内容自动更新。本页暂无重建记录，可先搜索或提问。' }}</p>
      <div class="filters">
        <label for="rag-top-k">检索数量</label>
        <r-input-number id="rag-top-k" v-model="topK" :min="1" :max="50" />
        <label for="rag-source">资料来源</label>
        <r-select id="rag-source" v-model="sourceType" style="width: 180px">
          <r-option label="全部来源" value="" />
          <r-option label="Wiki 词条" value="wiki_subject" />
          <r-option label="Wiki 关系" value="wiki_relation" />
          <r-option label="资讯" value="news" />
          <r-option label="社区帖子" value="post" />
        </r-select>
      </div>
    </r-card>

    <r-card shadow="never">
      <h3>语义检索</h3>
      <div class="search-row">
        <r-input v-model="searchQuery" aria-label="检索内容" placeholder="输入关键词或问题" clearable @keyup.enter="search" />
        <r-button type="primary" :loading="searching" :disabled="!searchQuery.trim() || rebuilding" @click="search">搜索</r-button>
      </div>
      <div class="examples">
        <span class="muted">试试关键词：</span>
        <r-button v-for="example in examples" :key="example" size="small" plain :disabled="searching || rebuilding" @click="searchQuery = example">{{ example }}</r-button>
      </div>
      <r-table :data="hits" v-loading="searching" border stripe style="width: 100%" :empty-text="searching ? '正在检索资料…' : searched ? '没有匹配资料，可以调整关键词、来源或重建索引后重试。' : '输入关键词后点搜索才会出结果，不是坏了。也可以点击上方示例填入关键词。'">
        <r-table-column label="文本片段" min-width="300">
          <template #default="{ row }">
            <details><summary class="snippet">{{ row.text.slice(0, 160) }}</summary><p class="chunk-text">{{ row.text }}</p></details>
          </template>
        </r-table-column>
        <r-table-column label="相似度" width="100">
          <template #default="{ row }">{{ row.similarity.toFixed(4) }}</template>
        </r-table-column>
        <r-table-column prop="source_type" label="来源类型" width="150" />
        <r-table-column prop="source_id" label="来源 ID" width="100" />
      </r-table>
    </r-card>

    <r-card shadow="never">
      <h3>知识问答</h3>
      <div class="examples">
        <span class="muted">试试问题：</span>
        <r-button v-for="example in examples" :key="example" size="small" plain :disabled="readOnly || asking || rebuilding" @click="question = `介绍一下${example}`">介绍一下{{ example }}</r-button>
      </div>
      <r-input v-model="question" type="textarea" :rows="4" aria-label="知识库问题" placeholder="输入问题，回答将附上检索资料引用" />
      <div class="ask-actions">
        <r-button type="primary" :loading="asking" :disabled="readOnly || !question.trim() || rebuilding" @click="ask">提问</r-button>
        <span v-if="asking" class="muted" role="status">正在检索资料并生成回答…</span>
      </div>
      <div v-if="answer" aria-live="polite">
        <p class="muted">问题：{{ answer.query }}</p>
        <div class="answer-text">{{ answer.answer }}</div>
        <p class="muted">模型：{{ answer.model }} · 嵌入：{{ answer.embedder }} · Top K：{{ answer.top_k }}</p>
        <p v-if="answer.graph_note" class="muted">{{ answer.graph_note }}</p>
        <h4>引用资料</h4>
        <p v-if="!answer.citations.length" class="muted">未检索到可引用资料。</p>
        <ol class="citations">
          <li v-for="(citation, index) in answer.citations" :key="`${citation.id}-${index}`">
            <details>
              <summary>[{{ index + 1 }}] {{ citation.source_type }} #{{ citation.source_id }} · 相似度 {{ citation.similarity.toFixed(4) }}</summary>
              <p class="chunk-text">{{ citation.text }}</p>
            </details>
          </li>
        </ol>
      </div>
    </r-card>
  </div>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue'
import { ragAsk, ragRebuild, ragSearch } from '@/api/admin'
import type { RAGAskResponse, RAGChunk } from '@/api/admin'
import { notify } from '@/components/radix/feedback'
import { useUserStore } from '@/store/user'

const userStore = useUserStore()
const examples = ['流浪地球', '英伟达', 'OpenAI']
const readOnly = computed(() => userStore.userInfo?.role === 'observer')
const topK = ref(5)
const sourceType = ref('')
const searchQuery = ref('')
const question = ref('')
const rebuilding = ref(false)
const searching = ref(false)
const asking = ref(false)
const searched = ref(false)
const rebuildNote = ref('')
const hits = ref<RAGChunk[]>([])
const answer = ref<RAGAskResponse>()

async function rebuild() {
  if (rebuilding.value || readOnly.value) return
  rebuilding.value = true
  try {
    const result = await ragRebuild()
    rebuildNote.value = `本页上次重建：${new Date().toLocaleString('zh-CN')} · ${result.chunks_indexed} 个文本块 · 嵌入模型：${result.embedder}`
    hits.value = []
    searched.value = false
    notify(rebuildNote.value, 'success')
  } catch { /* Request interceptor displays the error. */ }
  finally { rebuilding.value = false }
}

async function search() {
  if (!searchQuery.value.trim() || searching.value || rebuilding.value) return
  searching.value = true
  searched.value = false
  hits.value = []
  try {
    const result = await ragSearch({ q: searchQuery.value.trim(), top_k: topK.value, source_type: sourceType.value })
    hits.value = result.data?.results || []
    searched.value = true
  } catch { /* Request interceptor displays the error. */ }
  finally { searching.value = false }
}

async function ask() {
  if (!question.value.trim() || asking.value || rebuilding.value || readOnly.value) return
  asking.value = true
  answer.value = undefined
  try {
    const result = await ragAsk({ q: question.value.trim(), top_k: topK.value, source_type: sourceType.value })
    answer.value = result.data
  } catch { /* Request interceptor displays the error. */ }
  finally { asking.value = false }
}
</script>

<style scoped>
.rag-page { display: flex; flex-direction: column; gap: 20px; }
.toolbar, .filters, .search-row, .ask-actions { display: flex; align-items: center; gap: 12px; }
.toolbar { justify-content: space-between; flex-wrap: wrap; }
.filters { margin-top: 16px; flex-wrap: wrap; }
.search-row { margin-bottom: 16px; }
.ask-actions { margin: 16px 0; }
.examples { display: flex; align-items: center; flex-wrap: wrap; gap: 8px; margin-bottom: 16px; }
h2, h3 { margin: 0 0 12px; }
.muted { color: var(--text-secondary); font-size: 13px; }
.answer-text, .chunk-text { white-space: pre-wrap; overflow-wrap: anywhere; line-height: 1.8; }
.answer-text { padding: 16px; border: 1px solid var(--border-color); border-radius: var(--radius-md); }
.citations { list-style: none; padding: 0; }
.citations li { margin: 12px 0; }
summary { cursor: pointer; overflow-wrap: anywhere; }
.snippet { line-height: 1.6; }
@media (max-width: 640px) { .search-row { flex-wrap: wrap; } }
</style>
