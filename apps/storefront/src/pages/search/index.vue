<script setup lang="ts">
import { ref } from 'vue'
import { onLoad } from '@dcloudio/uni-app'
import StoreLayout from '../../components/StoreLayout.vue'
import SearchField from '../../components/SearchField.vue'
import ProductCard from '../../components/ProductCard.vue'
import { searchProducts, type Product } from '../../services/catalog'
import { decodeRouteQuery } from '../../services/routes'
const keyword = ref('')
const submitted = ref('')
const results = ref<Product[]>([]), loading = ref(false), error = ref('')
async function search(value: string) { keyword.value = value; submitted.value = value.trim(); if (!submitted.value) { results.value = []; return }; loading.value = true; error.value = ''; try { results.value = await searchProducts(submitted.value) } catch (e) { results.value = []; error.value = e instanceof Error ? e.message : '搜索失败，请重试' } finally { loading.value = false } }
onLoad(options => { keyword.value = decodeRouteQuery(options && options.q); search(keyword.value) })
</script>
<template><StoreLayout id="store-layout" title="搜索商品" eyebrow="SEARCH / DISCOVER" active="search"><view class="sticky-search"><SearchField v-model="keyword" @submit="search" /></view><view class="section"><text v-if="loading || error" class="demo-note">{{ error || '正在搜索…' }}</text><view v-if="submitted" class="row between result-heading"><text>“{{ submitted }}”</text><text class="small muted">{{ results.length }} 件商品</text></view><view v-if="results.length" class="product-grid"><ProductCard v-for="product in results" :key="product.id" :product="product" /></view><view v-else class="empty-state"><text class="empty-title">{{ submitted ? '没有找到相关商品' : '从一个关键词开始' }}</text><text class="muted small">{{ submitted ? '试试分类名：家居日用、文具办公、休闲食品' : '可以搜索分类、商品名或关键词' }}</text></view></view></StoreLayout></template>

