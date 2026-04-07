<template>
  <div class="r-feedback-host" aria-live="polite">
    <TransitionGroup name="r-toast">
      <div v-for="notice in feedbackState.notices" :key="notice.id" class="r-toast" :class="`r-toast--${notice.type}`" role="status">
        <span class="r-toast__mark" aria-hidden="true">{{ markFor(notice.type) }}</span>
        <span>{{ notice.message }}</span>
        <button type="button" class="r-toast__close" aria-label="关闭提示" @click="dismiss(notice.id)">×</button>
      </div>
    </TransitionGroup>
  </div>

  <r-dialog :model-value="Boolean(currentConfirmation)" :title="currentConfirmation?.title || '请确认'" width="min(28rem, calc(100vw - 2rem))" @update:model-value="onDialogChange">
    <p class="r-confirm-message">{{ currentConfirmation?.message }}</p>
    <template #footer>
      <button type="button" class="r-button" @click="settleConfirmation(false)">取消</button>
      <button type="button" class="r-button r-button--primary" @click="settleConfirmation(true)">确定</button>
    </template>
  </r-dialog>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { feedbackState, settleConfirmation } from './feedback'

const currentConfirmation = computed(() => feedbackState.confirmations[0])
const markFor = (type: string) => ({ success: '✓', warning: '!', error: '×', info: 'i' }[type] || 'i')
const dismiss = (id: number) => { feedbackState.notices = feedbackState.notices.filter((notice) => notice.id !== id) }
const onDialogChange = (open: boolean) => { if (!open && currentConfirmation.value) settleConfirmation(false) }
</script>

<style scoped>
.r-feedback-host { position: fixed; z-index: 2000; inset-block-start: 1rem; inset-inline-end: 1rem; display: flex; width: min(24rem, calc(100vw - 2rem)); flex-direction: column; gap: .6rem; pointer-events: none; }
.r-toast { display: flex; align-items: flex-start; gap: .7rem; padding: .8rem 1rem; border: 1px solid var(--border-color); border-radius: 14px; background: var(--surface); color: var(--text-primary); box-shadow: var(--shadow-pop); pointer-events: auto; }
.r-toast__mark { display: grid; width: 1.35rem; height: 1.35rem; flex: none; place-items: center; border-radius: 50%; background: var(--surface-hover); font-weight: 700; }
.r-toast--success .r-toast__mark { color: #16803c; background: #e9f8ef; }
.r-toast--warning .r-toast__mark { color: #a65c00; background: #fff4dd; }
.r-toast--error .r-toast__mark { color: #b42318; background: #fff0ef; }
.r-toast__close { margin-inline-start: auto; border: 0; background: transparent; color: var(--text-secondary); font-size: 1.2rem; cursor: pointer; }
.r-confirm-message { line-height: 1.65; color: var(--text-regular); }
.r-toast-enter-active, .r-toast-leave-active, .r-toast-move { transition: all .18s ease; }
.r-toast-enter-from, .r-toast-leave-to { opacity: 0; transform: translateY(-8px); }
</style>
