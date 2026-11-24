<script setup lang="ts">
// 骨架屏：目录加载期间的灰色轮廓占位，治白屏顿感（统一调整清单第四批）。
withDefaults(defineProps<{ count?: number }>(), { count: 4 })
</script>
<template>
  <view class="product-grid" aria-hidden="true">
    <view v-for="n in count" :key="n" class="skeleton-card">
      <view class="skeleton-block skeleton-image" />
      <view class="skeleton-block skeleton-line" />
      <view class="skeleton-block skeleton-line short" />
    </view>
  </view>
</template>
