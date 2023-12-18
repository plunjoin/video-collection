<template>
  <div class="login-wrapper">
    <div class="login-container">
      <!-- 头部装饰 -->
      <div class="login-header">
        <div class="logo-circle">
          <el-icon :size="28" color="#fff"><VideoCameraFilled /></el-icon>
        </div>
        <h2 class="title">聚合采集管理控制台</h2>
        <p class="subtitle">可配置多源采集 • 智能清洗聚合 • 纯后端 API 架构</p>
      </div>

      <!-- 登录表单 -->
      <el-form
        ref="loginFormRef"
        :model="form"
        :rules="rules"
        class="login-form"
        @keyup.enter="handleLogin"
      >
        <el-form-item prop="username">
          <el-input
            v-model="form.username"
            placeholder="请输入管理员用户名"
            size="large"
            :prefix-icon="User"
            clearable
          />
        </el-form-item>

        <el-form-item prop="password">
          <el-input
            v-model="form.password"
            type="password"
            placeholder="请输入管理员密码"
            size="large"
            :prefix-icon="Lock"
            show-password
          />
        </el-form-item>

        <div v-if="isDevelopment" class="quick-fill">
          <span class="hint-text">默认账号：<code>admin</code> / <code>admin123</code></span>
          <el-button link type="primary" size="small" @click="quickFill">一键填入</el-button>
        </div>

        <el-button
          type="primary"
          size="large"
          class="submit-btn"
          :loading="loading"
          @click="handleLogin"
        >
          {{ loading ? '登录验证中...' : '立即登录控制台' }}
        </el-button>
      </el-form>

      <div class="login-footer">
        <span>© 2026 视频智能采集聚合平台 • 现代管理架构</span>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { reactive, ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useUserStore } from '@/store/user'
import { ElMessage, type FormInstance, type FormRules } from 'element-plus'
import { VideoCameraFilled, User, Lock } from '@element-plus/icons-vue'

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

const handleLogin = async () => {
  if (!loginFormRef.value) return
  await loginFormRef.value.validate(async (valid) => {
    if (!valid) return
    loading.value = true
    try {
      await userStore.login(form)
      ElMessage.success('欢迎回来，登录成功！')
      const redirect = (route.query.redirect as string) || '/dashboard'
      await router.push(redirect)
    } catch (err: any) {
      ElMessage.error(err.message || '登录验证失败')
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
  background: radial-gradient(ellipse at top, #1e1b4b 0%, #090d16 100%);
  position: relative;
  overflow: hidden;

  &::before {
    content: '';
    position: absolute;
    width: 600px;
    height: 600px;
    background: radial-gradient(circle, rgba(99, 102, 241, 0.15) 0%, transparent 70%);
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    pointer-events: none;
  }

  .login-container {
    width: 440px;
    padding: 40px 36px;
    background: rgba(17, 24, 39, 0.85);
    border: 1px solid rgba(255, 255, 255, 0.08);
    backdrop-filter: blur(20px);
    border-radius: 24px;
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5), 0 0 40px rgba(99, 102, 241, 0.1);
    z-index: 1;

    .login-header {
      text-align: center;
      margin-bottom: 30px;

      .logo-circle {
        width: 58px;
        height: 58px;
        margin: 0 auto 16px;
        border-radius: 18px;
        background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%);
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow: 0 8px 20px rgba(99, 102, 241, 0.4);
      }

      .title {
        margin: 0;
        font-size: 20px;
        font-weight: 700;
        color: #f8fafc;
        letter-spacing: 0.5px;
      }

      .subtitle {
        margin: 8px 0 0;
        font-size: 12px;
        color: #94a3b8;
      }
    }

    .login-form {
      :deep(.el-input__wrapper) {
        border-radius: 12px;
        background-color: #1e293b;
        box-shadow: 0 0 0 1px #334155 inset;
        padding: 4px 14px;
        &:focus-within {
          box-shadow: 0 0 0 1px #6366f1 inset !important;
        }
      }

      .quick-fill {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 20px;

        .hint-text {
          font-size: 12px;
          color: #64748b;
          code {
            color: #818cf8;
            background: rgba(99, 102, 241, 0.12);
            padding: 2px 6px;
            border-radius: 4px;
          }
        }
      }

      .submit-btn {
        width: 100%;
        border-radius: 12px;
        height: 46px;
        font-size: 15px;
        font-weight: 600;
        background: linear-gradient(135deg, #6366f1 0%, #4f46e5 100%);
        border: none;
        box-shadow: 0 4px 14px rgba(99, 102, 241, 0.4);
        transition: all 0.2s;

        &:hover {
          opacity: 0.92;
          transform: translateY(-1px);
        }
      }
    }

    .login-footer {
      text-align: center;
      margin-top: 24px;
      font-size: 11px;
      color: #475569;
    }
  }
}
</style>
