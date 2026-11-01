<template>
  <r-dialog v-model="visible" title="修改密码" width="440px" @close="reset">
    <r-form ref="formRef" :model="form" :rules="rules" label-width="96px">
      <r-form-item label="当前密码" prop="old_password">
        <r-input
          v-model="form.old_password"
          type="password"
          show-password
          autocomplete="current-password"
          placeholder="请输入当前登录密码"
        />
      </r-form-item>
      <r-form-item label="新密码" prop="new_password">
        <r-input
          v-model="form.new_password"
          type="password"
          show-password
          autocomplete="new-password"
          placeholder="至少 6 位，不能与原密码相同"
        />
      </r-form-item>
      <r-form-item label="确认新密码" prop="confirm">
        <r-input
          v-model="form.confirm"
          type="password"
          show-password
          autocomplete="new-password"
          placeholder="再次输入新密码"
        />
      </r-form-item>
    </r-form>
    <p class="pwd-hint">修改成功后，其他已登录设备会被自动下线，当前设备保持登录。</p>
    <template #footer>
      <r-button @click="visible = false">取消</r-button>
      <r-button type="primary" :loading="submitting" @click="submit">确认修改</r-button>
    </template>
  </r-dialog>
</template>

<script setup lang="ts">
import { computed, reactive, ref } from 'vue'
import { changePassword } from '@/api/auth'
import { notify } from '@/components/radix/feedback'
import type { FormInstance, FormRules } from '@/components/radix/types'

const props = defineProps<{ modelValue: boolean }>()
const emit = defineEmits<{ (e: 'update:modelValue', value: boolean): void }>()

const visible = computed({
  get: () => props.modelValue,
  set: (value: boolean) => emit('update:modelValue', value)
})

const formRef = ref<FormInstance>()
const submitting = ref(false)
const form = reactive({
  old_password: '',
  new_password: '',
  confirm: ''
})

const rules: FormRules = {
  old_password: [{ required: true, message: '请输入当前密码', trigger: 'blur' }],
  new_password: [
    { required: true, message: '请输入新密码', trigger: 'blur' },
    { min: 6, message: '新密码不能少于 6 位', trigger: 'blur' },
    {
      validator: (_rule, value) =>
        value !== form.old_password || '新密码不能与当前密码相同',
      trigger: 'blur'
    }
  ],
  confirm: [
    { required: true, message: '请再次输入新密码', trigger: 'blur' },
    {
      validator: (_rule, value) => value === form.new_password || '两次输入的新密码不一致',
      trigger: 'blur'
    }
  ]
}

function reset() {
  form.old_password = ''
  form.new_password = ''
  form.confirm = ''
  formRef.value?.resetFields()
}

async function submit() {
  if (submitting.value) return
  const valid = await formRef.value?.validate()
  if (!valid) return
  submitting.value = true
  try {
    const res: any = await changePassword({
      old_password: form.old_password.trim(),
      new_password: form.new_password.trim()
    })
    const revoked = res?.revoked_sessions ?? res?.data?.revoked_sessions ?? 0
    notify(revoked > 0 ? `密码已更新，${revoked} 台其他设备已下线` : '密码已更新', 'success')
    visible.value = false
  } catch {
    // 请求拦截器已统一提示错误原因
  } finally {
    submitting.value = false
  }
}
</script>

<style scoped>
.pwd-hint {
  margin: 4px 0 0;
  color: var(--text-secondary);
  font-size: 12px;
  line-height: 1.6;
}
</style>
