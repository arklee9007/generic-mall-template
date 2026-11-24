<script setup lang="ts">
import { computed, ref } from 'vue'
import { onLoad } from '@dcloudio/uni-app'
import StoreLayout from '../../components/StoreLayout.vue'
import { loginDemo } from '../../services/shop'
import { shopConfig } from '../../services/catalog'
import { decodeRouteQuery, openPage, toast } from '../../services/routes'
import { confirmedValue } from '../../services/input'
import { callCloud } from '../../services/cloud'
const phone = ref(''); const agreed = ref(false); const returnTo = ref('/pages/account/index'); const wechatReady = ref(false)
const brandTitle = computed(() => shopConfig.brandWord || shopConfig.shopName)
onLoad(options => { const path = decodeRouteQuery(options && options.returnTo); if (/^\/pages\/[a-z-]+\/index(?:\?|$)/.test(path)) returnTo.value = path })
async function login() {
  if (!agreed.value) { toast('请先同意手机号绑定说明'); return }
  try { await loginDemo(phone.value.trim()); openPage(returnTo.value, true) } catch (error) { toast(error instanceof Error ? error.message : '登录失败') }
}
async function wechat() {
  // #ifdef MP-WEIXIN
  try { await callCloud('auth', { action: 'login' }); wechatReady.value = true; toast('微信身份已确认，请绑定手机号') } catch (error) { toast(error instanceof Error ? error.message : '微信授权未完成') }
  // #endif
  // #ifndef MP-WEIXIN
  toast('请在微信小程序内完成微信身份与手机号绑定')
  // #endif
}
</script>
<template><StoreLayout id="store-layout" title="欢迎光临" eyebrow="WELCOME" active="account"><view class="section login-form"><text class="login-wordmark">{{ brandTitle }}</text><text class="paragraph muted small">微信身份由云服务验证，手机号手填绑定；短信验证码关闭，不验证手机号归属。H5 浏览商品，登录与交易请在微信小程序完成。</text><text class="field-label">手机号</text><input v-model="phone" @blur="phone = confirmedValue($event, phone)" class="form-input phone-input" type="number" maxlength="11" placeholder="请输入11位手机号" /><button class="agreement" :class="{ checked: agreed }" @click="agreed = !agreed">{{ agreed ? '●' : '○' }} 我已了解并同意：绑定手填手机号，短信验证关闭</button><button class="primary full login-submit" @click="login">绑定手机号 / 注册</button><button class="secondary full" @click="wechat">{{ wechatReady ? '微信身份已确认' : '微信授权入口' }}</button><text class="paragraph small muted">短信开关：关闭　真实支付：关闭</text></view></StoreLayout></template>
