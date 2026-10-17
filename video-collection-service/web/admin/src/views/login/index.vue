<template>
  <div class="login-wrapper">
    <div class="login-card">
      <!-- 品牌头 -->
      <div class="login-header">
        <span class="logo-mark" v-html="sparkleSvg" />
        <h1 class="title">视频采集管理</h1>
        <p class="subtitle">可配置多源采集 • 智能清洗聚合 • 统一服务架构</p>
      </div>

      <!-- 登录表单 -->
      <r-form
        ref="loginFormRef"
        :model="form"
        :rules="rules"
        class="login-form"
        size="large"
        @keyup.enter="handleLogin"
      >
        <r-form-item prop="username">
          <r-input
            v-model="form.username"
            placeholder="管理员用户名"
            :prefix-icon="User"
            clearable
          />
        </r-form-item>

        <r-form-item prop="password">
          <r-input
            v-model="form.password"
            type="password"
            placeholder="管理员密码"
            :prefix-icon="Lock"
            show-password
          />
        </r-form-item>

        <div v-if="isDevelopment" class="quick-fill">
          <span class="hint-text">默认账号 <code>admin</code> / <code>admin123</code></span>
          <r-button link type="primary" size="small" @click="quickFill">一键填入</r-button>
        </div>

        <r-button
          type="primary"
          class="submit-btn"
          :loading="loading"
          round
          @click="handleLogin"
        >
          {{ loading ? '登录验证中…' : '登录管理后台' }}
        </r-button>
      </r-form>

      <div class="login-footer">video-collection-service · Go 统一服务</div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { reactive, ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useUserStore } from '@/store/user'
import { notify } from '@/components/radix/feedback'
import type { FormInstance, FormRules }  from '@/components/radix/types'
import { User, Lock } from '@/components/radix/icons'

const router = useRouter()
const route = useRoute()
const userStore = useUserStore()

const loginFormRef = ref<FormInstance>()
const loading = ref(false)
const isDevelopment = import.meta.env.DEV

const form = reactive({
  username: 'admin',
  password: ''
})

const rules = reactive<FormRules>({
  username: [{ required: true, message: '请输入管理员账号', trigger: 'blur' }],
  password: [{ required: true, message: '请输入管理员密码', trigger: 'blur' }]
})

const quickFill = () => {
  form.username = 'admin'
  form.password = 'admin123'
}

const sparkleSvg =
  "<svg viewBox='0 0 24 24' width='44' height='44' xmlns='http://www.w3.org/2000/svg'><defs><linearGradient id='lg' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='#4285f4'/><stop offset='.55' stop-color='#9b72cb'/><stop offset='1' stop-color='#d96570'/></linearGradient></defs><path fill='url(#lg)' d='M12 1.8c.6 4.9 3.9 8.3 8.7 9.1C15.9 11.7 12.6 15.1 12 20c-.6-4.9-3.9-8.3-8.7-9.1C8.1 10.1 11.4 6.7 12 1.8z'/></svg>"

const handleLogin = async () => {
  if (!loginFormRef.value) return
  await loginFormRef.value.validate(async (valid) => {
    if (!valid) return
    loading.value = true
    try {
      await userStore.login(form)
      notify('欢迎回来，登录成功', 'success')
      const redirect = (route.query.redirect as string) || '/dashboard'
      await router.push(redirect)
    } catch (err: any) {
      notify(err.message || '登录验证失败', 'error')
    } finally {
      loading.value = false
    }
  })
}
</script>

<style scoped lang="scss">
.login-wrapper {
  width: 100vw;
  height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background:
    radial-gradient(ellipse 80% 60% at 50% -10%, rgba(66, 133, 244, 0.10), transparent 60%),
    radial-gradient(ellipse 60% 50% at 80% 110%, rgba(217, 101, 112, 0.08), transparent 60%),
    var(--bg-color);
  padding: 24px;

  .login-card {
    width: 100%;
    max-width: 400px;
    padding: 44px 40px 32px;
    background: var(--glass-panel-strong); // 与浮层/大面板同族玻璃材质
    border: 1px solid var(--glass-border);
    border-radius: var(--radius-xl);
    box-shadow: var(--shadow-pop), var(--glass-highlight);
    backdrop-filter: var(--glass-blur-strong);
    -webkit-backdrop-filter: var(--glass-blur-strong);

    .login-header {
      text-align: center;
      margin-bottom: 32px;

      .logo-mark {
        display: inline-flex;
        margin-bottom: 14px;
      }
      .title {
        margin: 0;
        font-size: 22px;
        font-weight: 500;
        color: var(--text-primary);
        letter-spacing: 0.5px;
      }
      .subtitle {
        margin: 8px 0 0;
        font-size: 12.5px;
        color: var(--text-secondary);
      }
    }

    .login-form {
      :deep(.r-input__wrapper) {
        padding: 8px 14px;
        border-radius: 999px;
        background: var(--surface);
        box-shadow: 0 0 0 1px var(--border-strong) inset;
        &:hover { box-shadow: 0 0 0 1px var(--text-secondary) inset; }
        &.is-focus { box-shadow: 0 0 0 1px var(--brand) inset !important; }
      }

      .quick-fill {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 18px;
        .hint-text {
          font-size: 12px;
          color: var(--text-secondary);
          code {
            color: var(--text-primary);
            background: var(--surface-hover);
            padding: 2px 6px;
            border-radius: 6px;
          }
        }
      }

      .submit-btn {
        width: 100%;
        height: 46px;
        font-size: 15px;
        font-weight: 500;
        background: var(--brand);
        border: none;
        transition: all 0.18s ease;

        &:hover {
          background: var(--brand-hover);
          transform: translateY(-1px);
        }
      }
    }

    .login-footer {
      text-align: center;
      margin-top: 26px;
      font-size: 11px;
      color: var(--text-secondary);
      letter-spacing: 0.3px;
    }
  }
}
</style>
