import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useAppStore = defineStore('app', () => {
  const sidebarCollapse = ref<boolean>(localStorage.getItem('sidebar_collapse') === '1' || window.innerWidth < 768)
  const isDark = ref<boolean>(localStorage.getItem('theme_dark') === '1')

  const toggleSidebar = () => {
    sidebarCollapse.value = !sidebarCollapse.value
    localStorage.setItem('sidebar_collapse', sidebarCollapse.value ? '1' : '0')
  }

  const toggleDarkMode = (dark?: boolean) => {
    if (typeof dark === 'boolean') {
      isDark.value = dark
    } else {
      isDark.value = !isDark.value
    }
    localStorage.setItem('theme_dark', isDark.value ? '1' : '0')
    if (isDark.value) {
      document.documentElement.classList.add('dark')
    } else {
      document.documentElement.classList.remove('dark')
    }
  }

  // 初始化主题模式
  if (isDark.value) {
    document.documentElement.classList.add('dark')
  }

  return {
    sidebarCollapse,
    isDark,
    toggleSidebar,
    toggleDarkMode
  }
})
