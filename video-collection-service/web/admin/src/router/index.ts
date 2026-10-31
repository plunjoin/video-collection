import { createRouter, createWebHistory, RouteRecordRaw } from 'vue-router'
import NProgress from 'nprogress'
import 'nprogress/nprogress.css'
import { useUserStore } from '@/store/user'
import { canVisit } from '@/utils/permissions'

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
      { path: 'business-types', name: 'BusinessTypes', component: () => import('@/views/business-types/index.vue'), meta: { title: '业务类型' } },
      { path: 'reviews', name: 'Reviews', component: () => import('@/views/reviews/index.vue'), meta: { title: '内容审核中心' } },
      { path: 'growth', name: 'Growth', component: () => import('@/views/growth/index.vue'), meta: { title: '日活与积分运营' } },
      { path: 'ads', name: 'Ads', component: () => import('@/views/ads/index.vue'), meta: { title: '广告位管理' } },
      { path: 'notifications', name: 'Notifications', component: () => import('@/views/notifications/index.vue'), meta: { title: '消息通知' } },
      {
        path: 'dashboard',
        name: 'Dashboard',
        component: () => import('@/views/dashboard/index.vue'),
        meta: { title: '仪表盘' }
      },
      {
        path: 'collection-rules',
        name: 'CollectionRules',
        component: () => import('@/views/collection/index.vue'),
        meta: { title: '使魔规则工坊' }
      },
      {
        path: 'sources',
        name: 'Sources',
        component: () => import('@/views/sources/index.vue'),
        meta: { title: '使魔节点管理' }
      },
      {
        path: 'resources',
        name: 'Resources',
        component: () => import('@/views/resources/index.vue'),
        redirect: '/resources/video',
        meta: { title: '资源库' },
        children: [
          { path: 'video', name: 'ResourcesVideo', component: () => import('@/views/videos/index.vue'), meta: { title: '视频库' } },
          { path: 'news', name: 'ResourcesNews', component: () => import('@/views/news/index.vue'), meta: { title: '资讯' } },
          { path: 'record', name: 'ResourcesRecord', component: () => import('@/views/resources/BizTypeRows.vue'), meta: { title: '通用数据' } },
          { path: 'biz/:slug', name: 'ResourcesBiz', component: () => import('@/views/resources/BizTypeRows.vue'), meta: { title: '业务数据' } },
        ]
      },
      { path: 'videos', name: 'Videos', redirect: '/resources/video', meta: { title: '视频仓库', hidden: true } },
      {
        path: 'wiki',
        name: 'WikiKnowledge',
        component: () => import('@/views/wiki/index.vue'),
        meta: { title: 'Wiki 知识库' }
      },
      {
        path: 'rag',
        name: 'RagKnowledge',
        component: () => import('@/views/rag/index.vue'),
        meta: { title: 'RAG 知识库' }
      },
      {
        path: 'news', name: 'News', redirect: '/resources/news', meta: { title: '资讯管理', hidden: true }
      },
      {
        path: 'community',
        name: 'Community',
        component: () => import('@/views/community/index.vue'),
        meta: { title: '社区管理' }
      },
      {
        path: 'scheduler',
        name: 'Scheduler',
        component: () => import('@/views/scheduler/index.vue'),
        meta: { title: '使魔定时调度' }
      },
      {
        path: 'logs',
        name: 'CollectionLogs',
        redirect: '/scheduler'
      },
      {
        path: 'feedbacks',
        name: 'Feedbacks',
        component: () => import('@/views/feedbacks/index.vue'),
        meta: { title: '求片与反馈' }
      },
      {
        path: 'users',
        name: 'Users',
        component: () => import('@/views/users/index.vue'),
        meta: { title: '用户账号管理' }
      },
      {
        path: 'themes',
        name: 'Themes',
        component: () => import('@/views/themes/index.vue'),
        meta: { title: '客户端主题' }
      },
      {
        path: 'analytics',
        name: 'Analytics',
        component: () => import('@/views/analytics/index.vue'),
        meta: { title: '埋点信息预览' }
      },
      {
        path: 'webhooks',
        name: 'Webhooks',
        component: () => import('@/views/webhooks/index.vue'),
        meta: { title: 'Webhook 回调采集' }
      },
      {
        path: 'settings',
        name: 'Settings',
        component: () => import('@/views/settings/index.vue'),
        meta: { title: '系统配置' }
      },
      {
        path: 'bootstrap',
        name: 'Bootstrap',
        component: () => import('@/views/bootstrap/index.vue'),
        meta: { title: '基础配置' }
      },
      {
        path: 'database',
        name: 'Database',
        component: () => import('@/views/database/index.vue'),
        meta: { title: '数据库管理' }
      },
      {
        path: 'system-logs',
        name: 'SystemLogs',
        component: () => import('@/views/logs/index.vue'),
        meta: { title: '系统日志' }
      }
    ]
  },
  {
    path: '/:pathMatch(.*)*',
    redirect: '/dashboard',
    meta: { hidden: true }
  }
]

// 管理后台作为 /admin/ 子应用由 Go 服务托管（vite base 与 go:embed 对齐）
const router = createRouter({
  history: createWebHistory('/admin'),
  routes
})

// 白名单路由
const whiteList = ['/login']

router.beforeEach(async (to, _from, next) => {
  NProgress.start()
  const token = localStorage.getItem('admin_token')

  if (to.meta?.title && to.meta.title !== '管理员登录') {
    document.title = `${to.meta.title} - 视频采集管理`
  }

  if (token) {
    const store = useUserStore()
    const user = await store.fetchUserInfo()
    if (!user || user.role === 'user') {
      store.setToken(''); store.setUserInfo(null)
      if (to.path === '/login') next(); else next('/login'); NProgress.done(); return
    }
    if (to.path !== '/login' && !canVisit(user.role, to.path)) {
      next('/dashboard'); NProgress.done(); return
    }
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
