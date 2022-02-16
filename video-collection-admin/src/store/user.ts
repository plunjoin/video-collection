import { defineStore } from 'pinia'
import { ref } from 'vue'
import { login as loginApi, logout as logoutApi, getMe as getMeApi } from '@/api/auth'
import type { UserInfo } from '@/types'

export const useUserStore = defineStore('user', () => {
  const token = ref<string>(localStorage.getItem('admin_token') || '')
  const userInfo = ref<UserInfo | null>(
    localStorage.getItem('admin_user') ? JSON.parse(localStorage.getItem('admin_user')!) : null
  )

  const setToken = (newToken: string) => {
    token.value = newToken
    localStorage.setItem('admin_token', newToken)
  }

  const setUserInfo = (user: UserInfo | null) => {
    userInfo.value = user
    if (user) {
      localStorage.setItem('admin_user', JSON.stringify(user))
    } else {
      localStorage.removeItem('admin_user')
    }
  }

  const login = async (form: { username: string; password: string }) => {
    const res = await loginApi(form)
    const tokenVal = res.token || res.data?.token
    const userVal = res.user || res.data?.user
    if (res.code === 1 && tokenVal) {
      setToken(tokenVal)
      if (userVal) {
        setUserInfo(userVal)
      }
      return res
    }
    throw new Error(res.error || res.msg || '登录失败，未获取到有效凭据')
  }

  const logout = async () => {
    try {
      await logoutApi()
    } finally {
      token.value = ''
      userInfo.value = null
      localStorage.removeItem('admin_token')
      localStorage.removeItem('admin_user')
    }
  }

  const fetchUserInfo = async () => {
    if (!token.value) return null
    try {
      const res = await getMeApi()
      if (res.code === 1 && res.data) {
        setUserInfo(res.data)
        return res.data
      }
    } catch (e) {
      console.warn('获取用户信息失败', e)
    }
    return null
  }

  return {
    token,
    userInfo,
    setToken,
    setUserInfo,
    login,
    logout,
    fetchUserInfo
  }
})
