<template>
  <div class="tags-view-container">
    <el-scrollbar class="tags-scrollbar">
      <div class="tags-wrapper">
        <router-link
          v-for="tag in tagsViewStore.visitedViews"
          :key="tag.path"
          :to="{ path: tag.path }"
          class="tag-item"
          :class="{ active: isActive(tag.path) }"
        >
          <span class="dot" v-if="isActive(tag.path)"></span>
          <span class="title">{{ tag.title }}</span>
          <el-icon
            v-if="tag.path !== '/dashboard'"
            class="close-icon"
            @click.prevent.stop="closeTag(tag.path)"
          >
            <Close />
          </el-icon>
        </router-link>
      </div>
    </el-scrollbar>

    <!-- 标签操作下拉 -->
    <div class="actions">
      <el-dropdown trigger="click" @command="handleCommand">
        <div class="action-btn">
          <el-icon><ArrowDown /></el-icon>
        </div>
        <template #dropdown>
          <el-dropdown-menu>
            <el-dropdown-item command="refresh">
              <el-icon><Refresh /></el-icon>刷新当前
            </el-dropdown-item>
            <el-dropdown-item command="closeOthers" divided>
              <el-icon><CircleClose /></el-icon>关闭其他
            </el-dropdown-item>
            <el-dropdown-item command="closeAll">
              <el-icon><FolderDelete /></el-icon>关闭全部
            </el-dropdown-item>
          </el-dropdown-menu>
        </template>
      </el-dropdown>
    </div>
  </div>
</template>

<script setup lang="ts">
import { watch, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useTagsViewStore } from '@/store/tagsView'
import { Close, ArrowDown, Refresh, CircleClose, FolderDelete } from '@element-plus/icons-vue'

const route = useRoute()
const router = useRouter()
const tagsViewStore = useTagsViewStore()

const isActive = (path: string) => {
  return route.path === path
}

const addCurrentTag = () => {
  if (route.meta?.title) {
    tagsViewStore.addView(route)
  }
}

const closeTag = (path: string) => {
  tagsViewStore.delView(path)
  if (isActive(path)) {
    const latest = tagsViewStore.visitedViews[tagsViewStore.visitedViews.length - 1]
    if (latest) {
      router.push(latest.path)
    } else {
      router.push('/')
    }
  }
}

const handleCommand = (cmd: string) => {
  if (cmd === 'refresh') {
    router.replace({ path: '/redirect' + route.fullPath }).catch(() => {
      window.location.reload()
    })
  } else if (cmd === 'closeOthers') {
    tagsViewStore.delOthersViews(route.path)
  } else if (cmd === 'closeAll') {
    tagsViewStore.delAllViews()
    router.push('/dashboard')
  }
}

watch(
  () => route.path,
  () => {
    addCurrentTag()
  }
)

onMounted(() => {
  // 默认加入仪表盘
  tagsViewStore.addView({
    path: '/dashboard',
    meta: { title: '系统仪表盘' },
    name: 'Dashboard',
    fullPath: '/dashboard'
  } as any)
  addCurrentTag()
})
</script>

<style scoped lang="scss">
.tags-view-container {
  height: 38px;
  background-color: var(--card-bg);
  border-bottom: 1px solid var(--border-color);
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 12px;
  user-select: none;

  .tags-scrollbar {
    flex: 1;
    overflow: hidden;
  }

  .tags-wrapper {
    display: flex;
    align-items: center;
    gap: 6px;
    height: 38px;
    white-space: nowrap;

    .tag-item {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      height: 26px;
      line-height: 26px;
      padding: 0 10px;
      border-radius: 4px;
      font-size: 12px;
      color: var(--text-regular);
      background-color: rgba(148, 163, 184, 0.12);
      text-decoration: none;
      transition: all 0.2s;

      &:hover {
        background-color: rgba(148, 163, 184, 0.22);
        color: var(--text-primary);
      }

      &.active {
        background-color: rgba(99, 102, 241, 0.15);
        color: #6366f1;
        font-weight: 600;

        .dot {
          width: 6px;
          height: 6px;
          border-radius: 50%;
          background-color: #6366f1;
        }
      }

      .close-icon {
        font-size: 11px;
        border-radius: 50%;
        padding: 2px;
        transition: all 0.2s;

        &:hover {
          background-color: rgba(0, 0, 0, 0.2);
          color: #f43f5e;
        }
      }
    }
  }

  .actions {
    margin-left: 8px;
    .action-btn {
      width: 26px;
      height: 26px;
      display: flex;
      align-items: center;
      justify-content: center;
      border-radius: 4px;
      cursor: pointer;
      color: var(--text-secondary);
      &:hover {
        background: rgba(148, 163, 184, 0.2);
        color: var(--text-primary);
      }
    }
  }
}
</style>
