<script setup lang="ts">
import { computed, reactive, ref } from 'vue'
import { onLoad } from '@dcloudio/uni-app'
import StoreLayout from '../../components/StoreLayout.vue'
import { findProduct, money, shopConfig, ensureCatalog, axisLabel, axisValues } from '../../services/catalog'
import { addToCart, availableStock, startCheckout, memberState, memberPrice, discountLabel } from '../../services/shop'
import { openPage, toast } from '../../services/routes'
const id = ref('')
const picked = reactive(['', '', ''])
const quantity = ref(1)
const product = computed(() => findProduct(id.value))
const axes = computed(() => product.value ? [0, 1, 2].filter(i => axisValues(product.value!, i).length > 0) : [])
const selectedSku = computed(() => product.value && product.value.skus.find(s => s.color === picked[0] && s.size === picked[1] && s.pattern === picked[2]))
const chartColumns = computed(() => 'grid-template-columns: repeat(' + (product.value?.specChart?.columns.length || 1) + ', minmax(0, 1fr))')
const showMemberPrice = computed(() => memberState.memberEnabled && !!memberState.account?.isMember && (memberState.account?.discountBps ?? 10000) < 10000)
function skuSlot(sku: { color: string; size: string; pattern: string }, index: number) { return [sku.color, sku.size, sku.pattern][index] }
function available(index: number, value: string) {
  return !!product.value && product.value.skus.some(s => availableStock(s.id) > 0 && skuSlot(s, index) === value && [0, 1, 2].every(j => j === index || picked[j] === '' || skuSlot(s, j) === picked[j]))
}
function select(index: number, value: string) { picked[index] = value; quantity.value = 1 }
async function add(buy = false) {
  if (!product.value || !selectedSku.value) { toast('请选择完整规格'); return }
  try {
    if (buy) { startCheckout([{ productId: product.value.id, skuId: selectedSku.value.id, quantity: quantity.value }]); openPage('/pages/checkout/index') }
    else { await addToCart(product.value.id, selectedSku.value.id, quantity.value); toast('已加入购物车') }
  }
  catch (error) { toast(error instanceof Error ? error.message : '加入失败，请重试') }
}
onLoad(async options => {
  id.value = options && typeof options.id === 'string' ? options.id : ''
  try { await ensureCatalog(true) } catch (error) { toast(error instanceof Error ? error.message : '商品读取失败'); return }
  const first = product.value && product.value.skus.find(s => s.stock > 0)
  if (first) { picked[0] = first.color; picked[1] = first.size; picked[2] = first.pattern }
})
</script>
<template><StoreLayout id="store-layout" :title="product ? '商品详情' : '商品未找到'" active="category" :actions="!!product">
  <template v-if="product"><swiper class="product-gallery" indicator-dots :indicator-active-color="shopConfig.brandColor"><swiper-item v-for="(image, index) in product.gallery" :key="image"><image :src="image" :alt="product.name + '图 ' + (index + 1)" class="gallery-image" mode="aspectFit" /></swiper-item></swiper>
  <view class="section product-intro"><text class="eyebrow">{{ product.subtitle }}</text><text class="large-title">{{ product.name }}</text><view class="row between"><text class="price-large">¥{{ money(product.price) }}</text><text class="small muted">{{ product.freeShipping ? '包邮' : '运费按地区计算' }} · 体验商品</text></view><text v-if="showMemberPrice" class="small blue">会员价 ¥{{ money(memberPrice(product.price)) }} · {{ discountLabel(memberState.account?.discountBps || 10000) }}</text></view>
  <view v-if="axes.length" class="section divided"><text class="block-title">选择规格</text><view v-for="index in axes" :key="index" class="spec-group"><text class="field-label">{{ axisLabel(product, index) }}</text><view class="chips"><button v-for="value in axisValues(product, index)" :key="value" class="chip spec-choice" :class="{ chosen: value === picked[index] }" :disabled="!available(index, value)" :aria-label="value + (!available(index, value) ? ' 售罄' : '')" @click="select(index, value)">{{ value }}{{ !available(index, value) ? ' · 售罄' : '' }}</button></view></view>
  <view class="row between"><text class="small muted">可用库存 {{ selectedSku ? availableStock(selectedSku.id) : 0 }}</text><view class="stepper"><button :disabled="quantity <= 1" aria-label="减少数量" @click="quantity--">−</button><text>{{ quantity }}</text><button :disabled="!selectedSku || quantity >= availableStock(selectedSku.id)" aria-label="增加数量" @click="quantity++">＋</button></view></view></view>
  <view v-else class="section divided"><view class="row between"><text class="small muted">可用库存 {{ selectedSku ? availableStock(selectedSku.id) : 0 }}</text><view class="stepper"><button :disabled="quantity <= 1" aria-label="减少数量" @click="quantity--">−</button><text>{{ quantity }}</text><button :disabled="!selectedSku || quantity >= availableStock(selectedSku.id)" aria-label="增加数量" @click="quantity++">＋</button></view></view></view>
  <view class="section divided"><text class="block-title">商品介绍</text><image v-for="(img, di) in (product.detailImages.length ? product.detailImages : [product.detail])" :key="di" :src="img" mode="widthFix" class="detail-image" /></view>
  <view v-if="shopConfig.specChart.enabled && product.specChart" class="section divided"><text class="block-title">{{ shopConfig.specChart.title }}</text><view class="size-table"><view class="table-row table-head" :style="chartColumns"><text v-for="col in product.specChart.columns" :key="col">{{ col }}</text></view><view v-for="(row, ri) in product.specChart.rows" :key="ri" class="table-row" :style="chartColumns"><text v-for="(cell, ci) in row" :key="ci">{{ cell }}</text></view></view></view>
  <view class="section divided"><text class="block-title">购买前请了解</text><text v-for="note in shopConfig.notices" :key="note" class="paragraph small muted">{{ note }}</text></view>
  </template><view v-else class="empty-state"><text>该商品不存在或已下架</text><button class="primary" @click="openPage('/pages/category/index')">浏览其他商品</button></view>
  <template #bar><view v-if="product" class="action-bar"><button class="secondary" :disabled="!selectedSku || availableStock(selectedSku.id) < 1" @click="add(false)">加入购物车</button><button class="primary" :disabled="!selectedSku || availableStock(selectedSku.id) < 1" @click="add(true)">立即购买</button></view></template>
</StoreLayout></template>
