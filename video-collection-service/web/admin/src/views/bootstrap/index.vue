<template>
  <div class="bootstrap-page">
    <r-card shadow="never" class="table-card">
      <div class="table-header">
        <div class="header-left">
          <span class="page-title">基础配置</span>
          <span class="sub-desc">数据库 / Redis / 初始管理员等启动引导信息，持久化在 SQLite 中</span>
        </div>
        <div class="header-right">
          <r-button @click="loadConfig" :loading="loading">
            <r-icon><RefreshRight /></r-icon>刷新
          </r-button>
          <r-button type="primary" :loading="saving" @click="handleSave">
            <r-icon><Check /></r-icon>保存配置
          </r-button>
        </div>
      </div>

      <r-alert
        type="info"
        :closable="false"
        show-icon
        class="tip-alert"
        title="SQLite 是基础配置的存储位置，不再是数据库兜底"
      >
        配置写入
        <span class="mono-text">{{ info.path || 'data/collection.db' }}</span>
        的 bootstrap_config 表；PostgreSQL 连接失败时服务将直接报错退出，不会再静默降级到 SQLite 写数据。
        数据库与 Redis 连接信息修改后需重启服务生效；初始管理员仅在数据库无用户时首次初始化时生效。
      </r-alert>
    </r-card>

    <!-- 数据库连接 -->
    <r-card shadow="never" class="table-card">
      <div class="card-title">数据库连接（PostgreSQL）</div>
      <r-form label-width="120px" class="config-form">
        <r-form-item label="驱动">
          <r-select v-model="form.db_driver" style="width: 240px" @change="handleDriverChange">
            <r-option label="postgres（推荐）" value="postgres" />
            <r-option label="sqlite（单文件模式）" value="sqlite" />
          </r-select>
          <r-tag v-if="sourceTag('db.driver')" size="small" type="info" effect="plain" class="src-tag">
            {{ sourceTag('db.driver') }}
          </r-tag>
        </r-form-item>

        <template v-if="form.db_driver === 'sqlite'">
          <r-form-item label="数据文件路径">
            <r-input v-model="form.db_dsn" disabled placeholder="使用 SQLITE_PATH 环境变量或默认 data/collection.db" />
            <span class="form-tip">SQLite 单文件模式：业务数据与基础配置同库（默认 data/collection.db）</span>
          </r-form-item>
        </template>

        <template v-else>
          <r-form-item label="完整连接串">
            <r-input v-model="form.db_dsn" placeholder="postgres://user:pass@host:5432/videodb?sslmode=disable（留空则使用下方分项配置）" />
            <r-tag v-if="sourceTag('db.dsn')" size="small" type="info" effect="plain" class="src-tag">
              {{ sourceTag('db.dsn') }}
            </r-tag>
          </r-form-item>
          <r-form-item label="主机">
            <r-input v-model="form.db_host" placeholder="postgres 或数据库服务器 IP" />
          </r-form-item>
          <r-row :gutter="16">
            <r-col :span="8">
              <r-form-item label="端口">
                <r-input v-model="form.db_port" placeholder="5432" />
              </r-form-item>
            </r-col>
            <r-col :span="8">
              <r-form-item label="数据库名">
                <r-input v-model="form.db_name" placeholder="videodb" />
              </r-form-item>
            </r-col>
            <r-col :span="8">
              <r-form-item label="SSL 模式">
                <r-input v-model="form.db_sslmode" placeholder="disable" />
              </r-form-item>
            </r-col>
          </r-row>
          <r-form-item label="用户名">
            <r-input v-model="form.db_user" placeholder="postgres" />
          </r-form-item>
          <r-form-item label="密码">
            <r-input v-model="form.db_password" type="password" placeholder="********（不变更请保持原样）" />
          </r-form-item>
          <r-form-item label=" ">
            <r-button size="small" :loading="testing" @click="handleTestDB">
              <r-icon><Connection /></r-icon>测试连通性
            </r-button>
            <span v-if="testResult" class="form-tip" :class="testResult.ok ? 'ok' : 'fail'">{{ testResult.message }}</span>
          </r-form-item>
        </template>
      </r-form>
    </r-card>

    <!-- Redis -->
    <r-card shadow="never" class="table-card">
      <div class="card-title">Redis（可选，分布式会话与公开读缓存）</div>
      <r-form label-width="120px" class="config-form">
        <r-form-item label="地址">
          <r-input v-model="form.redis_addr" placeholder="redis:6379（留空则不启用 Redis）" />
          <r-tag v-if="sourceTag('redis.addr')" size="small" type="info" effect="plain" class="src-tag">
            {{ sourceTag('redis.addr') }}
          </r-tag>
        </r-form-item>
        <r-row :gutter="16">
          <r-col :span="8">
            <r-form-item label="密码">
              <r-input v-model="form.redis_password" type="password" placeholder="********（无密码可留空）" />
            </r-form-item>
          </r-col>
          <r-col :span="8">
            <r-form-item label="库索引">
              <r-input v-model="form.redis_db" placeholder="0" />
            </r-form-item>
          </r-col>
          <r-col :span="8">
            <r-form-item label="键前缀">
              <r-input v-model="form.redis_prefix" placeholder="vc" />
            </r-form-item>
          </r-col>
        </r-row>
      </r-form>
    </r-card>

    <!-- 初始管理员 -->
    <r-card shadow="never" class="table-card">
      <div class="card-title">初始管理员（仅首次初始化数据库时生效）</div>
      <r-form label-width="120px" class="config-form">
        <r-form-item label="用户名">
          <r-input v-model="form.admin_username" placeholder="admin" style="width: 240px" />
          <r-tag v-if="sourceTag('admin.username')" size="small" type="info" effect="plain" class="src-tag">
            {{ sourceTag('admin.username') }}
          </r-tag>
        </r-form-item>
        <r-form-item label="密码">
          <r-input v-model="form.admin_password" type="password" placeholder="留空则启动时随机生成并写回此处" style="width: 320px" />
        </r-form-item>
      </r-form>
    </r-card>

    <!-- Webhook 加密主密钥 -->
    <r-card shadow="never" class="table-card">
      <div class="card-title">Webhook 密钥加密主密钥（可选）</div>
      <r-form label-width="120px" class="config-form">
        <r-form-item label="主密钥">
          <r-input v-model="form.webhook_encryption_key" placeholder="留空则由管理员初始密码派生" />
          <span class="form-tip">变更后所有既有 Webhook 密钥需在后台重新轮换才能继续验签</span>
        </r-form-item>
      </r-form>
    </r-card>

    <div class="save-bar">
      <r-button type="primary" size="large" :loading="saving" @click="handleSave">保存配置</r-button>
      <span class="form-tip">保存后写入基础配置 SQLite；数据库 / Redis 连接信息需重启服务生效</span>
    </div>
  </div>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { getBootstrapConfig, saveBootstrapConfig, testBootstrapDB } from '@/api/bootstrap'
import { notify } from '@/components/radix/feedback'
import { Check, Connection, RefreshRight } from '@/components/radix/icons'

const loading = ref(false)
const saving = ref(false)
const testing = ref(false)
const info = reactive<{ path: string; config: Record<string, string>; sources: Record<string, string> }>({
  path: '',
  config: {},
  sources: {}
})
const testResult = ref<{ ok: boolean; message: string } | null>(null)

const emptyForm = () => ({
  db_driver: 'postgres',
  db_dsn: '',
  db_host: '',
  db_port: '',
  db_user: '',
  db_password: '',
  db_name: '',
  db_sslmode: '',
  redis_addr: '',
  redis_password: '',
  redis_db: '',
  redis_prefix: '',
  admin_username: '',
  admin_password: '',
  webhook_encryption_key: ''
})
const form = reactive(emptyForm())

function sourceTag(key: string) {
  const source = info.sources[key]
  if (!source) return ''
  return source.startsWith('env:') ? `环境变量 ${source.slice(4)} 覆盖` : '基础配置'
}

async function loadConfig() {
  loading.value = true
  try {
    const res = await getBootstrapConfig()
    info.path = res.data?.path || ''
    info.config = res.data?.config || {}
    info.sources = res.data?.sources || {}
    const c = info.config
    Object.assign(form, {
      db_driver: c['db.driver'] || 'postgres',
      db_dsn: c['db.dsn'] || '',
      db_host: c['db.host'] || '',
      db_port: c['db.port'] || '',
      db_user: c['db.user'] || '',
      db_password: c['db.password'] || '',
      db_name: c['db.name'] || '',
      db_sslmode: c['db.sslmode'] || '',
      redis_addr: c['redis.addr'] || '',
      redis_password: c['redis.password'] || '',
      redis_db: c['redis.db'] || '',
      redis_prefix: c['redis.prefix'] || '',
      admin_username: c['admin.username'] || '',
      admin_password: c['admin.password'] || '',
      webhook_encryption_key: c['webhook.encryption_key'] || ''
    })
  } catch {
    notify('读取基础配置失败', 'error')
  } finally {
    loading.value = false
  }
}

function handleDriverChange() {
  testResult.value = null
}

async function handleTestDB() {
  testing.value = true
  testResult.value = null
  try {
    const res = await testBootstrapDB({
      db_driver: form.db_driver,
      db_dsn: form.db_dsn,
      db_host: form.db_host,
      db_port: form.db_port,
      db_user: form.db_user,
      db_password: form.db_password,
      db_name: form.db_name,
      db_sslmode: form.db_sslmode
    })
    testResult.value = { ok: !!res.data?.ok, message: res.data?.message || '' }
  } catch (e: any) {
    testResult.value = { ok: false, message: e?.message || '测试失败' }
  } finally {
    testing.value = false
  }
}

async function handleSave() {
  saving.value = true
  try {
    const res = await saveBootstrapConfig({ ...form })
    notify(res.data?.note || '已保存，重启后生效', 'success')
    await loadConfig()
  } catch {
    notify('保存失败', 'error')
  } finally {
    saving.value = false
  }
}

onMounted(loadConfig)
</script>

<style scoped lang="scss">
.bootstrap-page {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.card-title {
  font-size: 15px;
  font-weight: 600;
  margin-bottom: 12px;
}

.config-form {
  max-width: 860px;
}

.form-tip {
  margin-left: 12px;
  font-size: 12px;
  color: var(--text-secondary, #909399);

  &.ok {
    color: #52c41a;
  }

  &.fail {
    color: #f5222d;
  }
}

.src-tag {
  margin-left: 10px;
}

.mono-text {
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  padding: 0 2px;
}

.tip-alert {
  margin-top: 12px;
  line-height: 1.7;
}

.save-bar {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 4px 0 24px;
}
</style>
