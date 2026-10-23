<template>
  <div class="operations-page">
  <r-card><div class="toolbar"><h2>消息通知 <r-tag>{{ unread }} 条未读</r-tag></h2><r-button @click="load">刷新</r-button><r-button :disabled="!unread" @click="readAll">全部已读</r-button><r-button v-if="canSend" type="primary" @click="sendVisible=true">发送站内通知</r-button></div>
    <r-empty v-if="!items.length" description="暂时没有通知"/>
    <article v-for="n in items" :key="n.id" :class="{unread:!n.is_read}" @click="open(n)"><strong>{{ n.title }}</strong><small>{{ new Date(n.created_at).toLocaleString() }}</small><p>{{ n.content }}</p><r-tag size="small">{{ n.is_read?'已读':'未读' }}</r-tag><r-button v-if="['review','movie_request','points'].includes(n.target_type)" link type="primary">查看详情 →</r-button></article>
    <r-pagination v-model:current-page="page" v-model:page-size="pageSize" :page-sizes="[10, 20, 50, 100]" :total="total" @current-change="load" @size-change="load"/>
  </r-card>
  <r-dialog v-model="sendVisible" title="发送站内通知"><r-form label-width="100px"><r-form-item label="标题"><r-input v-model="title" maxlength="200"/></r-form-item><r-form-item label="正文"><r-input v-model="body" type="textarea" :rows="5" maxlength="10000"/></r-form-item><r-form-item label="全部用户"><r-switch v-model="broadcast"/></r-form-item><r-form-item v-if="!broadcast" label="用户 ID"><r-input v-model="recipients" placeholder="多个用户 ID 用逗号分隔"/></r-form-item></r-form><template #footer><r-button type="primary" :loading="busy" @click="send">发送通知</r-button></template></r-dialog>
  </div>
</template>
<script setup lang="ts">
import {ref,computed,onMounted} from 'vue'
import {useRouter} from 'vue-router'
import {useUserStore} from '@/store/user'
import request from '@/utils/request'
import { notify, confirmAction }  from '@/components/radix/feedback'
const user=useUserStore(),router=useRouter(),canSend=computed(()=>['super_admin','admin'].includes(user.userInfo?.role || ''))
const items=ref<any[]>([]),unread=ref(0),page=ref(1),pageSize=ref(20),total=ref(0),sendVisible=ref(false),title=ref(''),body=ref(''),broadcast=ref(false),recipients=ref(''),busy=ref(false)
async function load(){const r:any=await request.get('/api/user/notifications',{params:{page:page.value,page_size:pageSize.value}});items.value=r.data;unread.value=r.unread_count;total.value=r.total;window.dispatchEvent(new Event('inbox-updated'))}
async function readAll(){await request.post('/api/user/notifications/read',{all:true});await load()}
async function open(n:any){if(!n.is_read){await request.post('/api/user/notifications/read',{ids:[n.id]});await load()}if(n.target_type==='review')router.push('/reviews');if(n.target_type==='movie_request')router.push('/growth');if(n.target_type==='points')window.open((import.meta.env.VITE_PORTAL_URL || '/')+'points','_blank')}
async function send(){if(broadcast.value)await confirmAction('向所有正常用户发送此通知？','发送确认');busy.value=true;try{await request.post('/api/admin/notifications',{title:title.value,content:body.value,broadcast:broadcast.value,user_ids:broadcast.value?[]:recipients.value.split(/[,，\s]+/).filter(Boolean).map(Number)});sendVisible.value=false;title.value='';body.value='';notify('通知已发送', 'success');await load()}finally{busy.value=false}}
onMounted(load)
</script>
<style scoped lang="scss">
.toolbar {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 12px;

  h2 {
    flex: 1;
    font-size: 13px;
    font-weight: 700;
    color: var(--text-primary);
    margin: 0;
    display: flex;
    align-items: center;
    gap: 8px;
  }
}

article {
  padding: 10px 14px;
  margin: 8px 0;
  border: 1px solid var(--border-color);
  border-radius: var(--radius-sm);
  background: rgba(255, 255, 255, 0.4);
  cursor: pointer;
  transition: background 0.15s ease, border-color 0.15s ease;

  &:hover {
    background: var(--nav-bg-subtle);
  }

  &.unread {
    border-left: 3px solid var(--brand);
    background: var(--nav-bg-subtle);
  }

  strong {
    font-size: 11.5px;
    font-weight: 600;
    color: var(--text-primary);
  }

  small {
    float: right;
    font-size: 10px;
    color: var(--text-secondary);
    opacity: 0.8;
  }

  p {
    margin: 6px 0 8px;
    font-size: 11px;
    color: var(--text-regular);
    line-height: 1.5;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
}

:global(html.dark) article {
  background: rgba(255, 255, 255, 0.03);

  &:hover {
    background: rgba(126, 148, 255, 0.08);
  }

  &.unread {
    background: rgba(126, 148, 255, 0.08);
  }
}
</style>
