<script setup lang="ts">
import { shopConfig } from '../services/catalog'
import { toast } from '../services/routes'
defineProps<{ compact?: boolean }>()
</script>
<template><view class="customer-service"><text v-if="!compact" class="paragraph small muted">人工服务时间：{{ shopConfig.serviceHours }}</text>
  <!-- #ifdef MP-WEIXIN -->
  <button class="secondary full" open-type="contact" @error="toast('客服会话未打开，请检查微信客服配置后重试')">转微信人工客服</button>
  <!-- #endif -->
  <!-- #ifndef MP-WEIXIN -->
  <button class="secondary full" @click="toast('请在微信小程序中使用官方人工客服')">转微信人工客服</button>
  <!-- #endif -->
</view></template>
