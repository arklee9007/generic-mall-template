<script setup lang="ts">
import { computed, ref } from 'vue'
import { onLoad, onShow } from '@dcloudio/uni-app'
import StoreLayout from '../../components/StoreLayout.vue'
import { money } from '../../services/catalog'
import { demoState, reconcileOrders, statusLabel } from '../../services/shop'
import type { OrderStatus } from '../../services/shop'
import { openPage, toast } from '../../services/routes'
type OrderRow = typeof demoState.orders[number]; type OrderLineRow = OrderRow['lines'][number]
function openLine(order: OrderRow, line: OrderLineRow) { openPage('/pages/product/index?id=' + line.productId) }
const filter = ref('all')
const tabs: { id: OrderStatus | 'all'; name: string }[] = [{ id: 'all', name: '全部' }, ...Object.entries(statusLabel).map(([id, name]) => ({ id: id as OrderStatus, name }))]
const orders = computed(() => demoState.orders.filter(order => filter.value === 'all' || order.status === filter.value))
onLoad(options => { if (options && tabs.some(tab => tab.id === options.status)) filter.value = options.status as string })
onShow(() => reconcileOrders().catch(error => toast(error instanceof Error ? error.message : '订单读取失败')))
</script>
<template><StoreLayout id="store-layout" title="我的订单" eyebrow="ORDERS" active="account"><view v-if="!demoState.user" class="empty-state"><text>登录后查看订单</text><button class="primary" @click="openPage('/pages/login/index?returnTo=' + encodeURIComponent('/pages/orders/index'))">去登录</button></view><template v-else><scroll-view scroll-x class="order-tabs"><view class="chips no-wrap"><button v-for="tab in tabs" :key="tab.id" class="chip" :class="{ chosen: filter === tab.id }" @click="filter = tab.id">{{ tab.name }}</button></view></scroll-view><view class="section"><view v-for="order in orders" :key="order.id" class="order-card" @click="openPage('/pages/order/index?id=' + order.id)"><view class="row between"><text class="small muted">体验订单 · {{ order.id.slice(-10) }}</text><text class="blue small">{{ statusLabel[order.status] }}</text></view><view v-for="(line, index) in order.lines.slice(0, 2)" :key="index" class="order-line" @click.stop="openLine(order, line)"><image :src="line.image" class="line-image" mode="aspectFit" /><view class="line-body"><text class="line-name">{{ line.name }}</text><text class="small muted">{{ line.spec }}</text><text class="small">× {{ line.quantity }}</text></view></view><view class="row between"><text class="small">实付合计 ¥{{ money(order.total) }} →</text></view></view><view v-if="!orders.length" class="empty-state"><text class="empty-title">暂无{{ filter === 'all' ? '' : statusLabel[filter as OrderStatus] }}订单</text><text class="small muted">先去挑选喜欢的商品。</text></view></view></template></StoreLayout></template>
