<script setup lang="ts">
import { computed, ref } from 'vue'
import ProductCard from '../components/ProductCard.vue'
import SkeletonCards from '../components/SkeletonCards.vue'
import { listedProducts, homeData, catalogStatus, shopConfig } from '../services/catalog'
// 原 pages/index 内容，改为滑块壳内的面板；active/paused 控制轮播自动播放，hold 通知壳在横滑轮播时锁住外层滑块。
const props = defineProps<{ active: boolean; paused: boolean }>()
const emit = defineEmits<{ hold: [value: boolean] }>()
const visible = computed(() => props.active && !props.paused)
const heroIndex = ref(0)
const homeContent = computed(() => ({ heroInterval: 5000, slides: homeData.slides }))
const brandWord = computed(() => shopConfig.brandWord || shopConfig.shopName)
const footerLeft = computed(() => shopConfig.brandWord || shopConfig.shopName)
const footerRight = computed(() => shopConfig.footerText || '欢迎光临')
</script>
<template>
  <scroll-view class="panel-scroll" scroll-y>
    <view v-if="homeContent.slides.length" class="hero-section">
      <swiper class="hero-swiper" circular :autoplay="visible" :interval="homeContent.heroInterval" :duration="500" :current="heroIndex" @change="heroIndex = $event.detail.current" aria-label="店铺主图轮播" @touchstart="emit('hold', true)" @touchend="emit('hold', false)" @touchcancel="emit('hold', false)">
        <swiper-item v-for="slide in homeContent.slides" :key="slide.id"><image class="hero-image" :src="slide.image" :alt="slide.alt" mode="aspectFill" /></swiper-item>
      </swiper>
      <view class="hero-pagination"><text class="hero-caption">{{ homeContent.slides[heroIndex].caption }}</text><view class="hero-controls"><button v-for="(slide, index) in homeContent.slides" :key="slide.id" class="slide-control" :class="{ selected: index === heroIndex }" :aria-label="'查看主图 ' + (index + 1)" @click="heroIndex = index">0{{ index + 1 }}</button></view></view>
    </view>
    <view class="products"><view class="section-heading"><view><text class="section-en">{{ brandWord }}</text><text class="section-title">主推精选</text></view><text class="section-number">01 / 精选</text></view><text class="demo-note">{{ catalogStatus.error || (catalogStatus.loading ? '正在读取商品…' : '体验商品 · 模拟支付，不发生真实扣款') }}</text><SkeletonCards v-if="catalogStatus.loading && !listedProducts.length" /><view v-else class="product-grid"><ProductCard v-for="(product, riseIndex) in listedProducts.slice(0, 4)" :key="product.id" :product="product" class="rise-item" :style="'animation-delay:' + (riseIndex > 7 ? 0.35 : riseIndex * 0.05) + 's'" /></view></view>
    <view class="footer"><text>{{ footerLeft }}</text><text>{{ footerRight }}</text></view>
  </scroll-view>
</template>
<style scoped>
.panel-scroll{height:100%}
.hero-section{margin-top:20px}.hero-swiper{height:400px;height:min(104vw,480px);background:var(--brand-blue)}.hero-image{width:100%;height:100%;display:block}.hero-pagination{padding:12px 24px;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid #e5e9f0;gap:8px}.hero-caption{font-size:10px;letter-spacing:1px;color:var(--muted)}.hero-controls{display:flex;gap:8px}.slide-control{margin:0;padding:0;width:40px;height:36px;line-height:36px;border-radius:0;background:#fff;color:var(--muted);font-size:11px;border-bottom:2px solid transparent}.slide-control.selected{color:var(--brand-blue);border-color:var(--brand-blue);font-weight:700}.products{padding:32px 24px}.section-heading{display:flex;align-items:flex-end;justify-content:space-between;gap:8px}.section-en{display:block;font-size:9px;letter-spacing:2px;color:var(--brand-blue);margin-bottom:8px}.section-title{font-size:24px;font-weight:800}.section-number{font-size:9px;letter-spacing:1px;color:var(--muted);padding-bottom:4px}.footer{padding:20px 24px 32px;border-top:1px solid #e5e9f0;font-size:9px;letter-spacing:1px;color:var(--muted);display:flex;justify-content:space-between;gap:8px}
</style>
