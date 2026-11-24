<script setup lang="ts">
import CapsuleNavigation from './CapsuleNavigation.vue'
import type { NavigationItem } from './navigation'
import { goMain, goSearch, goBack } from '../services/routes'
defineOptions({ options: { virtualHost: true } })
defineProps<{ title: string; eyebrow?: string; active?: NavigationItem; actions?: boolean }>()
</script>
<template>
  <view class="app-shell" :class="{ 'with-actions': actions }">
    <CapsuleNavigation id="site-navigation" :active="active || 'category'" @navigate="goMain" @search="goSearch" />
    <view class="page-heading"><view><text class="eyebrow">{{ eyebrow || '商城' }}</text><text class="page-title">{{ title }}</text></view><button class="text-button" @click="goBack">返回</button></view>
    <view class="demo-note">体验模式 · 订单会保存，支付为模拟</view>
    <view class="page-enter"><slot /></view>
    <slot name="bar" />
  </view>
</template>
