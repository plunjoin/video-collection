import axios, { AxiosInstance, AxiosResponse, InternalAxiosRequestConfig } from 'axios'
import { ElMessage } from 'element-plus'
import router from '@/router'

const service: AxiosInstance = axios.create({
  baseURL: '',
  timeout: 30000,
  headers: {
    'Content-Type': 'application/json'
  }
})

// 请求拦截器
service.interceptors.request.use(
  (config: InternalAxiosRequestConfig) => {
    const token = localStorage.getItem('admin_token')
    const user = JSON.parse(localStorage.getItem('admin_user') || 'null')
    if (user?.role === 'observer' && config.url?.startsWith('/api/admin/') && !['get', 'head'].includes(config.method || 'get')) {
      ElMessage.warning('观察员只能查看，无法执行此操作')
      return Promise.reject(new Error('观察员无操作权限'))
    }
    if (token) {
      config.headers['Authorization'] = `Bearer ${token}`
    }
    return config
  },
  (error) => {
    return Promise.reject(error)
  }
)

// 响应拦截器
service.interceptors.response.use(
  (response: AxiosResponse) => {
    const res = response.data
    // 如果不是标准 JSON 格式或者没有 code，直接返回
    if (res && typeof res.code === 'number') {
      if (res.code === 1) {
        return res
      } else {
        const errorMsg = res.error || res.msg || '操作失败'
        ElMessage.error(errorMsg)
        return Promise.reject(new Error(errorMsg))
      }
    }
    return res
  },
  (error) => {
    const status = error.response ? error.response.status : null
    let errorMsg = '网络连接异常，请检查后端服务'

    if (error.response && error.response.data) {
      errorMsg = error.response.data.error || error.response.data.msg || error.message
    } else if (error.message) {
      errorMsg = error.message
    }

    if (status === 401) {
      ElMessage.error('登录状态已失效，请重新登录')
      localStorage.removeItem('admin_token')
      localStorage.removeItem('admin_user')
      if (router.currentRoute.value.path !== '/login') {
        router.push({
          path: '/login',
          query: { redirect: router.currentRoute.value.fullPath }
        })
      }
    } else if (status === 403) {
      ElMessage.error(errorMsg || '无权访问此管理资源')
    } else {
      ElMessage.error(errorMsg)
    }

    return Promise.reject(error)
  }
)

export default service
