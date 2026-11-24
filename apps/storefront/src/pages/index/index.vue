<script setup lang="ts">
import { computed, ref } from 'vue'
import { onLoad, onShow, onUnload } from '@dcloudio/uni-app'
import CapsuleNavigation from '../../components/CapsuleNavigation.vue'
import SplashAd from '../../components/SplashAd.vue'
import HomePanel from '../../panels/HomePanel.vue'
import CategoryPanel from '../../panels/CategoryPanel.vue'
import CartPanel from '../../panels/CartPanel.vue'
import AccountPanel from '../../panels/AccountPanel.vue'
import { ensureCatalog, ensureCatalogStale, homeData, splashState, shopConfig } from '../../services/catalog'
import { goSearch } from '../../services/routes'
import { MAIN_PANELS, takeMainTarget } from '../../services/mainPanel'
import type { NavigationDestination } from '../../components/navigation'
// 真滑块壳：四个主页同居一页，跟手拖动切换（拖一半松手弹回、拖过半才切），无模糊；
// 胶囊高亮块由 floatIndex 驱动、与拖动进度同步。点胶囊=程序化切换，动画期间 transition 事件同样推进 floatIndex。
// 版式以首页原布局为准——壳顶是一条与内容同步横滑的「头部带」
// （首页格=公告条+品牌区原样保留；其余三格是各自页标题），头部带之下是全程固定不动的一条胶囊导航，
// 胶囊在四页里落在同一高度；标题移到胶囊上方后，各面板内不再自带标题。
const winH = uni.getSystemInfoSync().windowHeight || 640
const HEAD_H = 131
const current = ref(0)
const floatIndex = ref(0)
const searchOpen = ref(false)
const bannerHold = ref(false)
const noticeIndex = ref(0)
const categoryRef = ref<InstanceType<typeof CategoryPanel> | null>(null)
const cartRef = ref<InstanceType<typeof CartPanel> | null>(null)
const accountRef = ref<InstanceType<typeof AccountPanel> | null>(null)
const activeName = computed(() => MAIN_PANELS[current.value])
const noticeAutoplay = computed(() => current.value === 0 && !searchOpen.value)
const swiperHeight = Math.max(320, winH - HEAD_H - 60)
const brandTitle = computed(() => shopConfig.brandWord || shopConfig.shopName)
const brandSub = computed(() => shopConfig.brandWord ? shopConfig.shopName : '欢迎光临')
function refreshPanel(index: number) {
  if (index === 2) cartRef.value?.refresh()
  if (index === 3) accountRef.value?.refresh()
}
function setPanel(index: number) {
  if (index < 0 || index >= MAIN_PANELS.length) return
  current.value = index
  refreshPanel(index)
}
function onNavigate(dest: NavigationDestination) { setPanel(MAIN_PANELS.indexOf(dest)) }
function onTransition(e: { detail: { dx: number } }) {
  const w = uni.getSystemInfoSync().windowWidth || 375
  floatIndex.value = Math.min(3, Math.max(0, current.value + e.detail.dx / w))
}
function onChange(e: { detail: { current: number } }) { current.value = e.detail.current }
function onAnimationFinish(e: { detail: { current: number } }) {
  current.value = e.detail.current
  floatIndex.value = e.detail.current
  refreshPanel(e.detail.current)
}
function onMainPanelEvent(dest: NavigationDestination) { setPanel(MAIN_PANELS.indexOf(dest)) }
function consumeTarget() {
  const t = takeMainTarget()
  if (!t) return
  const idx = MAIN_PANELS.indexOf(t.dest as NavigationDestination)
  if (idx >= 0) setPanel(idx)
  if (t.categoryId) categoryRef.value?.setCategory(t.categoryId)
}
onLoad(() => {
  uni.$on('mall-main-panel', onMainPanelEvent)
})
onUnload(() => uni.$off('mall-main-panel', onMainPanelEvent))
onShow(() => { ensureCatalogStale(60000).catch(() => { /* 目录错误态由各面板呈现 */ }); consumeTarget() })
</script>
<template>
  <view class="main-shell" :style="{ height: winH + 'px' }">
    <SplashAd />
    <view class="head-strip" :style="{ height: HEAD_H + 'px' }">
      <view class="head-track" :style="{ transform: 'translateX(' + (-floatIndex * 100) + '%)' }">
        <view class="head-cell head-cell--home">
          <swiper v-if="homeData.notices.length" class="notice" vertical circular :autoplay="noticeAutoplay" :interval="4000" :duration="400" @change="noticeIndex = $event.detail.current" aria-label="店铺公告">
            <swiper-item v-for="notice in homeData.notices" :key="notice.id"><view class="notice-line"><text>{{ notice.text }}</text><text class="notice-count">{{ noticeIndex + 1 }} / {{ homeData.notices.length }}</text></view></swiper-item>
          </swiper>
          <view class="brand"><text class="wordmark">{{ brandTitle }}</text><view class="brand-signature"><text class="subtitle">{{ brandSub }}</text><text class="brand-caption">欢迎光临</text></view></view>
        </view>
        <view class="head-cell"><view class="page-heading head-heading"><view><text class="eyebrow">BROWSE</text><text class="page-title">分类</text></view></view></view>
        <view class="head-cell"><view class="page-heading head-heading"><view><text class="eyebrow">SHOPPING BAG</text><text class="page-title">购物车</text></view></view></view>
        <view class="head-cell"><view class="page-heading head-heading"><view><text class="eyebrow">MY ACCOUNT</text><text class="page-title">我的</text></view></view></view>
      </view>
    </view>
    <CapsuleNavigation id="site-navigation" :active="activeName" :float-index="floatIndex" overlay-top="203px" @navigate="onNavigate" @search="goSearch" @search-visibility="searchOpen = $event" />
    <swiper class="main-swiper" :style="{ height: swiperHeight + 'px' }" :current="current" :duration="260" :disable-touch="searchOpen || splashState.visible || bannerHold" @transition="onTransition" @change="onChange" @animationfinish="onAnimationFinish">
      <swiper-item><HomePanel :active="current === 0" :paused="searchOpen" @hold="bannerHold = $event" /></swiper-item>
      <swiper-item><CategoryPanel ref="categoryRef" /></swiper-item>
      <swiper-item><CartPanel ref="cartRef" /></swiper-item>
      <swiper-item><AccountPanel ref="accountRef" /></swiper-item>
    </swiper>
  </view>
</template>
<style scoped>
.main-shell{max-width:480px;margin:0 auto;box-sizing:border-box;background:#fff;display:flex;flex-direction:column}
.main-swiper{width:100%}
.head-strip{width:100%;overflow:hidden;flex-shrink:0}
.head-track{display:flex;height:100%}
.head-cell{flex:0 0 100%;height:100%;display:flex;flex-direction:column;justify-content:flex-end;box-sizing:border-box}
.head-heading{padding-bottom:20px}
.notice{height:32px;background:var(--brand-blue);color:#fff;flex-shrink:0}.notice-line{height:32px;padding:0 24px;display:flex;align-items:center;justify-content:space-between;gap:8px;font-size:10px;letter-spacing:1px}.notice-count{flex-shrink:0;font-size:9px;opacity:.75}.brand{display:flex;align-items:center;justify-content:space-between;padding:24px 24px 20px;gap:8px}.wordmark{font-family:Impact,'Arial Narrow',sans-serif;font-weight:900;font-size:48px;line-height:1.1;letter-spacing:-1px;color:var(--brand-blue)}.brand-signature{display:flex;flex-direction:column;align-items:flex-end;gap:8px}.subtitle{font-size:13px;letter-spacing:4px}.brand-caption{font-size:8px;letter-spacing:1px;color:var(--muted)}
</style>
