<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import StoreLayout from '../../components/StoreLayout.vue'
import { money } from '../../services/catalog'
import { createOrder, demoState, quoteDraft, payOrder, refreshCommerce, startCheckout, memberState, type Quote } from '../../services/shop'
import { openPage, toast } from '../../services/routes'
import { confirmedValue } from '../../services/input'
const remark = ref(''); const submitting = ref(false)
const useBalance = ref(true)
const address = computed(() => demoState.user ? demoState.addresses.find(a => a.id === demoState.selectedAddressId) || demoState.addresses.find(a => a.isDefault) : undefined)
const balance = computed(() => memberState.account?.balance ?? demoState.user?.balance ?? 0)
const calculation = reactive({ quote: null as Quote | null, error: '', loading: false })
let request = 0
async function loadQuote() { const current = ++request; calculation.loading = true; try { const quote = await quoteDraft(address.value, useBalance.value); if (current === request) { calculation.quote = quote; calculation.error = '' } } catch (error) { if (current === request) { calculation.quote = null; calculation.error = error instanceof Error ? error.message : '报价读取失败' } } finally { if (current === request) calculation.loading = false } }
watch(() => address.value?.id, loadQuote)
watch(useBalance, loadQuote)
async function submit() {
  if (!demoState.user) { openPage('/pages/login/index?returnTo=' + encodeURIComponent('/pages/checkout/index')); return }
  if (!address.value) { toast('请先选择收货地址'); return }
  if (submitting.value) return
  submitting.value = true
  try { const order = await createOrder(address.value.id, remark.value, useBalance.value); uni.showModal({ title: '确认模拟支付', content: '应付 ¥' + money(order.total) + '，不会调用真实微信支付。', success: async result => { try { if (result.confirm) await payOrder(order.id) } catch (error) { toast(error instanceof Error ? error.message : '支付未完成') } finally { openPage('/pages/order/index?id=' + order.id, true) } } }) }
  catch (error) { toast(error instanceof Error ? error.message : '提交失败') }
  finally { submitting.value = false }
}
// 进页先用会话内已有地址立即算价（不再串行等全量刷新），刷新放后台；地址被刷新改动时 watch 自动重算。
onShow(() => { if (!demoState.draft && demoState.cart.some(l => l.selected)) { try { startCheckout() } catch { /* 草稿缺失由报价错误提示兜底 */ } } loadQuote(); refreshCommerce().catch(() => undefined) })
</script>
<template><StoreLayout id="store-layout" title="确认订单" eyebrow="CHECKOUT" active="cart" :actions="true"><view class="section"><view class="address-card" @click="openPage('/pages/addresses/index?choose=1')"><text class="block-title">{{ address ? address.name + ' ' + address.phone.slice(0, 3) + '****' + address.phone.slice(-4) : '选择或新增收货地址' }}</text><text class="small muted">{{ address ? address.region + ' · ' + address.detail : '请先登录并填写收货地址' }}</text><text class="paragraph blue small">修改收货地址 →</text></view>
  <view v-if="calculation.quote"><view v-for="line in calculation.quote.lines" :key="line.skuId" class="order-line"><image :src="line.image" class="line-image" mode="aspectFit" /><view class="line-body"><text class="line-name">{{ line.name }}</text><text class="small muted">{{ line.spec }}</text><text class="paragraph small">¥{{ money(line.unitPrice) }} × {{ line.quantity }}</text></view></view>
  <button v-if="memberState.memberEnabled" :class="['agreement', { checked: useBalance }]" @click="useBalance = !useBalance">{{ useBalance ? '●' : '○' }} 使用余额支付（余额 ¥{{ money(balance) }}，不足部分走模拟微信支付）</button>
  <text class="field-label">订单备注</text><textarea v-model="remark" @blur="remark = confirmedValue($event, remark)" class="form-textarea order-remark" maxlength="200" placeholder="选填，最多200字" /><view class="bill"><view class="row between"><text>商品金额</text><text>¥{{ money(calculation.quote.subtotal) }}</text></view><view class="row between"><text>配送运费</text><text>¥{{ money(calculation.quote.shipping) }}</text></view><view v-if="(calculation.quote.discount || 0) > 0" class="row between"><text>会员折扣</text><text>−¥{{ money(calculation.quote.discount || 0) }}</text></view><view v-if="(calculation.quote.balancePaid || 0) > 0" class="row between"><text>余额抵扣</text><text>−¥{{ money(calculation.quote.balancePaid || 0) }}</text></view><view class="row between"><text>模拟微信支付</text><text>¥{{ money(calculation.quote.wxPaid || 0) }}</text></view></view><text class="paragraph small muted">金额由服务器计算，不发生外部真实扣款。应付金额见底部结算条。</text></view>
  <view v-else class="empty-state"><text>{{ calculation.error || '正在计算金额…' }}</text><button class="secondary" @click="openPage('/pages/cart/index')">返回购物车</button></view>
  </view><template #bar><view class="action-bar"><view class="summary"><text class="small muted">应付</text><text class="price-large">¥{{ money(calculation.quote ? calculation.quote.total : 0) }}</text></view><button class="primary submit-order" :disabled="submitting || (!!demoState.user && !calculation.quote)" @click="submit">{{ !demoState.user ? '登录后提交' : submitting ? '提交中' : '提交订单' }}</button></view></template>
</StoreLayout></template>
