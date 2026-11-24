<script setup lang="ts">
import { onUnmounted, ref, watch } from 'vue'
import { homeData, claimSplash, splashState } from '../services/catalog'
import { openPage } from '../services/routes'
const visible = ref(false)
const remaining = ref(0)
let timer: ReturnType<typeof setInterval> | undefined
function close() { visible.value = false; splashState.visible = false; if (timer) { clearInterval(timer); timer = undefined } }
function tapImage() { const link = homeData.splash.link; close(); if (link.startsWith('/pages/')) openPage(link); else if (link.startsWith('https://')) { uni.setClipboardData({ data: link, success: () => uni.showToast({ title: '链接已复制，请在浏览器打开', icon: 'none' }) }) } }
watch(() => homeData.splash, splash => {
  if (visible.value || !splash.enabled || !splash.image || !claimSplash()) return
  remaining.value = Math.min(15, Math.max(1, splash.seconds || 5)); visible.value = true; splashState.visible = true
  timer = setInterval(() => { remaining.value -= 1; if (remaining.value <= 0) close() }, 1000)
}, { immediate: true, deep: true })
onUnmounted(() => { if (timer) clearInterval(timer) })
</script>
<template>
  <view v-if="visible" class="splash-overlay">
    <view class="splash-card">
      <image class="splash-image" :src="homeData.splash.image" mode="widthFix" @click="tapImage" />
      <text class="splash-count">{{ remaining }}s</text>
      <button class="splash-close" @click="close">✕</button>
    </view>
  </view>
</template>
<style scoped>
.splash-overlay { position: fixed; inset: 0; z-index: 200; background: rgba(12, 16, 28, .55); display: flex; align-items: center; justify-content: center; }
.splash-card { position: relative; width: 84vw; border-radius: 16px; overflow: hidden; background: #fff; box-shadow: 0 18px 50px rgba(0, 0, 0, .35); }
.splash-image { width: 100%; display: block; }
.splash-count { position: absolute; top: 10px; left: 10px; padding: 3px 10px; border-radius: 100px; background: rgba(20, 20, 20, .5); color: #fff; font-size: 12px; line-height: 1.5; }
.splash-close { position: absolute; top: 8px; right: 8px; width: 30px; height: 30px; margin: 0; padding: 0; border-radius: 50%; background: rgba(20, 20, 20, .5); color: #fff; font-size: 14px; line-height: 30px; text-align: center; }
</style>
