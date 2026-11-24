<script setup lang="ts">
import { money } from '../services/catalog'
import type { Product } from '../services/catalog'
import { openPage } from '../services/routes'
defineProps<{ product: Product }>()
</script>
<template><button class="product-card" :aria-label="product.name" @click="openPage('/pages/product/index?id=' + product.id)"><image :src="product.image" :alt="product.name" mode="aspectFit" class="product-image" /><view class="product-card-body"><text class="product-subtitle">{{ product.subtitle }}</text><text class="product-name">{{ product.name }}</text><view class="row between"><text class="product-price">¥{{ money(product.price) }}</text></view></view></button></template>
