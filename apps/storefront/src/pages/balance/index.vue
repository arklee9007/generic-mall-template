<script setup lang="ts">
import { computed } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import StoreLayout from '../../components/StoreLayout.vue'
import { demoState, memberState, refreshCommerce, refreshLogs, discountLabel } from '../../services/shop'
import { money } from '../../services/catalog'
import { openPage, toast } from '../../services/routes'
const logTypeNames: Record<string, string> = { recharge: '充值', bonus: '充值赠送', pay: '订单支付', refund_in: '退款入账' }
const day = (iso?: string | null) => iso ? new Date(iso).toLocaleDateString('zh-CN') : '—'
const account = computed(() => memberState.account)
onShow(async () => { try { await refreshCommerce(); if (demoState.user) await refreshLogs() } catch (error) { toast(error instanceof Error ? error.message : '记录读取失败') } })
</script>
<template><StoreLayout title="余额与流水" active="account"><view class="section"><text class="field-label">店铺余额</text><text class="price-large">¥{{ money(account?.balance || 0) }}</text><text class="paragraph small muted">{{ account?.isMember ? account.tierName + ' · 等级 ' + account.level + ' · 购物 ' + discountLabel(account.discountBps) : '普通顾客' }} · 累计充值（实付）¥{{ money(account?.totalRecharge || 0) }}</text><button v-if="memberState.rechargeEnabled" class="secondary full" @click="openPage('/pages/recharge/index')">去充值</button><text v-else class="paragraph small muted">当前店铺未开通充值。</text><text class="block-title">充值记录</text><view v-for="(rec, index) in memberState.records" :key="'r' + index" class="order-card"><view class="row between"><text>充值 ¥{{ money(rec.amount) }}<template v-if="rec.bonusAmount > 0"> 送 ¥{{ money(rec.bonusAmount) }}</template></text><text class="blue">到账 ¥{{ money(rec.amount + rec.bonusAmount) }}</text></view><text class="paragraph small muted">充值后等级 {{ rec.level }}{{ rec.simulated ? ' · 模拟支付' : '' }}</text><text class="small muted">{{ new Date(rec.createdAt).toLocaleString() }}</text></view><view v-if="!memberState.records.length" class="empty-state">暂无充值记录</view><text class="block-title">余额流水</text><view v-for="(log, index) in memberState.logs" :key="'l' + index" class="order-card"><view class="row between"><text>{{ logTypeNames[log.type] || log.type }}</text><text class="blue">{{ log.amount >= 0 ? '+' : '−' }}¥{{ money(Math.abs(log.amount)) }}</text></view><text class="paragraph small muted">{{ log.remark || '' }} · 变动后余额 ¥{{ money(log.balanceAfter) }}</text><text class="small muted">{{ new Date(log.createdAt).toLocaleString() }}</text></view><view v-if="!memberState.logs.length" class="empty-state">暂无余额流水</view></view></StoreLayout></template>
