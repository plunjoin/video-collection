<template>
  <aside class="entropy-sidebar" :class="{ 'is-collapsed': isCollapsed }" :data-collapsed="isCollapsed || undefined">
    <header class="sidebar-brand-row">
      <div v-if="!isCollapsed" class="brand-lockup" @click="goDashboard" title="返回仪表盘">
        <span class="brand-mark" aria-hidden="true">B</span>
        <span class="brand-copy">
          <strong>Bllii Studio</strong>
          <small>动漫聚合与运营工作台</small>
        </span>
      </div>

      <r-tooltip v-if="isCollapsed" content="打开边栏" side="right" :delay-duration="120">
        <button class="collapsed-brand-toggle" type="button" aria-label="打开边栏" :aria-expanded="false" @click="toggleCollapsed">
          <span class="brand-mark collapsed-mark" aria-hidden="true">B</span>
          <span class="collapsed-toggle-icon" aria-hidden="true"><PanelLeftOpen :size="19" /></span>
        </button>
      </r-tooltip>

      <r-tooltip v-else content="收起边栏" side="right" :delay-duration="120">
        <button class="sidebar-toggle" type="button" aria-label="收起边栏" :aria-expanded="true" @click="toggleCollapsed">
          <PanelLeft :size="19" />
        </button>
      </r-tooltip>
    </header>

    <div class="sidebar-search" :class="{ 'search-collapsed': isCollapsed }">
      <r-tooltip v-if="isCollapsed" content="搜索导航" side="right" :delay-duration="120">
        <button class="search-collapsed-button" type="button" aria-label="展开并搜索导航" @click="focusSearch">
          <Search :size="17" />
        </button>
      </r-tooltip>
      <label v-else class="search-box">
        <Search class="search-icon" :size="16" aria-hidden="true" />
        <input ref="searchInput" v-model="searchQuery" type="search" placeholder="搜索导航..." aria-label="搜索导航" @keydown.esc="searchQuery = ''" />
        <button v-if="searchQuery" type="button" class="search-clear" aria-label="清除搜索" @click="searchQuery = ''; focusSearch()">×</button>
        <kbd v-else class="search-shortcut">⌘ K</kbd>
      </label>
    </div>

    <nav class="sidebar-navigation" aria-label="主导航">
      <section v-for="section in filteredSections" :key="section.title" class="nav-section">
        <h2 v-if="!isCollapsed" class="nav-section-title">{{ section.title }}</h2>
        <template v-for="item in section.items" :key="item.path">
          <r-tooltip v-if="isCollapsed" :content="item.title" side="right" :delay-duration="120">
            <router-link :to="item.path" class="nav-item nav-item-collapsed" :class="{ 'is-active': isActive(item.path) }" :aria-label="item.title" :aria-current="isActive(item.path) ? 'page' : undefined">
              <component :is="item.icon" :size="18" aria-hidden="true" />
            </router-link>
          </r-tooltip>
          <router-link v-else :to="item.path" class="nav-item" :class="{ 'is-active': isActive(item.path) }" :aria-current="isActive(item.path) ? 'page' : undefined">
            <component :is="item.icon" :size="17" aria-hidden="true" />
            <span class="nav-label">{{ item.title }}</span>
          </router-link>
        </template>
      </section>
      <div v-if="!filteredSections.length" class="search-empty">没有匹配的导航项</div>
    </nav>

    <footer class="sidebar-footer">
      <r-tooltip v-if="isCollapsed" content="系统设置" side="right" :delay-duration="120">
        <router-link to="/settings" class="nav-item nav-item-collapsed" :class="{ 'is-active': isActive('/settings') }" aria-label="系统设置">
          <Settings2 :size="18" aria-hidden="true" />
        </router-link>
      </r-tooltip>
      <router-link v-else to="/settings" class="nav-item settings-link" :class="{ 'is-active': isActive('/settings') }">
        <Settings2 :size="17" aria-hidden="true" />
        <span class="nav-label">系统设置</span>
      </router-link>

      <r-dropdown trigger="click" placement="top-end" @command="handleCommand">
        <button class="profile-card" :class="{ 'profile-collapsed': isCollapsed }" type="button" :aria-label="`用户菜单：${profileName}`">
          <span class="profile-avatar" :class="{ 'has-avatar': userStore.userInfo?.avatar }">
            <img v-if="userStore.userInfo?.avatar" :src="userStore.userInfo.avatar" :alt="profileName" />
            <span v-else>{{ profileInitial }}</span>
          </span>
          <span v-if="!isCollapsed" class="profile-copy">
            <strong>{{ profileName }}</strong>
            <small>{{ roleLabels[userStore.userInfo?.role || 'user'] }}</small>
          </span>
          <Settings2 v-if="!isCollapsed" class="profile-settings-icon" :size="16" aria-hidden="true" />
        </button>
        <template #dropdown>
          <r-dropdown-menu>
            <r-dropdown-item command="portal"><Monitor :size="15" />客户端门户</r-dropdown-item>
            <r-dropdown-item command="docs"><Reading :size="15" />接口文档</r-dropdown-item>
            <r-dropdown-item command="logout" divided><SwitchButton :size="15" />退出登录</r-dropdown-item>
          </r-dropdown-menu>
        </template>
      </r-dropdown>
    </footer>
  </aside>
</template>

<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { notify, confirmAction } from '@/components/radix/feedback'
import { useAppStore } from '@/store/app'
import { useUserStore } from '@/store/user'
import { roleLabels, canVisit } from '@/utils/permissions'
import {
  Activity,
  Bell,
  Reading,
  Brush,
  ChatDotRound,
  ChatLineRound,
  Clock,
  Coin,
  Connection,
  Document,
  Film,
  Lightning,
  Network,
  SwitchButton,
  Monitor,
  Odometer,
  PanelLeft,
  PanelLeftOpen,
  PriceTag,
  Search,
  Settings2,
  SetUp,
  TrendCharts,
  User,
} from '@/components/radix/icons'

const appStore = useAppStore()
const userStore = useUserStore()
const route = useRoute()
const router = useRouter()
const searchInput = ref<HTMLInputElement>()
const searchQuery = ref('')
const isCollapsed = computed(() => appStore.sidebarCollapse)

const allSections = [
  {
    title: '工作空间',
    items: [
      { path: '/dashboard', title: '工作台', icon: Odometer },
    ],
  },
  {
    title: '内容管理',
    items: [
      { path: '/resources', title: '资源库', icon: Film },
      { path: '/wiki', title: 'Wiki 知识库', icon: Network },
      { path: '/rag', title: 'RAG 知识库', icon: Search },
      { path: '/sources', title: '使魔节点管理', icon: SetUp },
      { path: '/business-types', title: '业务类型', icon: Document },
      { path: '/collection-rules', title: '使魔规则工坊', icon: SetUp },
      { path: '/scheduler', title: '使魔调度', icon: Clock },
      { path: '/community', title: '社区内容', icon: ChatDotRound },
      { path: '/reviews', title: '内容审核', icon: Document },
      { path: '/feedbacks', title: '求片反馈', icon: ChatLineRound },
      { path: '/webhooks', title: 'Webhook 回调', icon: Lightning },
      { path: '/ads', title: '广告位', icon: PriceTag },
    ],
  },
  {
    title: '用户运营',
    items: [
      { path: '/growth', title: '成长运营', icon: TrendCharts },
      { path: '/analytics', title: '埋点统计', icon: Activity },
      { path: '/notifications', title: '消息通知', icon: Bell },
      { path: '/users', title: '用户账号', icon: User },
    ],
  },
  {
    title: '系统工具',
    items: [
      { path: '/themes', title: '客户端主题', icon: Brush },
      { path: '/bootstrap', title: '基础配置', icon: SetUp },
      { path: '/database', title: '数据库管理', icon: Coin },
      { path: '/system-logs', title: '系统日志', icon: Document },
    ],
  },
]

const permittedSections = computed(() => allSections
  .map((section) => ({ ...section, items: section.items.filter((item) => canVisit(userStore.userInfo?.role || '', item.path)) }))
  .filter((section) => section.items.length > 0))

const filteredSections = computed(() => {
  const query = searchQuery.value.trim().toLocaleLowerCase()
  if (!query) return permittedSections.value
  return permittedSections.value
    .map((section) => ({ ...section, items: section.items.filter((item) => item.title.toLocaleLowerCase().includes(query)) }))
    .filter((section) => section.items.length > 0)
})

const profileName = computed(() => userStore.userInfo?.nickname || userStore.userInfo?.username || '管理员')
const profileInitial = computed(() => profileName.value.slice(0, 1).toUpperCase())

function isActive(path: string) {
  if (path === '/resources') {
    return route.path === '/resources' || route.path.startsWith('/resources/') || route.path === '/videos' || route.path.startsWith('/videos/') || route.path === '/news' || route.path.startsWith('/news/')
  }
  return route.path === path || route.path.startsWith(`${path}/`)
}

function goDashboard() {
  void router.push('/dashboard')
}

function toggleCollapsed() {
  appStore.toggleSidebar()
}

function focusSearch() {
  if (isCollapsed.value) appStore.toggleSidebar()
  window.setTimeout(() => searchInput.value?.focus(), 180)
}

function handleGlobalShortcut(event: KeyboardEvent) {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
    event.preventDefault()
    focusSearch()
  }
}

const handleCommand = async (command: string) => {
  if (command === 'logout') {
    try {
      await confirmAction('确定要退出当前管理员登录状态吗？', '安全退出')
      await userStore.logout()
      notify('已安全退出', 'success')
      await router.push('/login')
    } catch {}
  } else if (command === 'docs') {
    window.open('/docs', '_blank', 'noopener,noreferrer')
  } else if (command === 'portal') {
    const url = import.meta.env.VITE_PORTAL_URL || '/'
    window.open(url, '_blank', 'noopener,noreferrer')
  }
}

onMounted(() => window.addEventListener('keydown', handleGlobalShortcut))
onUnmounted(() => window.removeEventListener('keydown', handleGlobalShortcut))
</script>

<style scoped lang="scss">
.entropy-sidebar {
  --sidebar-width: 256px;
  --sidebar-collapsed-width: 64px;
  --nav-bg: var(--glass-panel); // 与内容区卡片同一玻璃材质
  --nav-border: var(--border-color); // 与内容区卡片同边框色
  --nav-border-light: rgba(20, 32, 57, 0.05);
  --nav-text-primary: var(--text-primary);
  --nav-text-secondary: var(--text-regular);
  --nav-text-muted: var(--text-secondary);
  --nav-bg-subtle: rgba(255, 255, 255, 0.55);
  --nav-bg-active: rgba(79, 110, 242, 0.1);
  --nav-primary: var(--brand);

  display: flex;
  position: relative;
  z-index: 10;
  flex: 0 0 var(--sidebar-width);
  flex-direction: column;
  width: var(--sidebar-width);
  min-width: 0;
  height: 100%;
  overflow: hidden;
  color: var(--nav-text-primary);
  background: var(--nav-bg);
  border: 1px solid var(--nav-border); // 与内容区卡片同款完整玻璃边框
  border-radius: var(--radius-lg); // 与内容区卡片同圆角语言
  box-shadow: 0 1px 2px rgba(22, 33, 58, 0.04), 0 8px 24px rgba(22, 33, 58, 0.05), var(--glass-highlight); // 更轻的浮起，与内容卡片层级一致
  backdrop-filter: var(--glass-blur);
  -webkit-backdrop-filter: var(--glass-blur);
  transition: width 300ms cubic-bezier(0.16, 1, 0.3, 1), flex-basis 300ms cubic-bezier(0.16, 1, 0.3, 1);
  user-select: none;

  &.is-collapsed {
    flex-basis: var(--sidebar-collapsed-width);
    width: var(--sidebar-collapsed-width);
  }

  .sidebar-brand-row {
    display: flex;
    flex: 0 0 56px;
    height: 56px;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    padding: 0 12px;
    border-bottom: 1px solid var(--nav-border-light);
    border-radius: var(--radius-lg) var(--radius-lg) 0 0;
  }

  .brand-lockup {
    display: flex;
    min-width: 0;
    align-items: center;
    gap: 10px;
    cursor: pointer;
  }

  .brand-mark {
    display: inline-flex;
    width: 32px;
    height: 32px;
    flex: 0 0 32px;
    align-items: center;
    justify-content: center;
    border-radius: 9px;
    color: #fff;
    background: linear-gradient(135deg, #5d7af5 0%, #3d5ce0 100%);
    box-shadow: 0 2px 8px rgba(79, 110, 242, .24);
    font-size: 14px;
    font-weight: 800;
    letter-spacing: -.04em;
  }

  .brand-copy {
    display: flex;
    min-width: 0;
    flex-direction: column;
    gap: 2px;

    strong {
      overflow: hidden;
      color: var(--nav-text-primary);
      font-size: 13px;
      font-weight: 700;
      letter-spacing: -.02em;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    small {
      color: var(--nav-text-muted);
      font-size: 10px;
      line-height: 1.2;
    }
  }

  .sidebar-toggle,
  .collapsed-brand-toggle,
  .search-collapsed-button {
    display: inline-flex;
    position: relative;
    width: 34px;
    height: 34px;
    flex: 0 0 34px;
    align-items: center;
    justify-content: center;
    padding: 0;
    color: var(--nav-text-secondary);
    background: transparent;
    border: 0;
    border-radius: var(--radius-sm);
    cursor: pointer;
    outline: none;
    transition: background 180ms ease, color 180ms ease, transform 180ms ease;

    &:hover {
      color: var(--nav-text-primary);
      background: var(--nav-bg-subtle);
    }

    &:focus-visible {
      box-shadow: 0 0 0 2px rgba(79, 110, 242, .45);
    }
  }

  .collapsed-brand-toggle {
    width: 38px;
    height: 38px;
    flex-basis: 38px;
    margin: 0 auto;

    .collapsed-mark,
    .collapsed-toggle-icon {
      position: absolute;
      transition: opacity 180ms ease, transform 180ms ease;
    }

    .collapsed-mark {
      opacity: 1;
      transform: scale(1);
    }

    .collapsed-toggle-icon {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      color: var(--nav-text-secondary);
      opacity: 0;
      transform: scale(.88);
    }

    &:hover .collapsed-mark,
    &:focus-visible .collapsed-mark {
      opacity: 0;
      transform: scale(.88);
    }

    &:hover .collapsed-toggle-icon,
    &:focus-visible .collapsed-toggle-icon {
      color: var(--nav-text-primary);
      opacity: 1;
      transform: scale(1);
    }
  }

  .sidebar-search {
    display: flex;
    flex: 0 0 auto;
    justify-content: center;
    padding: 12px 12px 6px;
  }

  .search-box {
    display: flex;
    width: 100%;
    min-width: 0;
    min-height: 36px;
    align-items: center;
    gap: 8px;
    padding: 0 9px;
    color: var(--nav-text-muted);
    background: rgba(20, 32, 57, .04);
    border: 1px solid var(--nav-border-light);
    border-radius: var(--radius-md);
    transition: border-color 180ms ease, background 180ms ease, box-shadow 180ms ease;

    &:focus-within {
      background: rgba(255, 255, 255, .8);
      border-color: rgba(79, 110, 242, .35);
      box-shadow: 0 0 0 3px rgba(79, 110, 242, .1);
    }

    .search-icon { flex: 0 0 auto; }

    input {
      width: 100%;
      min-width: 0;
      padding: 0;
      color: var(--nav-text-primary);
      background: transparent;
      border: 0;
      outline: 0;
      font: inherit;
      font-size: 11px;

      &::placeholder { color: var(--nav-text-muted); }
      &::-webkit-search-cancel-button { display: none; }
    }
  }

  .search-shortcut {
    flex: 0 0 auto;
    padding: 2px 5px;
    color: var(--nav-text-muted);
    background: rgba(15, 23, 42, .045);
    border: 1px solid rgba(148, 163, 184, .22);
    border-radius: 5px;
    font-family: inherit;
    font-size: 9px;
    line-height: 1.3;
  }

  .search-clear {
    display: inline-flex;
    width: 20px;
    height: 20px;
    flex: 0 0 20px;
    align-items: center;
    justify-content: center;
    padding: 0;
    color: var(--nav-text-muted);
    background: transparent;
    border: 0;
    border-radius: 5px;
    cursor: pointer;
    font-size: 15px;

    &:hover { color: var(--nav-text-primary); background: #eef2f7; }
  }

  .sidebar-navigation {
    flex: 1 1 auto;
    min-height: 0;
    overflow-x: hidden;
    overflow-y: auto;
    padding: 8px 10px 14px;
    scrollbar-width: thin;
    scrollbar-color: rgba(113, 128, 155, 0.32) transparent; // 与全局滚动条一致
  }

  .nav-section + .nav-section { margin-top: 11px; }

  .nav-section-title {
    overflow: hidden;
    margin: 0;
    padding: 10px 10px 6px;
    color: var(--nav-text-muted);
    font-size: 9px;
    font-weight: 700;
    letter-spacing: .09em;
    line-height: 1.2;
    text-overflow: ellipsis;
    text-transform: uppercase;
    white-space: nowrap;
  }

  .nav-item {
    display: flex;
    position: relative;
    width: 100%;
    min-width: 0;
    min-height: 36px;
    align-items: center;
    gap: 10px;
    margin: 2px 0;
    padding: 0 10px;
    color: var(--nav-text-secondary);
    text-decoration: none;
    border-radius: var(--radius-sm);
    outline: 0;
    font-size: 11px;
    font-weight: 500;
    line-height: 1.25;
    transition: background 160ms ease, color 160ms ease, box-shadow 160ms ease;

    > svg { flex: 0 0 auto; color: var(--nav-text-muted); transition: color 160ms ease; }

    &:hover {
      color: var(--nav-text-primary);
      background: var(--nav-bg-subtle);
      > svg { color: var(--nav-text-secondary); }
    }

    &:focus-visible { box-shadow: 0 0 0 2px rgba(79, 110, 242, .45); }

    &.is-active {
      color: var(--nav-primary);
      background: var(--nav-bg-active);
      font-weight: 650;
      > svg { color: var(--nav-primary); }
    }
  }

  .nav-item-collapsed {
    width: 40px;
    height: 40px;
    min-height: 40px;
    justify-content: center;
    margin: 3px auto;
    padding: 0;
    border-radius: var(--radius-md);
  }

  .nav-label {
    overflow: hidden;
    min-width: 0;
    flex: 1 1 auto;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .nav-badge {
    display: inline-flex;
    min-width: 19px;
    height: 18px;
    flex: 0 0 auto;
    align-items: center;
    justify-content: center;
    padding: 0 5px;
    color: #6d28d9;
    background: #f5f3ff;
    border-radius: 999px;
    font-size: 9px;
    font-weight: 700;
  }

  .search-empty {
    padding: 18px 10px;
    color: var(--nav-text-muted);
    font-size: 11px;
    text-align: center;
  }

  .sidebar-footer {
    flex: 0 0 auto;
    padding: 8px 10px 10px;
    border-top: 1px solid var(--nav-border-light);
    border-radius: 0 0 var(--radius-lg) var(--radius-lg);
  }

  .settings-link { margin: 0 0 5px; }

  .profile-card {
    display: flex;
    width: 100%;
    min-width: 0;
    min-height: 50px;
    align-items: center;
    gap: 9px;
    padding: 6px 8px;
    color: var(--nav-text-primary);
    text-align: left;
    background: transparent;
    border: 1px solid transparent;
    border-radius: 11px;
    cursor: pointer;
    outline: none;
    transition: background 160ms ease, border-color 160ms ease;

    &:hover,
    &[data-state='open'] {
      background: var(--nav-bg-subtle);
      border-color: var(--nav-border-light);
    }

    &:focus-visible { box-shadow: 0 0 0 2px rgba(79, 110, 242, .45); }
  }

  .profile-collapsed {
    width: 42px;
    min-height: 42px;
    justify-content: center;
    margin: 0 auto;
    padding: 3px;
    border-radius: 50%;
  }

  .profile-avatar {
    display: inline-flex;
    width: 34px;
    height: 34px;
    flex: 0 0 34px;
    align-items: center;
    justify-content: center;
    overflow: hidden;
    color: #fff;
    background: linear-gradient(135deg, #5d7af5, #3d5ce0); // 与品牌主色同族
    border: 1px solid rgba(255, 255, 255, .82);
    border-radius: 50%;
    box-shadow: 0 1px 3px rgba(15, 23, 42, .12);
    font-size: 11px;
    font-weight: 700;

    img { width: 100%; height: 100%; object-fit: cover; }
  }

  .profile-copy {
    display: flex;
    min-width: 0;
    flex: 1 1 auto;
    flex-direction: column;
    gap: 2px;

    strong {
      overflow: hidden;
      color: var(--nav-text-primary);
      font-size: 11px;
      font-weight: 650;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    small {
      overflow: hidden;
      color: var(--nav-text-muted);
      font-size: 9px;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  }

  .profile-settings-icon { flex: 0 0 auto; color: var(--nav-text-muted); }

  .search-collapsed {
    padding: 7px 0 5px;
  }

  @media (max-width: 720px) {
    --sidebar-width: 216px;
    --sidebar-collapsed-width: 56px;

    .sidebar-brand-row { padding: 0 9px; }
    .sidebar-navigation { padding-right: 6px; padding-left: 6px; }
    .sidebar-footer { padding-right: 6px; padding-left: 6px; }
  }
}

html.dark .entropy-sidebar {
  --nav-bg: var(--glass-panel); // 暗色令牌自动翻转，与暗色卡片同材质
  --nav-border: rgba(255, 255, 255, 0.09);
  --nav-border-light: rgba(255, 255, 255, 0.06);
  --nav-text-primary: #f1f4fb;
  --nav-text-secondary: #b9c2d6;
  --nav-text-muted: #8f9cb5;
  --nav-bg-subtle: rgba(255, 255, 255, 0.06);
  --nav-bg-active: rgba(126, 148, 255, 0.14);
  --nav-primary: #7e94ff;

  .search-shortcut { color: #94a3b8; background: rgba(255, 255, 255, 0.06); border-color: rgba(148, 163, 184, 0.15); }
  .search-clear:hover { color: #f8fafc; background: rgba(255, 255, 255, 0.08); }
  .nav-badge { color: #c4b5fd; background: rgba(139, 92, 246, 0.16); }
}
</style>
