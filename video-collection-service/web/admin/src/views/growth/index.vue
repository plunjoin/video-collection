<template>
  <div class="operations-page">
  <r-tabs v-model="tab" type="border-card">
    <r-tab-pane label="日活与积分" name="metrics">
      <div class="metrics"><r-statistic title="今日登录用户（DAU）" :value="today?.dau || 0"/><r-statistic title="今日签到" :value="today?.checkins || 0"/><r-statistic title="今日发放 / 退款积分" :value="today?.earned || 0"/><r-statistic title="今日消费积分" :value="today?.spent || 0"/></div>
      <p>按北京时间统计登录用户，每个账号每天计一次。最近30天；积分流水包含活动奖励、兑换和求片退款。</p>
      <r-table :data="days"><r-table-column prop="day" label="日期"/><r-table-column prop="dau" label="日活"/><r-table-column prop="checkins" label="签到"/><r-table-column prop="earned" label="发放 / 退款"/><r-table-column prop="spent" label="消费"/></r-table>
    </r-tab-pane>
    <r-tab-pane label="留存看板" name="retention">
      <p>留存基于匿名访客 + 登录用户的到访记录；<b>次日 / 7 日留存</b>只统计观察窗口已结束的日期（-1 表示尚无数据）。<b>功能渗透率</b>以近 30 天有登录行为的注册用户为分母，用于验证个性化推荐、搜索、收藏等粘性设计是否真正被使用。</p>
      <div class="metrics">
        <r-statistic title="次日留存均值" :value="retention?.next_day_avg || 0" suffix="%" />
        <r-statistic title="7 日留存均值" :value="retention?.seven_day_avg || 0" suffix="%" />
        <r-statistic title="今日新增访客" :value="retention?.today_new || 0" />
        <r-statistic title="今日回访访客" :value="retention?.today_return || 0" />
      </div>
      <h4 class="retention-subtitle">近期新增访客留存（最近14天）</h4>
      <r-table :data="retention?.cohorts || []" size="small" border>
        <r-table-column prop="day" label="日期" width="140" />
        <r-table-column prop="new_visitors" label="新增访客" width="100" />
        <r-table-column label="次日留存" min-width="220">
          <template #default="{ row }">
            <div class="retention-bar" v-if="row.next_day_retention >= 0">
              <span class="retention-bar__num">{{ row.next_day_retention }}%</span>
              <div class="retention-bar__track"><div class="retention-bar__fill" :style="{ width: Math.min(100, row.next_day_retention) + '%' }" /></div>
            </div>
            <span v-else class="retention-bar__none">尚无数据</span>
          </template>
        </r-table-column>
        <r-table-column label="7 日留存" min-width="220">
          <template #default="{ row }">
            <div class="retention-bar" v-if="row.seven_day_retention >= 0">
              <span class="retention-bar__num">{{ row.seven_day_retention }}%</span>
              <div class="retention-bar__track"><div class="retention-bar__fill retention-bar__fill--alt" :style="{ width: Math.min(100, row.seven_day_retention) + '%' }" /></div>
            </div>
            <span v-else class="retention-bar__none">尚无数据</span>
          </template>
        </r-table-column>
      </r-table>
      <h4 class="retention-subtitle">功能渗透率（近30天活跃用户 {{ penetration?.active_users || 0 }} 人 / 全站注册 {{ penetration?.total_users || 0 }} 人）</h4>
      <r-table :data="penetration?.features || []" size="small" border>
        <r-table-column prop="name" label="功能" width="180" />
        <r-table-column prop="count" label="使用用户数" width="120" />
        <r-table-column label="渗透率" min-width="260">
          <template #default="{ row }">
            <div class="retention-bar">
              <span class="retention-bar__num">{{ row.rate }}%</span>
              <div class="retention-bar__track"><div class="retention-bar__fill retention-bar__fill--penetration" :style="{ width: Math.min(100, row.rate) + '%' }" /></div>
            </div>
          </template>
        </r-table-column>
      </r-table>
    </r-tab-pane>
    <r-tab-pane label="积分规则" name="rules"><r-form label-width="150px" :disabled="!canManage" style="max-width:580px">
      <r-form-item v-for="(label,key) in ruleLabels" :key="key" :label="label"><r-input-number v-model="rules[key]" :min="key === 'request_cost' ? 1 : 0" :max="key === 'request_cost' ? 10000 : key === 'streak_cap' ? 500 : key === 'streak_step' ? 20 : 100"/></r-form-item>
      <p>签到奖励 = 基础奖励 + (连续天数 − 1) × 增量，上限为奖励封顶；修改仅影响之后的奖励与消费。</p>
      <r-button type="primary" :loading="busy" @click="saveRules">保存规则</r-button>
    </r-form></r-tab-pane>
    <r-tab-pane label="积分求片" name="requests"><r-button @click="loadRequests">刷新</r-button>
      <r-table :data="requests"><r-table-column prop="id" label="ID" width="70"/><r-table-column prop="username" label="用户"/><r-table-column prop="title" label="片名"/><r-table-column prop="details" label="说明"/><r-table-column prop="cost" label="积分" width="70"/><r-table-column prop="support_count" label="同好助力" width="90"/><r-table-column label="状态"><template #default="{row}">{{ states[row.status] }}</template></r-table-column><r-table-column prop="reply" label="回复"/><r-table-column label="处理"><template #default="{row}"><r-button :disabled="!canManage || ['fulfilled','rejected'].includes(row.status)" @click="chosenRequest=row; resolution='processing'; reply=''">处理</r-button></template></r-table-column></r-table>
      <r-pagination v-model:current-page="page" v-model:page-size="pageSize" :page-sizes="[10, 20, 50, 100]" :total="total" @current-change="loadRequests" @size-change="loadRequests"/>
    </r-tab-pane>
    <r-tab-pane label="成长任务" name="missions">
      <p>任务按真实观影记录、有效收藏、已发布留言、连续签到和求片助力判定。每日任务按北京时间重置；成就只能领取一次。修改奖励和目标不重置已领取记录。</p>
      <r-button type="primary" :disabled="!canManage" @click="editMission()">新增任务</r-button>
      <r-table :data="missions"><r-table-column prop="name" label="名称"/><r-table-column prop="description" label="说明" min-width="200"/><r-table-column label="依据"><template #default="{row}">{{ missionKinds[row.kind] }}</template></r-table-column><r-table-column label="周期"><template #default="{row}">{{ row.period==='day'?'每日':'一次成就' }}</template></r-table-column><r-table-column prop="target" label="目标" width="70"/><r-table-column prop="reward" label="奖励" width="70"/><r-table-column label="启用"><template #default="{row}">{{ row.active?'是':'否' }}</template></r-table-column><r-table-column label="操作"><template #default="{row}"><r-button :disabled="!canManage" @click="editMission(row)">编辑</r-button></template></r-table-column></r-table>
    </r-tab-pane>
    <r-tab-pane label="装扮商店" name="shop"><r-button type="primary" :disabled="!canManage" @click="editItem()">新增装扮</r-button>
      <r-table :data="shop"><r-table-column prop="id" label="ID" width="60"/><r-table-column prop="name" label="名称"/><r-table-column label="类型"><template #default="{row}">{{ kinds[row.kind] }}</template></r-table-column><r-table-column prop="value" label="样式 / 图片地址" min-width="230"/><r-table-column prop="price" label="价格"/><r-table-column label="上架"><template #default="{row}">{{ row.active?'是':'否' }}</template></r-table-column><r-table-column label="操作"><template #default="{row}"><r-button :disabled="!canManage" @click="editItem(row)">编辑</r-button></template></r-table-column></r-table>
      <p>头像可使用 HTTPS 图片（动态头像支持 GIF）或内置 /api/cosmetics/orbit.svg、pulse.svg；头像框和昵称使用 #RRGGBB，铭牌最多12字。下架后已兑换用户仍可佩戴。</p>
    </r-tab-pane>
  </r-tabs>
  <r-dialog :model-value="!!chosenRequest" title="处理积分求片" @close="chosenRequest=null"><p>{{ chosenRequest?.title }}：{{ chosenRequest?.details }}</p><r-select v-model="resolution"><r-option v-for="(label,key) in states" v-show="key!=='pending'" :key="key" :label="label" :value="key"/></r-select><r-input v-model="reply" type="textarea" :rows="4" maxlength="2000" placeholder="填写进度或可观看链接（必填）"/><p v-if="resolution==='rejected'">拒绝将自动退还该次求片支付的积分。</p><template #footer><r-button type="primary" :loading="busy" @click="resolve">保存并通知用户</r-button></template></r-dialog>
  <r-dialog v-model="itemVisible" title="装扮管理"><r-form label-width="100px"><r-form-item label="名称"><r-input v-model="item.name" maxlength="40"/></r-form-item><r-form-item label="类型"><r-select v-model="item.kind" :disabled="!!item.id"><r-option v-for="(label,key) in kinds" :key="key" :label="label" :value="key"/></r-select></r-form-item><r-form-item label="图片 / 样式"><r-input v-model="item.value"/></r-form-item><r-form-item label="积分价格"><r-input-number v-model="item.price" :min="0" :max="100000"/></r-form-item><r-form-item label="上架"><r-switch v-model="item.active"/></r-form-item></r-form><template #footer><r-button type="primary" :loading="busy" @click="saveItem">保存</r-button></template></r-dialog>
  <r-dialog v-model="missionVisible" title="成长任务配置">
    <r-form label-width="100px"><r-form-item label="任务标识"><r-input v-model="mission.key" :disabled="missionEditing" placeholder="字母开头，使用小写字母、数字和下划线" maxlength="40"/></r-form-item><r-form-item label="名称"><r-input v-model="mission.name" maxlength="40"/></r-form-item><r-form-item label="说明"><r-input v-model="mission.description" maxlength="300" type="textarea"/></r-form-item><r-form-item label="任务依据"><r-select v-model="mission.kind" :disabled="missionEditing"><r-option v-for="(label,key) in missionKinds" :key="key" :label="label" :value="key"/></r-select></r-form-item><r-form-item label="奖励周期"><r-select v-model="mission.period" :disabled="missionEditing"><r-option label="一次成就" value="once"/><r-option label="每日（连续签到不能选每日）" value="day"/></r-select></r-form-item><r-form-item label="目标次数"><r-input-number v-model="mission.target" :min="1" :max="100"/></r-form-item><r-form-item label="奖励积分"><r-input-number v-model="mission.reward" :min="0" :max="500"/></r-form-item><r-form-item label="启用"><r-switch v-model="mission.active"/></r-form-item></r-form>
    <template #footer><r-button type="primary" :loading="busy" @click="saveMission">保存任务</r-button></template>
  </r-dialog>
  </div>
</template>
<script setup lang="ts">
import { ref, reactive, computed, onMounted } from 'vue'
import request from '@/utils/request'
import { getRetention } from '@/api/admin'
import { useUserStore } from '@/store/user'
import { notify }  from '@/components/radix/feedback'
const user=useUserStore(), canManage=computed(()=>['super_admin','admin'].includes(user.userInfo?.role || ''))
const tab=ref('metrics'),days=ref<any[]>([]),requests=ref<any[]>([]),shop=ref<any[]>([]),rules=reactive<Record<string,number>>({active:5,checkin:10,streak_step:2,streak_cap:30,request_cost:20}),busy=ref(false),page=ref(1),pageSize=ref(20),total=ref(0),chosenRequest=ref<any>(null),resolution=ref('processing'),reply=ref(''),itemVisible=ref(false)
const retention=ref<any>(null),penetration=ref<any>(null)
async function loadRetention(){try{const r:any=await getRetention();retention.value=r.data?.retention||null;penetration.value=r.data?.penetration||null}catch(e){retention.value=null;penetration.value=null}}
const item=reactive({id:0,name:'',kind:'avatar',value:'',price:30,active:true})
const missions=ref<any[]>([]),missionVisible=ref(false),missionEditing=ref(false)
const missionKinds:Record<string,string>={history:'云端观影记录',favorite:'有效作品收藏',comment:'已发布留言',checkin:'连续签到天数',support:'求片助力'}
const mission=reactive({key:'',name:'',description:'',kind:'favorite',period:'once',target:1,reward:15,active:true})
async function loadMissions(){const r:any=await request.get('/api/admin/missions');missions.value=r.data}
function editMission(row?:any){missionEditing.value=!!row;Object.assign(mission,row?{key:row.key,name:row.name,description:row.description,kind:row.kind,period:row.period,target:row.target,reward:row.reward,active:row.active}:{key:'',name:'',description:'',kind:'favorite',period:'once',target:1,reward:15,active:true});missionVisible.value=true}
async function saveMission(){if(mission.kind==='checkin'&&mission.period==='day'){notify('连续签到使用一次成就周期', 'warning');return}busy.value=true;try{await request.post('/api/admin/missions',mission);missionVisible.value=false;await loadMissions();notify('任务已保存', 'success')}finally{busy.value=false}}
const kinds:Record<string,string>={avatar:'头像',animated_avatar:'动态头像',frame:'头像框',badge:'铭牌',nickname_color:'彩色昵称'},states:Record<string,string>={pending:'待处理',processing:'寻找中',fulfilled:'已完成',rejected:'未采纳 / 已退款'},ruleLabels:Record<string,string>={active:'每日活跃奖励',checkin:'签到基础奖励',streak_step:'连续签到每日增量',streak_cap:'签到奖励封顶',request_cost:'每次求片积分'}
const today=computed(()=>days.value.find(d=>d.day===new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Shanghai'}).format(new Date())))
async function loadRequests(){const r:any=await request.get('/api/admin/movie-requests',{params:{page:page.value,page_size:pageSize.value}});requests.value=r.data;total.value=r.total}
async function loadShop(){const r:any=await request.get('/api/admin/shop');shop.value=r.data}
async function saveRules(){busy.value=true;try{await request.post('/api/admin/growth/rules',rules);notify('规则已保存', 'success')}finally{busy.value=false}}
async function resolve(){if(!reply.value.trim()){notify('请输入处理说明', 'warning');return}busy.value=true;try{await request.post('/api/admin/movie-requests',{id:chosenRequest.value.id,status:resolution.value,reply:reply.value});chosenRequest.value=null;await loadRequests();notify('已处理并通知', 'success')}finally{busy.value=false}}
function editItem(row?:any){Object.assign(item,row?{id:row.id,name:row.name,kind:row.kind,value:row.value,price:row.price,active:row.active}:{id:0,name:'',kind:'avatar',value:'',price:30,active:true});itemVisible.value=true}
async function saveItem(){busy.value=true;try{await request.post('/api/admin/shop',item);itemVisible.value=false;await loadShop();notify('装扮已保存', 'success')}finally{busy.value=false}}
onMounted(async()=>{const results=await Promise.allSettled([request.get('/api/admin/growth'),request.get('/api/admin/growth/rules'),loadRequests(),loadShop(),loadMissions(),loadRetention()]);if(results[0].status==='fulfilled')days.value=(results[0].value as any).data;if(results[1].status==='fulfilled')Object.assign(rules,(results[1].value as any).data)})
</script>
<style scoped lang="scss">
.metrics {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 12px;
  margin: 12px 0;
}

p {
  color: var(--text-secondary);
  font-size: 11px;
  line-height: 1.6;
  margin: 8px 0;
}

.r-pagination,
.r-textarea {
  margin-top: 14px;
}

.retention-subtitle {
  margin: 16px 0 8px;
  font-size: 12px;
  font-weight: 650;
  color: var(--text-primary);
}

.retention-bar {
  display: flex;
  align-items: center;
  gap: 8px;

  &__num {
    width: 44px;
    font-size: 10px;
    font-variant-numeric: tabular-nums;
    color: var(--text-regular);
  }

  &__track {
    flex: 1;
    height: 6px;
    border-radius: var(--radius-pill);
    background: var(--border-color-lighter, #eef1f6);
    overflow: hidden;
  }

  &__fill {
    height: 100%;
    border-radius: var(--radius-pill);
    background: linear-gradient(90deg, var(--brand, #4b9fff), #9a83ff);
    transition: width 0.4s ease;

    &--alt {
      background: linear-gradient(90deg, #0ea5e9, #22d3ee);
    }

    &--penetration {
      background: linear-gradient(90deg, #10b981, #34d399);
    }
  }

  &__none {
    font-size: 10px;
    color: var(--text-secondary);
  }
}

@media (max-width: 900px) {
  .metrics {
    grid-template-columns: repeat(2, 1fr);
  }
}
</style>
