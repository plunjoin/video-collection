<template>
  <div class="operations-page">
  <el-tabs v-model="tab" type="border-card">
    <el-tab-pane label="日活与积分" name="metrics">
      <div class="metrics"><el-statistic title="今日登录用户（DAU）" :value="today?.dau || 0"/><el-statistic title="今日签到" :value="today?.checkins || 0"/><el-statistic title="今日发放 / 退款积分" :value="today?.earned || 0"/><el-statistic title="今日消费积分" :value="today?.spent || 0"/></div>
      <p>按北京时间统计登录用户，每个账号每天计一次。最近30天；积分流水包含活动奖励、兑换和求片退款。</p>
      <el-table :data="days"><el-table-column prop="day" label="日期"/><el-table-column prop="dau" label="日活"/><el-table-column prop="checkins" label="签到"/><el-table-column prop="earned" label="发放 / 退款"/><el-table-column prop="spent" label="消费"/></el-table>
    </el-tab-pane>
    <el-tab-pane label="积分规则" name="rules"><el-form label-width="150px" :disabled="!canManage" style="max-width:580px">
      <el-form-item v-for="(label,key) in ruleLabels" :key="key" :label="label"><el-input-number v-model="rules[key]" :min="key === 'request_cost' ? 1 : 0" :max="key === 'request_cost' ? 10000 : key === 'streak_cap' ? 500 : key === 'streak_step' ? 20 : 100"/></el-form-item>
      <p>签到奖励 = 基础奖励 + (连续天数 − 1) × 增量，上限为奖励封顶；修改仅影响之后的奖励与消费。</p>
      <el-button type="primary" :loading="busy" @click="saveRules">保存规则</el-button>
    </el-form></el-tab-pane>
    <el-tab-pane label="积分求片" name="requests"><el-button @click="loadRequests">刷新</el-button>
      <el-table :data="requests"><el-table-column prop="id" label="ID" width="70"/><el-table-column prop="username" label="用户"/><el-table-column prop="title" label="片名"/><el-table-column prop="details" label="说明"/><el-table-column prop="cost" label="积分" width="70"/><el-table-column prop="support_count" label="同好助力" width="90"/><el-table-column label="状态"><template #default="{row}">{{ states[row.status] }}</template></el-table-column><el-table-column prop="reply" label="回复"/><el-table-column label="处理"><template #default="{row}"><el-button :disabled="!canManage || ['fulfilled','rejected'].includes(row.status)" @click="chosenRequest=row; resolution='processing'; reply=''">处理</el-button></template></el-table-column></el-table>
      <el-pagination v-model:current-page="page" :page-size="20" :total="total" layout="total, prev, pager, next" @current-change="loadRequests"/>
    </el-tab-pane>
    <el-tab-pane label="成长任务" name="missions">
      <p>任务按真实观影记录、有效收藏、已发布留言、连续签到和求片助力判定。每日任务按北京时间重置；成就只能领取一次。修改奖励和目标不重置已领取记录。</p>
      <el-button type="primary" :disabled="!canManage" @click="editMission()">新增任务</el-button>
      <el-table :data="missions"><el-table-column prop="name" label="名称"/><el-table-column prop="description" label="说明" min-width="200"/><el-table-column label="依据"><template #default="{row}">{{ missionKinds[row.kind] }}</template></el-table-column><el-table-column label="周期"><template #default="{row}">{{ row.period==='day'?'每日':'一次成就' }}</template></el-table-column><el-table-column prop="target" label="目标" width="70"/><el-table-column prop="reward" label="奖励" width="70"/><el-table-column label="启用"><template #default="{row}">{{ row.active?'是':'否' }}</template></el-table-column><el-table-column label="操作"><template #default="{row}"><el-button :disabled="!canManage" @click="editMission(row)">编辑</el-button></template></el-table-column></el-table>
    </el-tab-pane>
    <el-tab-pane label="装扮商店" name="shop"><el-button type="primary" :disabled="!canManage" @click="editItem()">新增装扮</el-button>
      <el-table :data="shop"><el-table-column prop="id" label="ID" width="60"/><el-table-column prop="name" label="名称"/><el-table-column label="类型"><template #default="{row}">{{ kinds[row.kind] }}</template></el-table-column><el-table-column prop="value" label="样式 / 图片地址" min-width="230"/><el-table-column prop="price" label="价格"/><el-table-column label="上架"><template #default="{row}">{{ row.active?'是':'否' }}</template></el-table-column><el-table-column label="操作"><template #default="{row}"><el-button :disabled="!canManage" @click="editItem(row)">编辑</el-button></template></el-table-column></el-table>
      <p>头像可使用 HTTPS 图片（动态头像支持 GIF）或内置 /api/cosmetics/orbit.svg、pulse.svg；头像框和昵称使用 #RRGGBB，铭牌最多12字。下架后已兑换用户仍可佩戴。</p>
    </el-tab-pane>
  </el-tabs>
  <el-dialog :model-value="!!chosenRequest" title="处理积分求片" @close="chosenRequest=null"><p>{{ chosenRequest?.title }}：{{ chosenRequest?.details }}</p><el-select v-model="resolution"><el-option v-for="(label,key) in states" v-show="key!=='pending'" :key="key" :label="label" :value="key"/></el-select><el-input v-model="reply" type="textarea" :rows="4" maxlength="2000" placeholder="填写进度或可观看链接（必填）"/><p v-if="resolution==='rejected'">拒绝将自动退还该次求片支付的积分。</p><template #footer><el-button type="primary" :loading="busy" @click="resolve">保存并通知用户</el-button></template></el-dialog>
  <el-dialog v-model="itemVisible" title="装扮管理"><el-form label-width="100px"><el-form-item label="名称"><el-input v-model="item.name" maxlength="40"/></el-form-item><el-form-item label="类型"><el-select v-model="item.kind" :disabled="!!item.id"><el-option v-for="(label,key) in kinds" :key="key" :label="label" :value="key"/></el-select></el-form-item><el-form-item label="图片 / 样式"><el-input v-model="item.value"/></el-form-item><el-form-item label="积分价格"><el-input-number v-model="item.price" :min="0" :max="100000"/></el-form-item><el-form-item label="上架"><el-switch v-model="item.active"/></el-form-item></el-form><template #footer><el-button type="primary" :loading="busy" @click="saveItem">保存</el-button></template></el-dialog>
  <el-dialog v-model="missionVisible" title="成长任务配置">
    <el-form label-width="100px"><el-form-item label="任务标识"><el-input v-model="mission.key" :disabled="missionEditing" placeholder="字母开头，使用小写字母、数字和下划线" maxlength="40"/></el-form-item><el-form-item label="名称"><el-input v-model="mission.name" maxlength="40"/></el-form-item><el-form-item label="说明"><el-input v-model="mission.description" maxlength="300" type="textarea"/></el-form-item><el-form-item label="任务依据"><el-select v-model="mission.kind" :disabled="missionEditing"><el-option v-for="(label,key) in missionKinds" :key="key" :label="label" :value="key"/></el-select></el-form-item><el-form-item label="奖励周期"><el-select v-model="mission.period" :disabled="missionEditing"><el-option label="一次成就" value="once"/><el-option label="每日（连续签到不能选每日）" value="day"/></el-select></el-form-item><el-form-item label="目标次数"><el-input-number v-model="mission.target" :min="1" :max="100"/></el-form-item><el-form-item label="奖励积分"><el-input-number v-model="mission.reward" :min="0" :max="500"/></el-form-item><el-form-item label="启用"><el-switch v-model="mission.active"/></el-form-item></el-form>
    <template #footer><el-button type="primary" :loading="busy" @click="saveMission">保存任务</el-button></template>
  </el-dialog>
  </div>
</template>
<script setup lang="ts">
import { ref, reactive, computed, onMounted } from 'vue'
import request from '@/utils/request'
import { useUserStore } from '@/store/user'
import { ElMessage } from 'element-plus'
const user=useUserStore(), canManage=computed(()=>['super_admin','admin'].includes(user.userInfo?.role || ''))
const tab=ref('metrics'),days=ref<any[]>([]),requests=ref<any[]>([]),shop=ref<any[]>([]),rules=reactive<Record<string,number>>({active:5,checkin:10,streak_step:2,streak_cap:30,request_cost:20}),busy=ref(false),page=ref(1),total=ref(0),chosenRequest=ref<any>(null),resolution=ref('processing'),reply=ref(''),itemVisible=ref(false)
const item=reactive({id:0,name:'',kind:'avatar',value:'',price:30,active:true})
const missions=ref<any[]>([]),missionVisible=ref(false),missionEditing=ref(false)
const missionKinds:Record<string,string>={history:'云端观影记录',favorite:'有效作品收藏',comment:'已发布留言',checkin:'连续签到天数',support:'求片助力'}
const mission=reactive({key:'',name:'',description:'',kind:'favorite',period:'once',target:1,reward:15,active:true})
async function loadMissions(){const r:any=await request.get('/api/admin/missions');missions.value=r.data}
function editMission(row?:any){missionEditing.value=!!row;Object.assign(mission,row?{key:row.key,name:row.name,description:row.description,kind:row.kind,period:row.period,target:row.target,reward:row.reward,active:row.active}:{key:'',name:'',description:'',kind:'favorite',period:'once',target:1,reward:15,active:true});missionVisible.value=true}
async function saveMission(){if(mission.kind==='checkin'&&mission.period==='day'){ElMessage.warning('连续签到使用一次成就周期');return}busy.value=true;try{await request.post('/api/admin/missions',mission);missionVisible.value=false;await loadMissions();ElMessage.success('任务已保存')}finally{busy.value=false}}
const kinds:Record<string,string>={avatar:'头像',animated_avatar:'动态头像',frame:'头像框',badge:'铭牌',nickname_color:'彩色昵称'},states:Record<string,string>={pending:'待处理',processing:'寻找中',fulfilled:'已完成',rejected:'未采纳 / 已退款'},ruleLabels:Record<string,string>={active:'每日活跃奖励',checkin:'签到基础奖励',streak_step:'连续签到每日增量',streak_cap:'签到奖励封顶',request_cost:'每次求片积分'}
const today=computed(()=>days.value.find(d=>d.day===new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Shanghai'}).format(new Date())))
async function loadRequests(){const r:any=await request.get('/api/admin/movie-requests',{params:{page:page.value}});requests.value=r.data;total.value=r.total}
async function loadShop(){const r:any=await request.get('/api/admin/shop');shop.value=r.data}
async function saveRules(){busy.value=true;try{await request.post('/api/admin/growth/rules',rules);ElMessage.success('规则已保存')}finally{busy.value=false}}
async function resolve(){if(!reply.value.trim()){ElMessage.warning('请输入处理说明');return}busy.value=true;try{await request.post('/api/admin/movie-requests',{id:chosenRequest.value.id,status:resolution.value,reply:reply.value});chosenRequest.value=null;await loadRequests();ElMessage.success('已处理并通知')}finally{busy.value=false}}
function editItem(row?:any){Object.assign(item,row?{id:row.id,name:row.name,kind:row.kind,value:row.value,price:row.price,active:row.active}:{id:0,name:'',kind:'avatar',value:'',price:30,active:true});itemVisible.value=true}
async function saveItem(){busy.value=true;try{await request.post('/api/admin/shop',item);itemVisible.value=false;await loadShop();ElMessage.success('装扮已保存')}finally{busy.value=false}}
onMounted(async()=>{const results=await Promise.allSettled([request.get('/api/admin/growth'),request.get('/api/admin/growth/rules'),loadRequests(),loadShop(),loadMissions()]);if(results[0].status==='fulfilled')days.value=(results[0].value as any).data;if(results[1].status==='fulfilled')Object.assign(rules,(results[1].value as any).data)})
</script>
<style scoped>.metrics{display:grid;grid-template-columns:repeat(4,1fr);gap:20px;margin:20px 0}p{color:var(--text-color-secondary);line-height:1.8}.el-pagination,.el-textarea{margin-top:20px}@media(max-width:900px){.metrics{grid-template-columns:repeat(2,1fr)}}</style>
