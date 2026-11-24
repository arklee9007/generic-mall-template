<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { ElButton, ElAlert } from 'element-plus'
import { callAdmin, uploadAdminFile } from './api'
interface Tier { _id?: string; level: number; name: string; threshold: number; discountBps: number; cardBg: string; cardText: string; sort: number; enabled: boolean }
interface Pkg { label: string; amount: number; bonus: number }
const busy = ref(false), error = ref(''), notice = ref('')
const tiers = ref<Tier[]>([])
const enabled = ref(true), rechargeEnabled = ref(true)
const packages = ref<Pkg[]>([])
const editing = ref(false), editingExisting = ref(false)
const form = ref({ level: 1, name: '', thresholdYuan: 0, discountZhe: 10, cardBg: '', cardText: '', sort: 0, enabled: true })
const zheOf = (bps: number) => (Number(bps) / 1000).toString().replace(/\.0+$/, '').replace(/(\.\d)0$/, '$1')
async function run(fn: () => Promise<void>) { if (busy.value) return; busy.value = true; error.value = ''; notice.value = ''; try { await fn() } catch (e) { error.value = e instanceof Error ? e.message : '操作失败' } finally { busy.value = false } }
async function load() {
  const r = await callAdmin<{ tiers: Tier[]; config: { enabled: boolean; rechargeEnabled: boolean; packages: Pkg[] } }>('membership.list')
  tiers.value = (r.tiers || []).slice().sort((a, b) => Number(a.level) - Number(b.level))
  enabled.value = r.config.enabled; rechargeEnabled.value = r.config.rechargeEnabled
  packages.value = (r.config.packages || []).map(p => ({ label: p.label, amount: Number(p.amount), bonus: Number(p.bonus) }))
}
function pkgYuan(p: Pkg, key: 'amount' | 'bonus') { return (Number(p[key]) / 100).toFixed(2) }
function setPkgYuan(p: Pkg, key: 'amount' | 'bonus', raw: string) { const v = Number(raw); p[key] = Number.isFinite(v) ? Math.round(v * 100) : 0 }
function addPackage() {
  if (packages.value.length >= 20) { error.value = '充值套餐最多 20 个'; return }
  packages.value.push({ label: '', amount: 10000, bonus: 0 })
}
function saveConfig() {
  run(async () => {
    const seen = new Set<number>()
    for (const p of packages.value) {
      if (!p.label.trim() || p.label.trim().length > 40) throw new Error('套餐名称须为 1–40 字')
      if (!Number.isSafeInteger(p.amount) || p.amount < 100 || p.amount > 100000000) throw new Error('套餐金额须在 1 元到 100 万元之间')
      if (!Number.isSafeInteger(p.bonus) || p.bonus < 0 || p.bonus > p.amount) throw new Error('赠送金额不能超过充值金额')
      if (seen.has(p.amount)) throw new Error('充值套餐金额不可重复')
      seen.add(p.amount)
    }
    await callAdmin('membership.config.save', { data: { enabled: enabled.value, rechargeEnabled: rechargeEnabled.value, packages: packages.value.map(p => ({ label: p.label.trim(), amount: p.amount, bonus: p.bonus })) } })
    await load(); notice.value = '会员设置已保存'
  })
}
function newTier() {
  const used = new Set(tiers.value.map(t => Number(t.level)))
  let level = 1; while (used.has(level) && level < 20) level++
  form.value = { level, name: '', thresholdYuan: 0, discountZhe: 10, cardBg: '', cardText: '', sort: tiers.value.length, enabled: true }
  editingExisting.value = false; editing.value = true
}
function editTier(t: Tier) {
  form.value = { level: Number(t.level), name: t.name, thresholdYuan: Number(t.threshold) / 100, discountZhe: Number(t.discountBps) / 1000, cardBg: t.cardBg || '', cardText: t.cardText || '', sort: Number(t.sort) || 0, enabled: t.enabled !== false }
  editingExisting.value = true; editing.value = true
}
function saveTier() {
  run(async () => {
    const f = form.value
    const level = Number(f.level)
    if (!Number.isInteger(level) || level < 1 || level > 20) throw new Error('等级须为 1–20 的整数')
    if (!f.name.trim() || f.name.trim().length > 20) throw new Error('档位名称须为 1–20 字')
    const threshold = Math.round(Number(f.thresholdYuan) * 100)
    if (!Number.isSafeInteger(threshold) || threshold < 0) throw new Error('累计充值门槛不正确')
    const discountBps = Math.round(Number(f.discountZhe) * 1000)
    if (!Number.isInteger(discountBps) || discountBps < 1000 || discountBps > 10000) throw new Error('折扣须在 1–10 折之间')
    if (f.cardText.length > 200) throw new Error('卡面文字至多 200 字')
    const next = tiers.value.filter(t => Number(t.level) !== level).map(t => ({ level: Number(t.level), threshold: Number(t.threshold) }))
    next.push({ level, threshold }); next.sort((a, b) => a.level - b.level)
    for (let i = 1; i < next.length; i++) if (next[i].threshold <= next[i - 1].threshold) throw new Error('高等级的累计充值门槛须高于低等级')
    await callAdmin('membership.tier.save', { data: { level, name: f.name.trim(), threshold, discountBps, cardBg: f.cardBg.trim(), cardText: f.cardText.trim(), sort: Number(f.sort) || 0, enabled: f.enabled } })
    editing.value = false; await load(); notice.value = '档位已保存'
  })
}
function deleteTier(t: Tier) {
  if (!confirm('删除档位“' + t.name + '”（' + t.level + ' 级）？已有该等级的顾客不受影响，之后不再按此档定级。')) return
  run(async () => { await callAdmin('membership.tier.delete', { id: 'tier-' + Number(t.level) }); await load(); notice.value = '档位已删除' })
}
function uploadCardBg(event: Event) {
  const input = event.target as HTMLInputElement, file = input.files?.[0]
  if (!file) return
  if (file.size > 2097152) { error.value = '图片限2MB，请先压缩'; return }
  run(async () => { const r = await uploadAdminFile<{ url: string }>(file, { purpose: 'image' }); form.value.cardBg = r.url; notice.value = '会员卡背景图已上传云存储' })
  input.value = ''
}
onMounted(() => run(load))
</script>
<template><section class="content membership-manager"><div class="section-heading"><div><p class="eyebrow">MEMBERSHIP SETTINGS</p><h1>会员设置</h1></div><ElButton @click="run(load)" :loading="busy">刷新会员设置</ElButton></div><ElAlert v-if="error" :title="error" type="error" :closable="false"/><ElAlert v-if="notice" :title="notice" type="success" :closable="false"/>
<form class="admin-form settings-card" @submit.prevent="saveConfig"><h3>会员开关与充值套餐</h3><label class="checkbox-label"><input v-model="enabled" type="checkbox" aria-label="启用会员"/>启用会员（关闭后顾客端不再显示会员权益与等级折扣）</label><label class="checkbox-label"><input v-model="rechargeEnabled" type="checkbox" aria-label="启用充值"/>启用充值（关闭后顾客不能充值，余额照常使用）</label><h3>充值套餐</h3><p class="muted">金额 1 元起，赠送不能超过本金，金额不可重复，最多 20 个。顾客按套餐金额充值，赠送部分进余额但不计入累计充值实付。</p><div v-for="(p, i) in packages" :key="i" class="package-row"><label>套餐名称<input v-model="p.label" :aria-label="'套餐名称'+(i+1)" maxlength="40" required :disabled="busy"/></label><label>充值金额（元）<input :value="pkgYuan(p, 'amount')" :aria-label="'套餐金额'+(i+1)" type="number" min="1" max="1000000" step="0.01" required :disabled="busy" @input="setPkgYuan(p, 'amount', ($event.target as HTMLInputElement).value)"/></label><label>赠送（元）<input :value="pkgYuan(p, 'bonus')" :aria-label="'套餐赠送'+(i+1)" type="number" min="0" step="0.01" required :disabled="busy" @input="setPkgYuan(p, 'bonus', ($event.target as HTMLInputElement).value)"/></label><ElButton :disabled="busy" @click="packages.splice(i, 1)">删除</ElButton></div><div class="action-row"><ElButton :disabled="busy" @click="addPackage">新增套餐</ElButton><ElButton native-type="submit" type="primary" :loading="busy">保存会员设置</ElButton></div></form>
<section class="settings-card"><div class="section-heading"><h3>会员档位</h3><ElButton type="primary" @click="newTier">新增档位</ElButton></div><p class="muted">等级只按累计充值实付定级，只升不降，赠送不计入；高等级的门槛须高于低等级。等级 1–20，折扣 1–10 折（10 折为不打折）。</p><p v-if="!tiers.length" class="muted">暂无档位，请先新增一个档位，顾客充值后才能定级。</p><article v-for="t in tiers" :key="t.level" class="tier-row"><div><h3>{{t.level}} 级 · {{t.name}} · {{t.enabled?'启用':'停用'}}</h3><p>累计充值满 ¥{{(Number(t.threshold)/100).toFixed(2)}} · {{zheOf(t.discountBps)}} 折 · 排序 {{t.sort}}</p><p v-if="t.cardText" class="muted">{{t.cardText}}</p><img v-if="t.cardBg" :src="t.cardBg" alt="" class="card-preview"/></div><div class="action-row"><ElButton @click="editTier(t)">编辑</ElButton><ElButton @click="deleteTier(t)">删除</ElButton></div></article></section>
<form v-if="editing" class="admin-form settings-card" @submit.prevent="saveTier"><h3>{{editingExisting ? '编辑档位' : '新增档位'}}</h3><div class="settings-grid"><label>等级（1–20）<input v-model.number="form.level" aria-label="档位等级" type="number" min="1" max="20" step="1" required :disabled="busy || editingExisting"/><span class="field-hint">已建档位的等级不可改，改级请删了重建。</span></label><label>档位名称<input v-model="form.name" aria-label="档位名称" maxlength="20" required :disabled="busy"/></label><label>累计充值门槛（元）<input v-model.number="form.thresholdYuan" aria-label="档位门槛" type="number" min="0" step="0.01" required :disabled="busy"/></label><label>折扣（折）<input v-model.number="form.discountZhe" aria-label="档位折扣" type="number" min="1" max="10" step="0.1" required :disabled="busy"/></label><label>排序<input v-model.number="form.sort" aria-label="档位排序" type="number" min="0" :disabled="busy"/></label><label class="checkbox-label"><input v-model="form.enabled" type="checkbox" aria-label="启用档位"/>启用此档位</label></div><label>会员卡背景图地址<input v-model="form.cardBg" aria-label="会员卡背景图地址" maxlength="1200" placeholder="https://...（可粘贴地址，或上传本地图）" :disabled="busy"/></label><label>上传背景图<input type="file" accept="image/png,image/jpeg,image/webp" aria-label="上传会员卡背景图" :disabled="busy" @change="uploadCardBg"/><span class="field-hint">单张≤2MB，HTTPS 云存储地址或站内图片。</span></label><img v-if="form.cardBg" :src="form.cardBg" alt="" class="card-preview"/><label>卡面文字<textarea v-model="form.cardText" aria-label="卡面文字" rows="2" maxlength="200" :disabled="busy"/></label><div class="action-row"><ElButton native-type="submit" type="primary" :loading="busy">保存档位</ElButton><ElButton :disabled="busy" @click="editing=false">取消</ElButton></div></form>
</section></template>
<style>
.settings-card{padding:24px;background:white;border:1px solid #e4e9f1;border-radius:8px;margin:20px 0}.settings-card h3{font-size:17px;margin-top:0}.settings-card p{font-size:13px;line-height:1.8}.settings-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px}.settings-card label{min-width:0}.settings-card input,.settings-card select,.settings-card textarea{max-width:100%}.admin-form label{display:flex;flex-direction:column;gap:7px;font-size:13px;color:#3d4658}.admin-form input,.admin-form select,.admin-form textarea{width:100%;min-width:0;border:1px solid #dce2ec;border-radius:6px;padding:10px;font:inherit;color:#141414;background:white}.admin-form .checkbox-label{flex-direction:row;align-items:center}.checkbox-label input{width:auto}.field-hint{font-size:12px;color:#677185}.package-row{display:grid;grid-template-columns:2fr 1fr 1fr auto;gap:12px;align-items:end;margin-bottom:12px}.package-row label{display:grid;gap:8px;font-size:13px}.package-row input{padding:10px;border:1px solid #dce2ec;border-radius:6px;font:inherit;width:100%}.tier-row{display:flex;justify-content:space-between;gap:12px;align-items:flex-start;border-top:1px solid #edf1f6;padding:16px 0}.tier-row h3{margin:0 0 8px}.tier-row p{margin:4px 0}.card-preview{max-width:220px;max-height:120px;object-fit:cover;border-radius:6px;margin-top:8px;background:#edf1f7}.action-row{display:flex;flex-wrap:wrap;gap:8px;align-items:center}.action-row .el-button+.el-button{margin-left:0}@media(max-width:768px){.settings-grid{grid-template-columns:1fr}.settings-card{padding:16px}.membership-manager .section-heading{flex-wrap:wrap;gap:12px}.membership-manager .section-heading h1{font-size:26px}.package-row{grid-template-columns:1fr}.tier-row{flex-wrap:wrap}}
</style>
