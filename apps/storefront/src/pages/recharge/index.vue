<script setup lang="ts">
import { computed, ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import StoreLayout from '../../components/StoreLayout.vue'
import { memberState, refreshCommerce, rechargeMember, demoState, discountLabel, TERMS_VERSION } from '../../services/shop'
import { money, shopConfig } from '../../services/catalog'
import { openPage, toast } from '../../services/routes'
const agreed = ref(false), submitting = ref(false)
const selectedPackage = ref(-1)
const customYuan = ref('')
let requestKey = ''
onShow(() => refreshCommerce().catch(error => toast(error instanceof Error ? error.message : '会员信息读取失败')))
const account = computed(() => memberState.account)
const memberEnabled = computed(() => memberState.memberEnabled)
const rechargeEnabled = computed(() => memberState.rechargeEnabled)
const packages = computed(() => memberState.packages.length ? memberState.packages : shopConfig.member.packages)
const customCents = computed(() => { const n = Number(customYuan.value); if (!Number.isFinite(n) || n <= 0) return 0; return Math.round(n * 100) })
const chosenAmount = computed(() => selectedPackage.value >= 0 ? packages.value[selectedPackage.value].amount : customCents.value)
const chosenBonus = computed(() => { const hit = packages.value.find(p => p.amount === chosenAmount.value); return hit ? hit.bonus : 0 })
const amountValid = computed(() => chosenAmount.value >= 100 && chosenAmount.value <= 100000000)
function choosePackage(index: number) { selectedPackage.value = index; customYuan.value = '' }
function useCustom() { selectedPackage.value = -1 }
async function submit() {
  if (!demoState.user) { openPage('/pages/login/index?returnTo=' + encodeURIComponent('/pages/recharge/index')); return }
  if (!memberEnabled.value || !rechargeEnabled.value) { toast('当前店铺未开通充值'); return }
  if (!amountValid.value) { toast('单次充值须在 1 元到 100 万元之间'); return }
  if (!agreed.value) { toast('请阅读并同意充值条款'); return }
  if (submitting.value) return
  submitting.value = true; requestKey ||= 'recharge-' + Date.now().toString(36) + Math.random().toString(36).slice(2)
  try {
    const record = await rechargeMember(chosenAmount.value, agreed.value, requestKey)
    requestKey = ''; toast('充值成功，到账 ¥' + money(record.amount + record.bonusAmount)); openPage('/pages/balance/index', true)
  } catch (error) { toast(error instanceof Error ? error.message : '充值失败，请重试') } finally { submitting.value = false }
}
</script>
<template><StoreLayout title="会员充值" active="account"><view class="section"><text class="block-title">会员充值</text>
<view v-if="account" class="address-card full"><text class="large-title">余额 ¥{{ money(account.balance) }}</text><text>{{ account.isMember ? account.tierName + ' · 等级 ' + account.level + ' · 购物 ' + discountLabel(account.discountBps) : '普通顾客 · 充值后按累计充值实付定级' }}</text><text class="paragraph small muted">累计充值（实付）¥{{ money(account.totalRecharge) }}</text></view>
<template v-if="!memberEnabled"><text class="paragraph small">本店未开通会员服务。</text></template>
<template v-else-if="!rechargeEnabled"><text class="paragraph small">当前店铺未开通充值，余额与会员折扣不受影响。</text></template>
<template v-else>
<view class="section divided"><text class="block-title">选择充值套餐</text><view v-for="(pkg, index) in packages" :key="index" class="order-card" :class="{ chosen: selectedPackage === index }" @click="choosePackage(index)"><view class="row between"><text>{{ pkg.label || '充 ¥' + money(pkg.amount) }}</text><text class="blue">¥{{ money(pkg.amount) }}<template v-if="pkg.bonus > 0"> 送 ¥{{ money(pkg.bonus) }}</template></text></view></view><view v-if="!packages.length" class="empty-state">暂无充值套餐，可输入自定义金额</view>
<text class="field-label">自定义金额（元）</text><input v-model="customYuan" class="form-input" type="digit" placeholder="输入充值金额，1 元到 100 万元" @focus="useCustom" @input="useCustom" /><text class="paragraph small muted">仅与套餐金额完全一致时享受赠送；自定义金额不赠送。预计到账 ¥{{ money(chosenAmount + chosenBonus) }}（含赠送 ¥{{ money(chosenBonus) }}）。</text></view>
<view class="section divided"><text class="block-title">充值条款</text><text class="paragraph small">{{ memberState.terms }}</text><text class="paragraph small muted">条款版本 {{ TERMS_VERSION }}。本体验使用模拟支付，不调用真实微信支付；充值记录可在「余额与流水」中查看。</text></view><button :class="['agreement','recharge-agreement',{ checked: agreed }]" @click="agreed = !agreed">{{ agreed ? '●' : '○' }} 我已阅读并同意《充值条款》</button><button class="primary full recharge-submit" :disabled="submitting || !amountValid" @click="submit">{{ submitting ? '处理中' : '确认模拟充值 ¥' + money(chosenAmount) }}</button>
</template>
</view></StoreLayout></template>
