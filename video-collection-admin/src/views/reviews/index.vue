<template>
  <div class="operations-page">
  <el-card>
    <div class="toolbar"><h2>{{ operator ? '我的内容提交' : '内容审核中心' }}</h2>
      <el-select v-model="status" @change="load" style="width:160px"><el-option label="全部状态" value=""/><el-option label="待审核" value="pending"/><el-option label="已通过" value="approved"/><el-option label="已拒绝" value="rejected"/></el-select><el-button @click="load">刷新</el-button></div>
    <el-table :data="items" v-loading="loading" stripe>
      <el-table-column prop="id" label="编号" width="80"/><el-table-column label="类型" width="100"><template #default="{row}">{{ kinds[row.kind] }}</template></el-table-column>
      <el-table-column label="标题 / 内容" min-width="240"><template #default="{row}">{{ row.payload.title || row.payload.name || row.payload.content }}</template></el-table-column>
      <el-table-column prop="submitter_name" label="提交人"/><el-table-column label="状态"><template #default="{row}"><el-tag :type="row.status === 'approved' ? 'success' : row.status === 'rejected' ? 'danger' : 'warning'">{{ states[row.status] }}</el-tag></template></el-table-column>
      <el-table-column prop="note" label="审核意见"/><el-table-column label="操作" width="130"><template #default="{row}"><el-button @click="selected=row; note=''">查看详情</el-button></template></el-table-column>
    </el-table>
    <el-pagination v-model:current-page="page" :total="total" :page-size="20" layout="total, prev, pager, next" @current-change="load"/>
  </el-card>
  <el-dialog :model-value="!!selected" title="提交内容与审核" width="min(850px,95vw)" @close="selected=null">
    <template v-if="selected"><p>{{ kinds[selected.kind] }} · 原内容 ID：{{ selected.target_id || '新增' }} · 提交于 {{ selected.created_at }}</p>
      <pre class="payload">{{ JSON.stringify(selected.payload, null, 2) }}</pre><p v-if="selected.note">审核意见：{{ selected.note }}</p>
      <el-input v-if="canReview && selected.status==='pending'" v-model="note" type="textarea" maxlength="1000" placeholder="审核意见（拒绝时必填）"/>
    </template>
    <template #footer><el-button @click="selected=null">关闭</el-button>
      <template v-if="canReview && selected?.status==='pending'"><el-button type="danger" :loading="saving" @click="decide(false)">拒绝</el-button><el-button type="primary" :loading="saving" @click="decide(true)">审核通过</el-button></template>
      <el-button v-if="operator && selected?.status==='rejected'" @click="editPayload=JSON.stringify(selected.payload,null,2); resubmitVisible=true">修改后重新提交</el-button>
    </template>
  </el-dialog>
  <el-dialog v-model="resubmitVisible" title="修改提交资料" width="min(800px,95vw)"><el-input v-model="editPayload" type="textarea" :rows="18"/><template #footer><el-button :loading="saving" type="primary" @click="resubmit">重新提交审核</el-button></template></el-dialog>
  </div>
</template>
<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import request from '@/utils/request'
import { useUserStore } from '@/store/user'
import { ElMessage } from 'element-plus'
const user = useUserStore()
const operator = computed(() => user.userInfo?.role === 'operator')
const canReview = computed(() => ['super_admin','admin'].includes(user.userInfo?.role || ''))
const kinds: Record<string,string> = {video:'视频',news:'资讯',post:'社区',comment:'评论'}
const states: Record<string,string> = {pending:'待审核',approved:'已通过',rejected:'已拒绝'}
const items=ref<any[]>([]), selected=ref<any>(null), status=ref('pending'), page=ref(1),total=ref(0),loading=ref(false),saving=ref(false),note=ref(''),resubmitVisible=ref(false),editPayload=ref('')
async function load(){loading.value=true;try{const r:any=await request.get('/api/admin/reviews',{params:{status:status.value,page:page.value}});items.value=r.data;total.value=r.total}finally{loading.value=false}}
async function decide(approve:boolean){if(!approve&&!note.value.trim()){ElMessage.warning('请输入拒绝原因');return}saving.value=true;try{await request.post('/api/admin/reviews',{id:selected.value.id,approve,note:note.value});selected.value=null;ElMessage.success('审核完成');await load()}finally{saving.value=false}}
async function resubmit(){let payload:any;try{payload=JSON.parse(editPayload.value)}catch{ElMessage.error('JSON 格式错误');return}const kind=selected.value.kind; const paths:Record<string,string>={video:'/api/admin/videos/save',news:'/api/admin/news',post:'/api/admin/community/posts',comment:'/api/comments'}
 if(kind==='news'||kind==='post'){const {id,title,summary,content,cover,category,status,pinned}=payload;payload={id,title,summary,content,cover,category,status,pinned}}
 if(kind==='comment'){const {target_type,target_id,parent_id,content}=payload;payload={target_type,target_id,parent_id,content}}
 saving.value=true;try{const r:any=await request.post(paths[kind],payload);ElMessage.success(r.msg);resubmitVisible.value=false;selected.value=null;status.value='pending';await load()}finally{saving.value=false}}
onMounted(load)
</script>
<style scoped>.toolbar{display:flex;gap:16px;align-items:center;margin-bottom:20px}.toolbar h2{flex:1}.payload{background:var(--bg-color);padding:20px;max-height:50vh;overflow:auto;white-space:pre-wrap;overflow-wrap:anywhere}.el-pagination{margin-top:20px}</style>
