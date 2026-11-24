<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { ElButton, ElAlert } from 'element-plus'
import { callAdmin, uploadAdminFile } from './api'
const DEFAULT_AXES = ['规格一', '规格二', '规格三']
const config = ref({ shopName: '', servicePhone: '', serviceHours: '', notifyEmail: '', smsEnabled: false, realPaymentEnabled: false }), busy = ref(false), error = ref(''), notice = ref('')
const shop = ref({ brandWord: '', brandColor: '#2563EB', logo: '', footerText: '', specAxes: [...DEFAULT_AXES], chartEnabled: true, chartTitle: '规格说明', reviewRequired: true })
async function run(fn: () => Promise<void>) { if (busy.value) return; busy.value = true; error.value = ''; notice.value = ''; try { await fn() } catch (e) { error.value = e instanceof Error ? e.message : '操作失败' } finally { busy.value = false } }
async function load() {
  const r = await callAdmin<{ config: typeof config.value & { shopConfig?: Record<string, any> } }>('system.get')
  config.value = { shopName: r.config.shopName || '', servicePhone: r.config.servicePhone || '', serviceHours: r.config.serviceHours || '', notifyEmail: r.config.notifyEmail || '', smsEnabled: !!r.config.smsEnabled, realPaymentEnabled: !!r.config.realPaymentEnabled }
  const s = r.config.shopConfig || {}
  const axes = Array.isArray(s.specAxes) ? s.specAxes : []
  shop.value = {
    brandWord: typeof s.brandWord === 'string' ? s.brandWord : '',
    brandColor: typeof s.brandColor === 'string' && /^#[0-9a-fA-F]{6}$/.test(s.brandColor) ? s.brandColor : '#2563EB',
    logo: typeof s.logo === 'string' ? s.logo : '',
    footerText: typeof s.footerText === 'string' ? s.footerText : '',
    specAxes: [0, 1, 2].map(i => (typeof axes[i] === 'string' && axes[i].trim() ? axes[i].trim() : DEFAULT_AXES[i])),
    chartEnabled: s.specChart?.enabled !== false,
    chartTitle: typeof s.specChart?.title === 'string' && s.specChart.title.trim() ? s.specChart.title.trim() : '规格说明',
    reviewRequired: s.reviewRequired !== false
  }
}
function save() { run(async () => { await callAdmin('system.save', { data: { shopName: config.value.shopName, servicePhone: config.value.servicePhone, serviceHours: config.value.serviceHours, notifyEmail: config.value.notifyEmail } }); await load(); notice.value = '系统设置已保存，未发送提醒邮件' }) }
function saveShop() {
  run(async () => {
    const s = shop.value
    if (s.brandWord.length > 40) throw new Error('品牌字须为 40 字以内')
    if (!/^#[0-9a-fA-F]{6}$/.test(s.brandColor)) throw new Error('主色须为 #RRGGBB 形态，例如 #2563EB')
    if (s.logo.length > 1200) throw new Error('Logo 地址过长')
    if (s.logo && !/^https:\/\//.test(s.logo.trim()) && !s.logo.trim().startsWith('/static/')) throw new Error('Logo 须为 HTTPS 地址或站内图片')
    if (s.footerText.length > 200) throw new Error('页脚文字须为 200 字以内')
    if (!s.chartTitle.trim() || s.chartTitle.trim().length > 20) throw new Error('规格说明标题须为 1–20 字')
    const specAxes = s.specAxes.map((a, i) => (a.trim() || DEFAULT_AXES[i]))
    for (const a of specAxes) if (a.length > 10) throw new Error('规格轴名须为 1–10 字')
    await callAdmin('system.shopConfig', { data: { brandWord: s.brandWord.trim(), brandColor: s.brandColor, logo: s.logo.trim(), footerText: s.footerText.trim(), specAxes, specChart: { enabled: s.chartEnabled, title: s.chartTitle.trim() }, reviewRequired: s.reviewRequired } })
    await load(); notice.value = '店铺配置已保存'
  })
}
function uploadLogo(event: Event) {
  const input = event.target as HTMLInputElement, file = input.files?.[0]
  if (!file) return
  if (file.size > 2097152) { error.value = '图片限2MB，请先压缩'; return }
  run(async () => { const r = await uploadAdminFile<{ url: string }>(file, { purpose: 'image' }); shop.value.logo = r.url; notice.value = 'Logo 已上传云存储' })
  input.value = ''
}
onMounted(() => run(load))
</script>
<template><section class="content system-manager"><div class="section-heading"><div><p class="eyebrow">STORE SETTINGS</p><h1>系统设置</h1></div><ElButton @click="run(load)" :loading="busy">刷新系统设置</ElButton></div><ElAlert v-if="error" :title="error" type="error" :closable="false"/><ElAlert v-if="notice" :title="notice" type="success" :closable="false"/><form class="admin-form settings-card" @submit.prevent="save"><label>店名<input v-model="config.shopName" aria-label="系统店名" required maxlength="120" :disabled="busy"/></label><label>客服电话<input v-model="config.servicePhone" aria-label="客服电话" maxlength="40" :disabled="busy"/></label><label>客服时间<input v-model="config.serviceHours" aria-label="客服时间" maxlength="120" required :disabled="busy"/></label><label>订单提醒邮箱<input v-model="config.notifyEmail" aria-label="订单提醒邮箱" type="email" maxlength="254" placeholder="选填" :disabled="busy"/></label><p class="muted">此处只保存收件邮箱；订单/退款即时提醒属于独立自动化模块，当前未接线、不发送邮件。</p><ElButton native-type="submit" type="primary" :loading="busy">保存系统设置</ElButton></form>
<form class="admin-form settings-card" @submit.prevent="saveShop"><h3>店铺配置</h3><div class="settings-grid"><label>品牌字<input v-model="shop.brandWord" aria-label="品牌字" maxlength="40" placeholder="显示在店招与后台字标" :disabled="busy"/></label><label>主色<span class="color-row"><input v-model="shop.brandColor" aria-label="主色选择器" type="color"/><input v-model="shop.brandColor" aria-label="主色十六进制" maxlength="7" placeholder="#2563EB" :disabled="busy"/></span></label><label>Logo 地址<input v-model="shop.logo" aria-label="Logo 地址" maxlength="1200" placeholder="https://...（可粘贴地址，或上传本地图）" :disabled="busy"/></label><label>上传 Logo<input type="file" accept="image/png,image/jpeg,image/webp" aria-label="上传 Logo" :disabled="busy" @change="uploadLogo"/><span class="field-hint">单张≤2MB，HTTPS 云存储地址或站内图片。</span></label></div><img v-if="shop.logo" :src="shop.logo" alt="" class="logo-preview"/><label>页脚文字<textarea v-model="shop.footerText" aria-label="页脚文字" rows="2" maxlength="200" :disabled="busy"/></label><div class="settings-grid three"><label v-for="(ax, i) in shop.specAxes" :key="i">规格轴名 {{i + 1}}<input v-model="shop.specAxes[i]" :aria-label="'规格轴名'+(i+1)" maxlength="10" :placeholder="DEFAULT_AXES[i]" :disabled="busy"/></label></div><p class="muted">轴名留空时用默认轴名（规格一／规格二／规格三）；单个商品可在商品编辑里再改自己的轴名。</p><div class="settings-grid"><label class="checkbox-label"><input v-model="shop.chartEnabled" type="checkbox" aria-label="启用规格说明"/>启用规格说明展示</label><label>规格说明标题<input v-model="shop.chartTitle" aria-label="规格说明标题" maxlength="20" required :disabled="busy"/></label></div><label class="checkbox-label"><input v-model="shop.reviewRequired" type="checkbox" aria-label="商品审核开关"/>商品上新须审核（三段闸）</label><p class="muted">关闭后，商品完成上新时直接通过审核，不再进入待审核区。</p><ElButton native-type="submit" type="primary" :loading="busy">保存店铺配置</ElButton></form>
<div class="settings-card system-placeholders"><h3>短信与支付预留</h3><label>短信开关<input aria-label="短信占位开关" type="checkbox" disabled :checked="config.smsEnabled"/></label><label>短信密钥参数位<input value="未接入 · 仅占位" aria-label="短信参数占位" disabled/></label><label>微信支付参数位<input value="未接入 · 仅占位" aria-label="支付参数占位" disabled/></label><p class="muted">真实支付与短信关闭。参数位不可录入或启用，后台不读取、显示或保存任何密钥。</p></div></section></template>
<style>
.settings-card{padding:24px;background:white;border:1px solid #e4e9f1;border-radius:8px;margin:20px 0}.settings-card h3{font-size:17px;margin-top:0}.admin-form{display:grid;gap:18px}.admin-form label{display:flex;flex-direction:column;gap:7px;font-size:13px;color:#3d4658}.admin-form input,.admin-form textarea{width:100%;min-width:0;border:1px solid #dce2ec;border-radius:6px;padding:10px;font:inherit;color:#141414;background:white}.admin-form .checkbox-label{flex-direction:row;align-items:center}.checkbox-label input{width:auto}.settings-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px}.settings-grid.three{grid-template-columns:repeat(3,minmax(0,1fr))}.color-row{display:flex;gap:8px;align-items:center}.color-row input[type=color]{width:52px;height:40px;padding:2px;cursor:pointer}.field-hint{font-size:12px;color:#677185}.logo-preview{max-width:200px;max-height:80px;object-fit:contain;background:#f3f5f9;border-radius:6px}.system-placeholders{display:grid;gap:16px}.system-placeholders label{display:grid;gap:8px;font-size:13px}.system-placeholders input:not([type=checkbox]){padding:12px;border:1px solid #dce2ec;border-radius:6px;background:#f3f5f9;font:inherit;width:100%}@media(max-width:768px){.system-manager .section-heading{flex-wrap:wrap;gap:12px}.system-manager .section-heading h1{font-size:26px}.settings-grid,.settings-grid.three{grid-template-columns:1fr}.settings-card{padding:16px}}
</style>
