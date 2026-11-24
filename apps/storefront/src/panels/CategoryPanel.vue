<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import SearchField from '../components/SearchField.vue'
import ProductCard from '../components/ProductCard.vue'
import SkeletonCards from '../components/SkeletonCards.vue'
import { categories, listedProducts, catalogStatus } from '../services/catalog'
import { goSearch } from '../services/routes'
// 原 pages/category 内容，改为滑块壳内的面板；分类默认值等目录就绪后自动落位，壳可通过 setCategory 指定。
// 左栏第一项为固定项「所有分类」（虚拟 id，不占后台分类），进页默认选中、展示全部已上架商品。
const ALL_ID = '__all'
const categoryId = ref(ALL_ID)
const subcategoryId = ref('all')
const keyword = ref('')
const current = computed(() => categoryId.value === ALL_ID ? { id: ALL_ID, children: [] as { id: string; name: string }[] } : categories.find(item => item.id === categoryId.value) || { id: '', children: [] })
const filtered = computed(() => listedProducts.value.filter(item => (categoryId.value === ALL_ID || item.category === categoryId.value) && (subcategoryId.value === 'all' || item.subcategory === subcategoryId.value)))
function choose(id: string) { categoryId.value = id; subcategoryId.value = 'all' }
function setCategory(id: string) { if (categories.some(c => c.id === id)) choose(id) }
watch(categories, list => { if (categoryId.value !== ALL_ID && list.length && !list.some(c => c.id === categoryId.value)) categoryId.value = ALL_ID }, { immediate: true })
defineExpose({ setCategory })
</script>
<template>
  <view class="panel-flex">
    <view class="demo-note">体验模式 · 订单会保存，支付为模拟</view>
    <view class="panel-search"><SearchField v-model="keyword" @submit="goSearch" /></view>
    <scroll-view class="panel-scroll" scroll-y>
      <view v-if="catalogStatus.loading || catalogStatus.error" class="demo-note">{{ catalogStatus.error || '正在读取商品…' }}</view>
      <view class="category-layout"><view class="category-rail"><button class="category-option" :class="{ chosen: categoryId === ALL_ID }" @click="choose(ALL_ID)">所有分类</button><button v-for="category in categories" :key="category.id" class="category-option" :class="{ chosen: category.id === categoryId }" @click="choose(category.id)">{{ category.name }}</button></view>
        <view class="category-products"><view v-if="categoryId !== ALL_ID" class="chips"><button class="chip" :class="{ chosen: subcategoryId === 'all' }" @click="subcategoryId = 'all'">全部</button><button v-for="child in current.children" :key="child.id" class="chip" :class="{ chosen: subcategoryId === child.id }" @click="subcategoryId = child.id">{{ child.name }}</button></view><text class="small muted count-label">{{ filtered.length }} 件商品</text><SkeletonCards v-if="catalogStatus.loading && !listedProducts.length" /><template v-else><view class="product-grid grid-switch" :key="categoryId + '-' + subcategoryId"><ProductCard v-for="(product, riseIndex) in filtered" :key="product.id" :product="product" class="rise-item" :style="'animation-delay:' + (riseIndex > 7 ? 0.35 : riseIndex * 0.05) + 's'" /></view><view v-if="!filtered.length" class="empty-state">此分类暂无商品</view></template></view>
      </view>
    </scroll-view>
  </view>
</template>
<style scoped>
.panel-flex{display:flex;flex-direction:column;height:100%}
.panel-scroll{flex:1;height:0}
.panel-search{padding:12px 24px 4px}
</style>
