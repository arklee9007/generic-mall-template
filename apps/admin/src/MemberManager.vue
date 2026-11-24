<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { ElButton, ElAlert, ElDialog } from 'element-plus'
import { callAdmin } from './api'
type Member = { _id: string; phone: string; nickname: string; memberNo: string; level: number; balance: number; totalPurchase: number; totalRecharge: number; createdAt: string }
type MRecord = { amount: number; bonusAmount: number; level: number; requestKey: string; createdAt: string; simulated: boolean }
type BLog = { type: string; amount: number; orderId: string | null; balanceAfter: number; remark: string; createdAt: string }
type Tier = { level: number; name: string }
const members = ref<Member[]>([]), selected = ref<Member>(), records = ref<MRecord[]>([]), logs = ref<BLog[]>([]), tiers = ref<Tier[]>([]), phone = ref(''), busy = ref(false), error = ref(''), notice = ref(''), pickLevel = ref(0)
const yuan = (v: number) => (Number(v) / 100).toFixed(2)
const day = (v: string) => new Date(v).toLocaleDateString('zh-CN')
const logNames: Record<string, string> = { recharge: '充值入账', bonus: '充值赠送入账', pay: '订单支付', refund_in: '退款入账', refund_out: '退款扣回' }
const tierName = (level: number) => level === 0 ? '普通顾客' : (tiers.value.find(t => Number(t.level) === Number(level))?.name || '等级 ' + level)
async function run(fn: () => Promise<void>) { if (busy.value) return; busy.value = true; error.value = ''; notice.value = ''; try { await fn() } catch (e) { error.value = e instanceof Error ? e.message : '操作失败' } finally { busy.value = false } }
async function load() { members.value = (await callAdmin<{ members: Member[] }>('member.list', { phone: phone.value })).members }
async function loadTiers() { try { tiers.value = (await callAdmin<{ tiers: Tier[] }>('membership.list')).tiers || [] } catch { tiers.value = [] } }
async function detail(id: string) {
  const r = await callAdmin<{ member: Member; records: MRecord[]; logs: BLog[] }>('member.detail', { id })
  selected.value = r.member; records.value = r.records; logs.value = r.logs; pickLevel.value = Number(r.member.level) || 0
}
function setLevel() {
  if (!selected.value) return
  const level = Number(pickLevel.value)
  if (!confirm('把“' + selected.value.nickname + '”的等级定为 ' + tierName(level) + '（' + level + ' 级）？手动定级直接写等级，不改累计充值。')) return
  run(async () => {
    await callAdmin('membership.setLevel', { id: selected.value!._id, data: { level } })
    await detail(selected.value!._id); await load(); notice.value = '等级已定为 ' + tierName(level)
  })
}
onMounted(() => run(async () => { await loadTiers(); await load() }))
</script>
<template><section class="content member-manager"><div class="section-heading"><div><p class="eyebrow">MEMBER OPERATIONS</p><h1>会员管理</h1></div><ElButton @click="run(load)" :loading="busy">刷新会员</ElButton></div><ElAlert v-if="error" :title="error" type="error" :closable="false"/><ElAlert v-if="notice" :title="notice" type="success" :closable="false"/><form class="member-search" @submit.prevent="run(load)"><label>手机号查询<input v-model="phone" aria-label="会员手机号查询" placeholder="完整手机号；留空显示最近100位" maxlength="11"/></label><ElButton native-type="submit" :loading="busy">查询会员</ElButton></form><article v-for="m in members" :key="m._id" class="member-card" :data-member-id="m._id"><h3>{{m.nickname}} · {{tierName(Number(m.level))}}</h3><p>{{m.phone}}</p><p>会员编号 {{m.memberNo}} · 注册 {{day(m.createdAt)}}</p><div class="member-values"><span>余额 <strong>¥{{yuan(m.balance)}}</strong></span><span>累计充值实付 <strong>¥{{yuan(m.totalRecharge)}}</strong></span><span>累计购买 <strong>¥{{yuan(m.totalPurchase)}}</strong></span></div><ElButton @click="run(()=>detail(m._id))">查看会员与记录</ElButton></article>
<ElDialog :model-value="!!selected" @close="selected=undefined" title="会员与记录" width="min(760px, calc(100vw - 24px))"><template v-if="selected"><ElAlert v-if="error" :title="error" type="error" :closable="false"/><ElAlert v-if="notice" :title="notice" type="success" :closable="false"/><h3>{{selected.nickname}} · {{selected.phone}}</h3><p>会员编号 {{selected.memberNo}} · {{tierName(Number(selected.level))}} · 余额 ¥{{yuan(selected.balance)}} · 累计充值实付 ¥{{yuan(selected.totalRecharge)}} · 累计购买 ¥{{yuan(selected.totalPurchase)}}</p><form class="level-form" @submit.prevent="setLevel"><label>手动定级<select v-model.number="pickLevel" aria-label="手动定级"><option :value="0">0 级 · 普通顾客</option><option v-for="t in tiers" :key="t.level" :value="Number(t.level)">{{t.level}} 级 · {{t.name}}</option></select></label><ElButton native-type="submit" type="primary" :loading="busy">定为该等级</ElButton></form><p class="muted">只能定为已建档的等级或 0 级；档位在「会员设置」里建。等级平时按累计充值实付自动定，只升不降，赠送不计入。</p><h3>充值记录</h3><article v-for="(rec,i) in records" :key="i" class="member-log"><p>实付 ¥{{yuan(rec.amount)}} · 赠送 ¥{{yuan(rec.bonusAmount)}} · 充值后等级 {{rec.level}} 级{{rec.simulated?' · 模拟支付':''}}</p><small>{{new Date(rec.createdAt).toLocaleString('zh-CN')}}</small></article><p v-if="!records.length" class="muted">暂无充值记录</p><h3>余额流水</h3><article v-for="(log,i) in logs" :key="i" class="member-log"><p>{{logNames[log.type]||log.type}} ¥{{yuan(log.amount)}} · 变动后余额 ¥{{yuan(log.balanceAfter)}}<template v-if="log.orderId"> · 订单 {{log.orderId}}</template></p><p v-if="log.remark" class="muted">{{log.remark}}</p><small>{{new Date(log.createdAt).toLocaleString('zh-CN')}}</small></article><p v-if="!logs.length" class="muted">暂无余额流水</p></template></ElDialog></section></template>
<style>
.member-search{display:flex;gap:16px;align-items:flex-end;flex-wrap:wrap}.member-search label{display:grid;gap:8px;font-size:13px;flex:1}.member-search input{padding:12px;border:1px solid #dce2ec;border-radius:6px;font:inherit;max-width:400px;min-width:0}.member-card{background:white;border:1px solid #e4e9f1;border-radius:8px;padding:20px;margin:16px 0;overflow-wrap:anywhere}.member-card h3{font-size:16px}.member-values{display:flex;flex-wrap:wrap;gap:24px;font-size:13px;color:#677185;margin:20px 0}.member-values strong{color:#141414;display:block;font-size:20px;margin-top:8px}.member-log{padding:16px 0;border-bottom:1px solid #e4e9f1;overflow-wrap:anywhere}.member-log small{color:#677185}.level-form{display:flex;gap:12px;align-items:flex-end;flex-wrap:wrap;margin:16px 0}.level-form label{display:grid;gap:8px;font-size:13px}.level-form select{font:inherit;padding:10px;border:1px solid #dce2ec;border-radius:6px;min-width:200px}@media(max-width:768px){.member-card{padding:16px}.member-search input{width:100%}.member-search label{width:100%}.member-manager .section-heading h1{font-size:26px}}
</style>
