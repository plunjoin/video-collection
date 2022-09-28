<template>
  <div class="settings-page">
    <el-card shadow="never" class="main-card">
      <div class="page-header">
        <span class="page-title">系统全局参数与站点信息配置</span>
        <span class="sub-desc">配置前端客户端门户显示的网站名称、友情链接、联系方式、免责声明与备案信息</span>
      </div>

      <el-form
        ref="formRef"
        :model="form"
        label-width="140px"
        class="settings-form"
        v-loading="loading"
      >
        <el-divider content-position="left">站点基础信息</el-divider>

        <el-form-item label="网站品牌名称">
          <el-input v-model="form.site_name" placeholder="例如：Bllii 动漫聚合" />
        </el-form-item>

        <el-form-item label="副标题口号">
          <el-input v-model="form.site_subtitle" placeholder="例如：追番库 • 让生活多一种可能" />
        </el-form-item>

        <el-form-item label="全站滚动公告">
          <el-input
            v-model="form.site_announcement"
            type="textarea"
            :rows="3"
            placeholder="展示在客户端首页顶部的通知公告内容"
          />
        </el-form-item>

        <el-form-item label="公告栏展示开关">
          <el-switch
            v-model="form.site_notice_enabled"
            active-value="1"
            inactive-value="0"
            active-text="在前端显示公告"
            inactive-text="隐藏"
          />
        </el-form-item>

        <!-- 友情链接管理 -->
        <el-divider content-position="left">底部友情链接配置（前台页脚实时联动）</el-divider>

        <div class="friend-links-box">
          <div class="table-actions">
            <span class="tip-text">配置展示在网站底部的友情链接列表，可自定义名称、网址与站点说明。</span>
            <el-button type="primary" size="small" :icon="Plus" @click="handleAddLink">
              添加友情链接
            </el-button>
          </div>

          <el-table :data="friendLinks" border stripe style="width: 100%; margin-top: 12px">
            <el-table-column label="网站名称" min-width="160">
              <template #default="{ row }">
                <el-input v-model="row.name" placeholder="例如：Bangumi 番组计划" />
              </template>
            </el-table-column>
            <el-table-column label="链接地址 (URL)" min-width="240">
              <template #default="{ row }">
                <el-input v-model="row.url" placeholder="例如：https://bangumi.tv" />
              </template>
            </el-table-column>
            <el-table-column label="站点简介（选填）" min-width="200">
              <template #default="{ row }">
                <el-input v-model="row.description" placeholder="例如：动漫番组记录与评价" />
              </template>
            </el-table-column>
            <el-table-column label="排序/操作" width="180" align="center">
              <template #default="{ $index }">
                <el-button-group size="small">
                  <el-button
                    :icon="Top"
                    :disabled="$index === 0"
                    title="上移"
                    @click="handleMoveLink($index, -1)"
                  />
                  <el-button
                    :icon="Bottom"
                    :disabled="$index === friendLinks.length - 1"
                    title="下移"
                    @click="handleMoveLink($index, 1)"
                  />
                  <el-button
                    type="danger"
                    :icon="Delete"
                    title="删除"
                    @click="handleDeleteLink($index)"
                  />
                </el-button-group>
              </template>
            </el-table-column>
          </el-table>
        </div>

        <!-- 官方联系方式配置 -->
        <el-divider content-position="left">官方联系方式配置（前台页脚实时联动）</el-divider>

        <el-form-item label="联系邮箱">
          <el-input
            v-model="form.site_contact_email"
            placeholder="例如：contact@Bllii.com"
          />
        </el-form-item>

        <el-form-item label="官方社群 / 交流方式">
          <el-input
            v-model="form.site_contact_group"
            placeholder="例如：官方交流群: 876543210 (TG: @Bllii)"
          />
        </el-form-item>

        <!-- 免责声明与法律条款 -->
        <el-divider content-position="left">平台免责声明与版权申明</el-divider>

        <el-form-item label="免责声明全文">
          <el-input
            v-model="form.site_disclaimer"
            type="textarea"
            :rows="5"
            placeholder="展示在网站底部的免责声明正文，声明第三方聚合属性与版权处理时效"
          />
        </el-form-item>

        <!-- 搜索引擎优化 (SEO) -->
        <el-divider content-position="left">搜索引擎优化 (SEO)</el-divider>

        <el-form-item label="SEO 页面关键词">
          <el-input
            v-model="form.site_keywords"
            placeholder="多个关键词用半角逗号分隔，如：高清动漫,番剧新番,免费在线观看"
          />
        </el-form-item>

        <el-form-item label="SEO 站点描述">
          <el-input
            v-model="form.site_description"
            type="textarea"
            :rows="3"
            placeholder="提供给各大搜索引擎蜘蛛抓取的站点描述摘要"
          />
        </el-form-item>

        <el-divider />

        <el-form-item>
          <el-button type="primary" :loading="saving" @click="handleSave">
            保存全局配置
          </el-button>
          <el-button @click="loadData">恢复设置</el-button>
        </el-form-item>
      </el-form>
    </el-card>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { getSiteConfig, saveSiteConfig } from '@/api/admin'
import { ElMessage } from 'element-plus'
import { Plus, Delete, Top, Bottom } from '@element-plus/icons-vue'

interface FriendLink {
  name: string
  url: string
  description?: string
}

const loading = ref(false)
const saving = ref(false)

const form = reactive<Record<string, string>>({
  site_name: '',
  site_subtitle: '',
  site_announcement: '',
  site_keywords: '',
  site_description: '',
  site_notice_enabled: '1',
  site_friend_links: '',
  site_contact_email: '',
  site_contact_group: '',
  site_disclaimer: ''
})

const friendLinks = ref<FriendLink[]>([])

const handleAddLink = () => {
  friendLinks.value.push({
    name: '',
    url: 'https://',
    description: ''
  })
}

const handleDeleteLink = (index: number) => {
  friendLinks.value.splice(index, 1)
}

const handleMoveLink = (index: number, direction: number) => {
  const targetIndex = index + direction
  if (targetIndex < 0 || targetIndex >= friendLinks.value.length) return
  const item = friendLinks.value.splice(index, 1)[0]
  friendLinks.value.splice(targetIndex, 0, item)
}

const loadData = async () => {
  loading.value = true
  try {
    const res = await getSiteConfig()
    if (res.code === 1 && res.data) {
      Object.assign(form, res.data)
      
      // 解析友情链接 JSON
      try {
        if (form.site_friend_links) {
          const parsed = JSON.parse(form.site_friend_links)
          if (Array.isArray(parsed)) {
            friendLinks.value = parsed
          } else {
            friendLinks.value = []
          }
        } else {
          friendLinks.value = [
            { name: 'Bangumi 番组计划', url: 'https://bangumi.tv', description: '动画与游戏分享社区' },
            { name: '萌娘百科', url: 'https://zh.moegirl.org.cn', description: '万物皆可萌的ACG百科全书' },
            { name: 'ACG 动漫社区', url: 'https://acg.rip', description: '动漫资源分享与爱好者交流' },
            { name: 'MyAnimeList', url: 'https://myanimelist.net', description: '全球知名动漫资料库' },
            { name: 'AnimeDB', url: 'https://anidb.net', description: '动漫数据库与档案' }
          ]
        }
      } catch (err) {
        console.warn('解析友情链接配置失败:', err)
        friendLinks.value = []
      }
    }
  } finally {
    loading.value = false
  }
}

const handleSave = async () => {
  saving.value = true
  try {
    // 序列化友情链接
    form.site_friend_links = JSON.stringify(
      friendLinks.value.filter(link => link.name.trim() && link.url.trim())
    )

    const res = await saveSiteConfig(form)
    if (res.code === 1) {
      ElMessage.success(res.msg || '站点配置已保存并即时生效')
      loadData()
    }
  } finally {
    saving.value = false
  }
}

onMounted(() => {
  loadData()
})
</script>

<style scoped lang="scss">
.settings-page {
  .main-card {
    border-radius: 12px;
    border: 1px solid var(--border-color);
    max-width: 960px;
    margin: 0 auto;

    .page-header {
      display: flex;
      flex-direction: column;
      gap: 4px;
      margin-bottom: 24px;

      .page-title {
        font-size: 16px;
        font-weight: 700;
        color: var(--text-primary);
      }
      .sub-desc {
        font-size: 12px;
        color: var(--text-secondary);
      }
    }

    .settings-form {
      padding: 10px 0;
    }

    .friend-links-box {
      margin-bottom: 24px;
      padding-left: 20px;
      padding-right: 20px;

      .table-actions {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 8px;

        .tip-text {
          font-size: 12px;
          color: var(--text-secondary);
        }
      }
    }
  }
}
</style>
