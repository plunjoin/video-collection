<template>
  <div class="operations-page">
  <el-card><div class="toolbar"><h2>消息通知 <el-tag>{{ unread }} 条未读</el-tag></h2><el-button @click="load">刷新</el-button><el-button :disabled="!unread" @click="readAll">全部已读</el-button><el-button v-if="canSend" type="primary" @click="sendVisible=true">发送站内通知</el-button></div>
    <el-empty v-if="!items.length" description="暂时没有通知"/>
    <article v-for="n in items" :key="n.id" :class="{unread:!n.is_read}" @click="open(n)"><strong>{{ n.title }}</strong><small>{{ new Date(n.created_at).toLocaleString() }}</small><p>{{ n.content }}</p><el-tag size="small">{{ n.is_read?'已读':'未读' }}</el-tag><el-button v-if="['review','movie_request','points'].includes(n.target_type)" link type="primary">查看详情 →</el-button></article>
    <el-pagination v-model:current-page="page" :total="total" :page-size="20" layout="total,prev,pager,next" @current-change="load"/>
  </el-card>
  <el-dialog v-model="sendVisible" title="发送站内通知"><el-form label-width="100px"><el-form-item label="标题"><el-input v-model="title" maxlength="200"/></el-form-item><el-form-item label="正文"><el-input v-model="body" type="textarea" :rows="5" maxlength="10000"/></el-form-item><el-form-item label="全部用户"><el-switch v-model="broadcast"/></el-form-item><el-form-item v-if="!broadcast" label="用户 ID"><el-input v-model="recipients" placeholder="多个用户 ID 用逗号分隔"/></el-form-item></el-form><template #footer><el-button type="primary" :loading="busy" @click="send">发送通知</el-button></template></el-dialog>
  </div>
</template>
<script setup lang="ts">
import {ref,computed,onMounted} from 'vue'
import {useRouter} from 'vue-router'
import {useUserStore} from '@/store/user'
import request from '@/utils/request'
import {ElMessage,ElMessageBox} from 'element-plus'
const user=useUserStore(),router=useRouter(),canSend=computed(()=>['super_admin','admin'].includes(user.userInfo?.role || ''))
const items=ref<any[]>([]),unread=ref(0),page=ref(1),total=ref(0),sendVisible=ref(false),title=ref(''),body=ref(''),broadcast=ref(false),recipients=ref(''),busy=ref(false)
async function load(){const r:any=await request.get('/api/user/notifications',{params:{page:page.value}});items.value=r.data;unread.value=r.unread_count;total.value=r.total;window.dispatchEvent(new Event('inbox-updated'))}
async function readAll(){await request.post('/api/user/notifications/read',{all:true});await load()}
async function open(n:any){if(!n.is_read){await request.post('/api/user/notifications/read',{ids:[n.id]});await load()}if(n.target_type==='review')router.push('/reviews');if(n.target_type==='movie_request')router.push('/growth');if(n.target_type==='points')window.open((import.meta.env.VITE_PORTAL_URL || '/')+'points','_blank')}
async function send(){if(broadcast.value)await ElMessageBox.confirm('向所有正常用户发送此通知？','发送确认');busy.value=true;try{await request.post('/api/admin/notifications',{title:title.value,content:body.value,broadcast:broadcast.value,user_ids:broadcast.value?[]:recipients.value.split(/[,，\s]+/).filter(Boolean).map(Number)});sendVisible.value=false;title.value='';body.value='';ElMessage.success('通知已发送');await load()}finally{busy.value=false}}
onMounted(load)
</script>
<style scoped>.toolbar{display:flex;align-items:center;gap:12px}.toolbar h2{flex:1}article{padding:20px;margin:12px 0;border:1px solid var(--border-color);border-radius:10px;cursor:pointer}article.unread{border-left:4px solid #6366f1}small{float:right;opacity:.65}p{white-space:pre-wrap;overflow-wrap:anywhere}</style>
