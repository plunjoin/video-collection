import { reactive } from 'vue'

export type NoticeType = 'success' | 'warning' | 'error' | 'info'
interface Notice { id: number; message: string; type: NoticeType }
interface Confirmation { id: number; message: string; title: string; resolve: (accepted: boolean) => void }

export const feedbackState = reactive({
  notices: [] as Notice[],
  confirmations: [] as Confirmation[],
})

let nextId = 0

export function notify(message: string, type: NoticeType = 'info') {
  const id = ++nextId
  feedbackState.notices.push({ id, message, type })
  window.setTimeout(() => {
    feedbackState.notices = feedbackState.notices.filter((notice) => notice.id !== id)
  }, 3600)
}

// Rejecting on cancel matches the familiar confirm flow while the visible dialog is rendered with Reka Dialog primitives.
export function confirmAction(message: string, title = '请确认', _options?: Record<string, unknown>): Promise<void> {
  return new Promise((resolve, reject) => {
    feedbackState.confirmations.push({
      id: ++nextId,
      message,
      title,
      resolve: (accepted) => accepted ? resolve() : reject(new Error('操作已取消')),
    })
  })
}

export function settleConfirmation(accepted: boolean) {
  const confirmation = feedbackState.confirmations.shift()
  confirmation?.resolve(accepted)
}
