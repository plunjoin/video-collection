<template>
  <div class="operations-page">
  <r-card>
    <div class="toolbar"><h2>{{ operator ? '我的内容提交' : '内容审核中心' }}</h2>
      <r-select v-model="status" @change="load" style="width:160px"><r-option label="全部状态" value=""/><r-option label="待审核" value="pending"/><r-option label="已通过" value="approved"/><r-option label="已拒绝" value="rejected"/></r-select><r-button @click="load">刷新</r-button></div>
    <r-table :data="items" v-loading="loading" stripe>
      <r-table-column prop="id" label="编号" width="80"/><r-table-column label="类型" width="100"><template #default="{row}">{{ kinds[row.kind] }}</template></r-table-column>
      <r-table-column label="标题 / 内容" min-width="240"><template #default="{row}">{{ row.payload.title || row.payload.name || row.payload.content }}</template></r-table-column>
      <r-table-column prop="submitter_name" label="提交人"/><r-table-column label="状态"><template #default="{row}"><r-tag :type="row.status === 'approved' ? 'success' : row.status === 'rejected' ? 'danger' : 'warning'">{{ states[row.status] }}</r-tag></template></r-table-column>
      <r-table-column prop="note" label="审核意见"/><r-table-column label="操作" width="130"><template #default="{row}"><r-button @click="selected=row; note=''">查看详情</r-button></template></r-table-column>
    </r-table>
    <r-pagination v-model:current-page="page" :total="total" :page-size="20" layout="total, prev, pager, next" @current-change="load"/>
  </r-card>
  <r-dialog :model-value="!!selected" title="提交内容与审核" width="min(850px,95vw)" @close="selected=null">
    <template v-if="selected"><p>{{ kinds[selected.kind] }} · 原内容 ID：{{ selected.target_id || '新增' }} · 提交于 {{ selected.created_at }}</p>
      <pre class="payload">{{ JSON.stringify(selected.payload, null, 2) }}</pre><p v-if="selected.note">审核意见：{{ selected.note }}</p>
      <r-input v-if="canReview && selected.status==='pending'" v-model="note" type="textarea" maxlength="1000" placeholder="审核意见（拒绝时必填）"/>
    </template>
    <template #footer><r-button @click="selected=null">关闭</r-button>
      <template v-if="canReview && selected?.status==='pending'"><r-button type="danger" :loading="saving" @click="decide(false)">拒绝</r-button><r-button type="primary" :loading="saving" @click="decide(true)">审核通过</r-button></template>
      <r-button v-if="operator && selected?.status==='rejected'" @click="editPayload=JSON.stringify(selected.payload,null,2); resubmitVisible=true">修改后重新提交</r-button>
    </template>
  </r-dialog>
  <r-dialog v-model="resubmitVisible" title="修改提交资料" width="min(800px,95vw)"><r-input v-model="editPayload" type="textarea" :rows="18"/><template #footer><r-button :loading="saving" type="primary" @click="resubmit">重新提交审核</r-button></template></r-dialog>
  </div>
</template>
<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import request from '@/utils/request'
import { useUserStore } from '@/store/user'
import { notify }  from '@/components/radix/feedback'
const user = useUserStore()
const operator = computed(() => user.userInfo?.role === 'operator')
const canReview = computed(() => ['super_admin','admin'].includes(user.userInfo?.role || ''))
const kinds: Record<string,string> = {video:'视频',news:'资讯',post:'社区',comment:'评论'}
const states: Record<string,string> = {pending:'待审核',approved:'已通过',rejected:'已拒绝'}
const items=ref<any[]>([]), selected=ref<any>(null), status=ref('pending'), page=ref(1),total=ref(0),loading=ref(false),saving=ref(false),note=ref(''),resubmitVisible=ref(false),editPayload=ref('')
async function load(){loading.value=true;try{const r:any=await request.get('/api/admin/reviews',{params:{status:status.value,page:page.value}});items.value=r.data;total.value=r.total}finally{loading.value=false}}
async function decide(approve:boolean){if(!approve&&!note.value.trim()){notify('请输入拒绝原因', 'warning');return}saving.value=true;try{await request.post('/api/admin/reviews',{id:selected.value.id,approve,note:note.value});selected.value=null;notify('审核完成', 'success');await load()}finally{saving.value=false}}
async function resubmit(){let payload:any;try{payload=JSON.parse(editPayload.value)}catch{notify('JSON 格式错误', 'error');return}const kind=selected.value.kind; const paths:Record<string,string>={video:'/api/admin/videos/save',news:'/api/admin/news',post:'/api/admin/community/posts',comment:'/api/comments'}
 if(kind==='news'||kind==='post'){const {id,title,summary,content,cover,category,status,pinned}=payload;payload={id,title,summary,content,cover,category,status,pinned}}
 if(kind==='comment'){const {target_type,target_id,parent_id,content}=payload;payload={target_type,target_id,parent_id,content}}
 saving.value=true;try{const r:any=await request.post(paths[kind],payload);notify(r.msg, 'success');resubmitVisible.value=false;selected.value=null;status.value='pending';await load()}finally{saving.value=false}}
onMounted(load)
</script>
<style scoped lang="scss">
.toolbar {
  display: flex;
  gap: 12px;
  align-items: center;
  margin-bottom: 12px;

  h2 {
    flex: 1;
    font-size: 13px;
    font-weight: 700;
    color: var(--text-primary);
    margin: 0;
  }
}

.payload {
  background: var(--bg-color);
  padding: 12px;
  border-radius: var(--radius-sm);
  font-size: 11px;
  max-height: 50vh;
  overflow: auto;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.r-pagination {
  margin-top: 14px;
}
</style>
