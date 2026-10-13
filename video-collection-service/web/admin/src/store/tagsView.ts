import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { RouteLocationNormalized } from 'vue-router'

export interface TagViewItem {
  name?: string
  path: string
  title: string
  fullPath: string
}

export const useTagsViewStore = defineStore('tagsView', () => {
  const visitedViews = ref<TagViewItem[]>([])

  const addView = (route: RouteLocationNormalized) => {
    if (!route.meta?.title) return
    const exists = visitedViews.value.some((v) => v.path === route.path)
    if (!exists) {
      visitedViews.value.push({
        name: route.name as string,
        path: route.path,
        title: (route.meta.title as string) || 'no-name',
        fullPath: route.fullPath
      })
    }
  }

  const delView = (path: string) => {
    visitedViews.value = visitedViews.value.filter((v) => v.path !== path)
  }

  const delOthersViews = (path: string) => {
    visitedViews.value = visitedViews.value.filter((v) => v.path === path || v.path === '/dashboard')
  }

  const delAllViews = () => {
    visitedViews.value = visitedViews.value.filter((v) => v.path === '/dashboard')
  }

  return {
    visitedViews,
    addView,
    delView,
    delOthersViews,
    delAllViews
  }
})
