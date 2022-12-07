import { createRouter, createWebHistory, RouteRecordRaw } from 'vue-router'
import NProgress from 'nprogress'
import 'nprogress/nprogress.css'

NProgress.configure({ showSpinner: false })

export const routes: RouteRecordRaw[] = [
  {
    path: '/login',
    name: 'Login',
    component: () => import('@/views/login/index.vue'),
    meta: { title: '管理员登录', hidden: true }
  },
  {
    path: '/',
    component: () => import('@/layout/index.vue'),
    redirect: '/dashboard',
    children: [
      {
        path: 'dashboard',
        name: 'Dashboard',
        component: () => import('@/views/dashboard/index.vue'),
        meta: { title: '系统仪表盘', icon: 'Odometer' }
      },
      {
        path: 'sources',
        name: 'Sources',
        component: () => import('@/views/sources/index.vue'),
        meta: { title: '采集节点管理', icon: 'Connection' }
      },
      {
        path: 'videos',
        name: 'Videos',
        component: () => import('@/views/videos/index.vue'),
        meta: { title: '视频仓库', icon: 'Film' }
      },
      {
        path: 'scheduler',
        name: 'Scheduler',
        component: () => import('@/views/scheduler/index.vue'),
        meta: { title: '定时采集调度', icon: 'Clock' }
      },
      {
        path: 'feedbacks',
        name: 'Feedbacks',
        component: () => import('@/views/feedbacks/index.vue'),
        meta: { title: '求片与反馈', icon: 'ChatLineRound' }
      },
      {
        path: 'users',
        name: 'Users',
        component: () => import('@/views/users/index.vue'),
        meta: { title: '用户账号管理', icon: 'User' }
      },
      {
        path: 'themes',
        name: 'Themes',
        component: () => import('@/views/themes/index.vue'),
        meta: { title: '客户端主题', icon: 'Brush' }
      },
      {
        path: 'players',
        name: 'Players',
        component: () => import('@/views/players/index.vue'),
        meta: { title: '播放器管理', icon: 'VideoPlay' }
      },
      {
        path: 'settings',
        name: 'Settings',
        component: () => import('@/views/settings/index.vue'),
        meta: { title: '系统配置', icon: 'Setting' }
      },
      {
        path: 'database',
        name: 'Database',
        component: () => import('@/views/database/index.vue'),
        meta: { title: '数据库管理', icon: 'Coin' }
      },
      {
        path: 'logs',
        name: 'Logs',
        component: () => import('@/views/logs/index.vue'),
        meta: { title: '运行日志', icon: 'Document' }
      }
    ]
  },
  {
    path: '/:pathMatch(.*)*',
    redirect: '/dashboard',
    meta: { hidden: true }
  }
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

// 白名单路由
const whiteList = ['/login']

router.beforeEach((to, _from, next) => {
  NProgress.start()
  const token = localStorage.getItem('admin_token')

  if (to.meta?.title) {
    document.title = `${to.meta.title} - 聚合采集管理系统`
  }

  if (token) {
    if (to.path === '/login') {
      next({ path: '/' })
      NProgress.done()
    } else {
      next()
    }
  } else {
    if (whiteList.includes(to.path)) {
      next()
    } else {
      next(`/login?redirect=${encodeURIComponent(to.fullPath)}`)
      NProgress.done()
    }
  }
})

router.afterEach(() => {
  NProgress.done()
})

export default router
