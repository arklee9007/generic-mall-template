<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { findProduct, money } from '../services/catalog'
import { availableStock, cartGoodsAmount, demoState, refreshCommerce, removeCart, saveDemo, setCartQuantity, startCheckout } from '../services/shop'
import { goMain, openPage, toast } from '../services/routes'
// B-27：原 pages/cart 内容，改为滑块壳内的面板；结算条是面板内的底栏（随面板一起滑动），壳在切到本页时调 refresh。
const entries = computed(() => demoState.cart.map(line => { const product = findProduct(line.productId); return { line, product, sku: product && product.skus.find(s => s.id === line.skuId) } }))
const selected = computed(() => entries.value.filter(entry => entry.line.selected && entry.product && entry.sku))
const total = cartGoodsAmount
const allSelected = computed(() => entries.value.length > 0 && entries.value.every(entry => entry.line.selected))
async function toggle(key: string) { const line = demoState.cart.find(item => item.key === key); if (line) line.selected = !line.selected; try { await saveDemo() } catch (error) { toast(error instanceof Error ? error.message : '选择未保存') } }
async function toggleAll() { const value = !allSelected.value; demoState.cart.forEach(line => { line.selected = value }); try { await saveDemo() } catch (error) { toast(error instanceof Error ? error.message : '选择未保存') } }
async function change(key: string, quantity: number) { try { await setCartQuantity(key, quantity) } catch (error) { toast(error instanceof Error ? error.message : '修改失败') } }
function remove(key: string) { uni.showModal({ title: '移出购物车', content: '确认移除这件商品？', success: result => { if (result.confirm) removeCart(key).catch(error => toast(error instanceof Error ? error.message : '移除失败')) } }) }
function checkout() { try { startCheckout(); openPage('/pages/checkout/index') } catch (error) { toast(error instanceof Error ? error.message : '请选择商品') } }
function refresh() { refreshCommerce().catch(error => toast(error instanceof Error ? error.message : '购物车读取失败')) }
onMounted(refresh)
defineExpose({ refresh })
</script>
<template>
  <view class="panel-flex">
    <view class="demo-note">体验模式 · 订单会保存，支付为模拟</view>
    <scroll-view class="panel-scroll" scroll-y>
      <view v-if="entries.length" class="section"><view class="row between"><text class="small muted">{{ entries.length }} 款商品</text><button class="text-button blue select-all" @click="toggleAll">{{ allSelected ? '取消全选' : '全选' }}</button></view>
        <view v-for="entry in entries" :key="entry.line.key" class="cart-line"><button class="selection-button" :aria-label="(entry.line.selected ? '取消选择 ' : '选择 ') + (entry.product ? entry.product.name : '已下架商品')" @click="toggle(entry.line.key)">{{ entry.line.selected ? '●' : '○' }}</button><image :src="entry.product ? entry.product.image : '/static/products/placeholder.svg'" class="line-image" mode="aspectFit" /><view class="line-body"><text class="line-name" @click="openPage('/pages/product/index?id=' + entry.line.productId)">{{ entry.product ? entry.product.name : '商品已下架' }}</text><text class="small muted">{{ entry.sku ? [entry.sku.color, entry.sku.size, entry.sku.pattern].join(' / ') : '规格已失效' }}</text><view class="row between"><text class="blue small">¥{{ money(entry.product ? entry.product.price : 0) }}</text><button class="text-button" @click="remove(entry.line.key)">移除</button></view><view class="stepper"><button :disabled="entry.line.quantity <= 1" aria-label="减少数量" @click="change(entry.line.key, entry.line.quantity - 1)">−</button><text>{{ entry.line.quantity }}</text><button :disabled="entry.line.quantity >= availableStock(entry.line.skuId)" aria-label="增加数量" @click="change(entry.line.key, entry.line.quantity + 1)">＋</button></view><text v-if="entry.line.quantity > availableStock(entry.line.skuId)" class="small blue">库存已变化，请减少数量或移除</text></view></view>
      </view>
      <view v-else class="empty-state"><text class="empty-title">购物袋还空着</text><text class="small">去挑选喜欢的商品。</text><button class="primary" @click="goMain('category')">浏览商品</button></view>
    </scroll-view>
    <view v-if="entries.length" class="action-bar action-bar--panel"><view class="summary"><text class="small muted">商品合计（未含运费）</text><text class="price-large">¥{{ money(total) }}</text></view><button class="primary checkout-button" :disabled="!selected.length" @click="checkout">去结算 {{ selected.length }}</button></view>
  </view>
</template>
<style scoped>
.panel-flex{display:flex;flex-direction:column;height:100%}
.panel-scroll{flex:1;height:0}
</style>
