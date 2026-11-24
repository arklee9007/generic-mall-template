<script setup lang="ts">
import { computed, onMounted } from 'vue'
import MembershipCard from '../components/MembershipCard.vue'
import { demoState, logoutDemo, memberState, refreshCommerce, discountLabel } from '../services/shop'
import { money, shopConfig } from '../services/catalog'
import { openPage, toast } from '../services/routes'
// 原 pages/account 内容，改为滑块壳内的面板；壳在切到本页时调 refresh。
const account = computed(() => memberState.account)
const memberEnabled = computed(() => memberState.memberEnabled)
const profileMark = computed(() => (shopConfig.brandWord || shopConfig.shopName || '商').slice(0, 1))
function rechargeEntry() { openPage('/pages/recharge/index') }
const orderLinks = [{ status: 'pending', name: '待付款' }, { status: 'processing', name: '待发货' }, { status: 'shipped', name: '待收货' }, { status: 'completed', name: '已完成' }]
function logout() { uni.showModal({ title: '退出登录', content: '退出当前页面登录状态，服务端订单与会员记录会保留。', success: result => { if (result.confirm) { logoutDemo(); toast('已退出本地体验登录') } } }) }
function refresh() { refreshCommerce().catch(error => toast(error instanceof Error ? error.message : '账户读取失败')) }
onMounted(refresh)
defineExpose({ refresh })
</script>
<template>
  <view class="panel-flex">
    <view class="demo-note">体验模式 · 订单会保存，支付为模拟</view>
    <scroll-view class="panel-scroll" scroll-y>
      <view class="section account-top">
        <MembershipCard v-if="memberEnabled" id="membership-card" :key="String(!!account?.isMember)" :member="!!account?.isMember" :tier-name="account?.tierName || '普通顾客'" :level="account?.level || 0" :discount-label="discountLabel(account?.discountBps || 10000)" :balance="account?.balance || 0" :total-recharge="account?.totalRecharge || 0" :card-bg="account?.cardBg || ''" :card-text="account?.cardText || ''" :brand-word="shopConfig.brandWord" @recharge="rechargeEntry" />
        <view class="profile"><view class="profile-mark">{{ profileMark }}</view><view><text class="line-name">{{ demoState.user ? demoState.user.nickname : '你好，欢迎光临' }}</text><text v-if="demoState.user" class="paragraph small muted">{{ demoState.user.phone.slice(0, 3) }}****{{ demoState.user.phone.slice(-4) }} · 手机手填绑定</text><text v-if="demoState.user && demoState.user.memberNo" class="paragraph small muted">会员编号 {{ demoState.user.memberNo }}</text><button v-else class="text-button blue" @click="openPage('/pages/login/index')">登录 / 注册 →</button></view></view>
        <view class="row between"><text class="block-title">我的订单</text><button class="text-button blue" @click="openPage('/pages/orders/index')">全部订单 →</button></view>
        <view class="order-shortcuts"><button v-for="link in orderLinks" :key="link.status" @click="openPage('/pages/orders/index?status=' + link.status)"><text>{{ link.name }}</text><text class="small muted">{{ demoState.user ? demoState.orders.filter(o => o.status === link.status).length : '—' }}</text></button></view>
        <view class="account-menu"><button @click="openPage('/pages/addresses/index')">收货地址 <text>管理 →</text></button><button v-if="memberEnabled" @click="openPage('/pages/recharge/index')">会员充值 <text>{{ account?.isMember ? account.tierName + ' · ' + discountLabel(account.discountBps) + ' →' : '充值成为会员 →' }}</text></button><button v-if="memberEnabled" @click="openPage('/pages/balance/index')">余额与流水 <text>余额 ¥{{ money(account?.balance || 0) }} →</text></button><button @click="openPage('/pages/faq/index')">帮助与客服 <text>FAQ / 人工客服 →</text></button></view>
        <button v-if="demoState.user" class="secondary full logout-button" @click="logout">退出登录</button><text class="paragraph small muted">{{ shopConfig.shopName }} · 体验支付，不发生外部真实扣款</text>
      </view>
    </scroll-view>
  </view>
</template>
<style scoped>
.panel-flex{display:flex;flex-direction:column;height:100%}
.panel-scroll{flex:1;height:0}
</style>
