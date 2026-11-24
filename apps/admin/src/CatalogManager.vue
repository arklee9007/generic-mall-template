<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { ElButton, ElDialog, ElAlert } from 'element-plus'
import { callAdmin, uploadAdminFile } from './api'
interface SpecChart { columns: string[]; rows: string[][] }
interface Product { _id: string; name: string; categoryId: string; images: string[]; detailImages: string[]; desc: string; subtitle?: string; keywords?: string[]; colors: string[]; sizes: string[]; patterns: string[]; specLabels?: string[]; specChart?: unknown; sizeChart?: unknown; price: number; freightMode: string; freightTemplateId: string | null; stage: string; reviewStatus: string; reviewReason: string; onShelf: boolean }
interface Sku { _id?: string; productId?: string; color: string; size: string; pattern: string; stock: number; reserved?: number; delta?: number }
interface Category { _id: string; name: string; parentId: string | null; sort: number; visible: boolean }
interface Freight { _id: string; name: string }
interface ShopConfig { specAxes?: string[]; specChart?: { enabled?: boolean; title?: string }; reviewRequired?: boolean }
const DEFAULT_AXES = ['规格一', '规格二', '规格三']
const products = ref<Product[]>([]), skus = ref<Sku[]>([]), categories = ref<Category[]>([]), freight = ref<Freight[]>([]), shopConfig = ref<ShopConfig>({})
const busy = ref(false), error = ref(''), notice = ref(''), stage = ref('pool'), query = ref(''), categoryFilter = ref(''), editor = ref(false), categoryOpen = ref(false), rejectId = ref(''), rejectReason = ref('')
const activeTab = ref('on')
const form = ref({ _id: '', name: '', categoryId: '', images: '', detailImages: '', desc: '', subtitle: '', keywords: '', axisNames: ['', '', ''], axisValues: ['', '', ''], price: 0, freightMode: 'template', freightTemplateId: '', skus: [] as Sku[] })
const chart = ref<SpecChart>({ columns: [], rows: [] })
const category = ref({ _id: '', name: '', parentId: '', sort: 0, visible: true })
const split = (v: string) => v.split(/[,，\n]/).map(s => s.trim()).filter(Boolean)
const globalAxisName = (i: number) => shopConfig.value.specAxes?.[i]?.trim() || DEFAULT_AXES[i]
const resolveAxisName = (i: number, labels?: string[]) => (labels?.[i]?.trim()) || globalAxisName(i)
const chartTitle = computed(() => shopConfig.value.specChart?.title?.trim() || '规格说明')
const chartEnabled = computed(() => shopConfig.value.specChart?.enabled !== false)
function chartOf(p: Product): SpecChart {
  for (const cand of [p.specChart, p.sizeChart]) {
    if (cand && typeof cand === 'object' && !Array.isArray(cand)) {
      const o = cand as { columns?: unknown; rows?: unknown }
      if (Array.isArray(o.columns) && Array.isArray(o.rows)) {
        return { columns: o.columns.map(String), rows: o.rows.map(r => Array.isArray(r) ? r.map(String) : []) }
      }
    }
  }
  return { columns: [], rows: [] }
}
function normalizeChart() {
  const n = chart.value.columns.length
  chart.value.rows = chart.value.rows.map(r => Array.from({ length: n }, (_, i) => r[i] || ''))
}
function axisSummary(p: Product) {
  const axes = [p.colors, p.sizes, p.patterns]
  const parts = axes.map((list, i) => list.length ? resolveAxisName(i, p.specLabels) + ' ' + list.length + ' 个' : '').filter(Boolean)
  return parts.length ? parts.join(' · ') : '无规格'
}
const list = computed(() => products.value.filter(p => (stage.value === 'pool' ? p.stage === 'pool' : stage.value === 'pending' ? p.stage === 'shelf' && p.reviewStatus === 'pending' : p.stage === 'shelf' && p.reviewStatus === 'approved') && p.name.includes(query.value) && (!categoryFilter.value || p.categoryId === categoryFilter.value || categories.value.find(c => c._id === p.categoryId)?.parentId === categoryFilter.value)))
const displayList = computed(() => stage.value === 'active' ? list.value.filter(p => activeTab.value === 'on' ? p.onShelf : !p.onShelf) : list.value)
const onCount = computed(() => list.value.filter(p => p.onShelf).length), offCount = computed(() => list.value.filter(p => !p.onShelf).length)
async function run(fn: () => Promise<void>) { busy.value = true; error.value = ''; notice.value = ''; try { await fn() } catch (e) { error.value = e instanceof Error ? e.message : '操作失败' } finally { busy.value = false } }
async function load() {
  const r = await callAdmin<{ products: Product[]; skus: Sku[]; categories: Category[]; freight: Freight[]; shopConfig: ShopConfig }>('catalog.list')
  products.value = r.products; skus.value = r.skus.map(s => ({ ...s, stock: Number(s.stock), reserved: Number(s.reserved), delta: 0 })); categories.value = r.categories; freight.value = r.freight; shopConfig.value = r.shopConfig || {}
}
function open(p?: Product) {
  error.value = ''
  if (p) {
    form.value = { _id: p._id, name: p.name, categoryId: p.categoryId, images: p.images.join('\n'), detailImages: p.detailImages.join('\n'), desc: p.desc, subtitle: p.subtitle || '', keywords: (p.keywords || []).join('，'), axisNames: [0, 1, 2].map(i => p.specLabels?.[i] || ''), axisValues: [p.colors.join('，'), p.sizes.join('，'), p.patterns.join('，')], price: Number(p.price) / 100, freightMode: p.freightMode, freightTemplateId: p.freightTemplateId || '', skus: skus.value.filter(s => s.productId === p._id).map(s => ({ ...s })) }
    chart.value = chartOf(p); normalizeChart()
  } else {
    form.value = { _id: '', name: '', categoryId: categories.value[0]?._id || '', images: '', detailImages: '', desc: '', subtitle: '', keywords: '', axisNames: ['', '', ''], axisValues: ['', '', ''], price: 0, freightMode: 'template', freightTemplateId: freight.value[0]?._id || '', skus: [] }
    chart.value = { columns: [], rows: [] }
    generate()
  }
  editor.value = true
}
function generate() {
  const lists = form.value.axisValues.map(v => { const items = split(v); return items.length ? items : [''] })
  const next: Sku[] = []
  for (const color of lists[0]) for (const size of lists[1]) for (const pattern of lists[2]) {
    if (next.length >= 400) { error.value = '最多400个规格组合'; return }
    const old = form.value.skus.find(s => s.color === color && s.size === size && s.pattern === pattern)
    next.push(old ? { ...old } : { color, size, pattern, stock: 0, delta: 0 })
  }
  form.value.skus = next
}
function addColumn() {
  if (chart.value.columns.length >= 8) { error.value = '规格说明表最多 8 列'; return }
  chart.value.columns.push(''); normalizeChart()
}
function removeColumn(i: number) { chart.value.columns.splice(i, 1); normalizeChart() }
function addRow() {
  if (chart.value.rows.length >= 50) { error.value = '规格说明表最多 50 行'; return }
  chart.value.rows.push(Array.from({ length: chart.value.columns.length }, () => ''))
}
function removeRow(i: number) { chart.value.rows.splice(i, 1) }
function chartPayload(): SpecChart | [] {
  const raw = chart.value.columns.map(c => c.trim())
  if (raw.every(c => !c)) return []
  if (raw.some(c => !c)) throw new Error('规格说明表列名不可留空，不用的列请删掉')
  if (raw.length > 8) throw new Error('规格说明表最多 8 列')
  for (const c of raw) if (c.length > 20) throw new Error('规格说明表列名至多 20 字')
  if (chart.value.rows.length > 50) throw new Error('规格说明表最多 50 行')
  const rows = chart.value.rows.map(r => raw.map((_, i) => (r[i] || '').trim()))
  for (const r of rows) for (const cell of r) if (cell.length > 40) throw new Error('规格说明表单元格至多 40 字')
  return { columns: raw, rows }
}
function save() {
  run(async () => {
    const keywords = split(form.value.keywords)
    if (keywords.length > 20) throw new Error('关键词最多 20 个')
    for (const k of keywords) if (k.length > 40) throw new Error('关键词每个至多 40 字')
    const axes = form.value.axisValues.map(split)
    for (const list of axes) if (list.length > 20) throw new Error('每个规格轴最多 20 个值')
    for (const name of form.value.axisNames) if (name.trim().length > 10) throw new Error('轴名至多 10 字')
    const specChart = chartPayload()
    await callAdmin('catalog.save', {
      id: form.value._id || undefined,
      data: { name: form.value.name, categoryId: form.value.categoryId, images: form.value.images.split('\n').map(s => s.trim()).filter(Boolean), detailImages: form.value.detailImages.split('\n').map(s => s.trim()).filter(Boolean), desc: form.value.desc, subtitle: form.value.subtitle, keywords, colors: axes[0], sizes: axes[1], patterns: axes[2], specLabels: form.value.axisNames.map(a => a.trim()), specChart, price: Math.round(form.value.price * 100), freightMode: form.value.freightMode, freightTemplateId: form.value.freightTemplateId, skus: form.value.skus.map(s => ({ color: s.color, size: s.size, pattern: s.pattern, stock: Math.max(0, Math.trunc(Number(s.stock) || 0)) })) }
    })
    editor.value = false; stage.value = 'pool'; await load(); notice.value = '已保存到上新池；编辑已激活商品后须重新审核'
  })
}
function action(op: string, p: Product, data: Record<string, unknown> = {}) {
  run(async () => {
    await callAdmin('catalog.' + op, { id: p._id, data }); await load()
    notice.value = op === 'complete' ? (shopConfig.value.reviewRequired === false ? '已完成上新并直接通过审核' : '已提交审核，请在货架待审核区处理') : '操作已保存并留痕'
  })
}
function adjust(s: Sku) { run(async () => { await callAdmin('catalog.stock', { id: form.value._id, data: { skuId: s._id, delta: s.delta } }); await load(); const updated = skus.value.find(row => row._id === s._id); if (updated) Object.assign(s, updated); notice.value = '库存调整已保存' }) }
function upload(event: Event, detail = false) {
  const input = event.target as HTMLInputElement, file = input.files?.[0]
  if (!file) return
  if (file.size > 2097152) { error.value = '图片限2MB，请先压缩'; return }
  run(async () => { const r = await uploadAdminFile<{ url: string }>(file, { purpose: 'image' }); const field = detail ? 'detailImages' : 'images'; form.value[field] += (form.value[field] ? '\n' : '') + r.url; notice.value = '图片已上传云存储' })
}
function categorySave() { run(async () => { await callAdmin('catalog.category.save', { id: category.value._id || undefined, data: category.value }); await load(); category.value = { _id: '', name: '', parentId: '', sort: 0, visible: true }; notice.value = '分类已保存' }) }
function categoryDelete(c: Category) { if (confirm('删除分类“' + c.name + '”？有商品或子分类时会被服务端拒绝。')) run(async () => { await callAdmin('catalog.category.delete', { id: c._id }); await load() }) }
async function clearDemo() {
  if (!confirm('清空全部演示数据？会删除所有 demo- 前缀的商品、分类、轮播、公告与 FAQ（被商家商品引用的演示分类会保留）。')) return
  if (!confirm('再次确认：演示数据删除后不可恢复，确定清空吗？')) return
  busy.value = true; error.value = ''; notice.value = ''
  try {
    await callAdmin('catalog.clearDemo')
    await load(); notice.value = '演示数据已清空'
  } catch (e) {
    const msg = e instanceof Error ? e.message : '操作失败'
    error.value = msg.includes('DEMO_IN_USE') ? '演示商品已有订单或购物车引用，无法清空（DEMO_IN_USE），请先处理相关订单与购物车后再试。' : msg
  } finally { busy.value = false }
}
onMounted(() => run(load))
</script>
<template><section class="content catalog-manager"><div class="section-heading"><div><p class="eyebrow">PRODUCT OPERATIONS</p><h1>商品管理</h1></div><div class="action-row"><ElButton @click="categoryOpen=true">分类管理</ElButton><ElButton type="danger" @click="clearDemo">清空演示数据</ElButton><ElButton type="primary" @click="open()">新增商品</ElButton></div></div>
<ElAlert v-if="error" :title="error" type="error" :closable="false"/><ElAlert v-if="notice" :title="notice" type="success" :closable="false"/>
<div class="catalog-toolbar"><div class="tab-row"><button v-for="tab in [{key:'pool',name:'上新池'},{key:'pending',name:'货架待审核'},{key:'active',name:'已激活'}]" :key="tab.key" :class="{active:stage===tab.key}" @click="stage=tab.key">{{tab.name}}</button></div><input v-model="query" aria-label="搜索商品" placeholder="搜索商品名称"/><select v-model="categoryFilter" aria-label="按大类筛选" class="category-filter"><option value="">全部大类</option><option v-for="c in categories.filter(c=>!c.parentId)" :key="c._id" :value="c._id">{{c.name}}</option></select><ElButton @click="run(load)" :loading="busy">刷新</ElButton></div>
<template v-if="stage==='active'"><div class="tab-row sub-tabs"><button :class="{active:activeTab==='on'}" @click="activeTab='on'">已上架（{{onCount}}）</button><button :class="{active:activeTab==='off'}" @click="activeTab='off'">未上架（{{offCount}}）</button></div></template>
<p v-if="!displayList.length" class="empty-state">当前分区暂无商品</p><div class="product-grid"><template v-for="p in displayList" :key="p._id"><article class="product-card" :data-product-id="p._id"><img :src="p.images[0]" :alt="p.name"/><div class="product-copy"><h2>{{p.name}}</h2><p v-if="p.subtitle">{{p.subtitle}}</p><p>¥{{(Number(p.price)/100).toFixed(2)}} · {{categories.find(c=>c._id===p.categoryId)?.name}}</p><p>{{axisSummary(p)}} · {{p.onShelf?'已上架':'未上架'}}</p><p v-if="p.reviewReason">打回原因：{{p.reviewReason}}</p><div class="action-row"><ElButton @click="open(p)">编辑</ElButton><ElButton v-if="p.stage==='pool'" @click="action('complete',p)">完成上新</ElButton><template v-if="p.stage==='shelf'&&p.reviewStatus==='pending'"><ElButton type="primary" @click="action('approve',p)">审核通过</ElButton><ElButton @click="rejectId=p._id;rejectReason=''">打回</ElButton></template><ElButton v-if="p.stage==='shelf'&&p.reviewStatus==='approved'" type="primary" @click="action('shelf',p,{onShelf:!p.onShelf})">{{p.onShelf?'下架':'上架'}}</ElButton></div></div></article></template></div>
<ElDialog v-model="editor" title="商品资料" width="min(960px, calc(100vw - 24px))" :close-on-click-modal="false"><ElAlert v-if="error" :title="error" type="error" :closable="false"/><ElAlert v-if="notice" :title="notice" type="success" :closable="false"/><form class="admin-form" @submit.prevent="save"><div class="form-grid"><label>商品名称<input v-model="form.name" aria-label="商品名称" required maxlength="120"/></label><label>分类<select v-model="form.categoryId" aria-label="商品分类" required><option v-for="c in categories" :key="c._id" :value="c._id">{{c.parentId?'　└ ':''}}{{c.name}}</option></select></label><label>价格（元）<input v-model.number="form.price" aria-label="商品价格" type="number" min="0" step="0.01" required/></label><label>运费方式<select v-model="form.freightMode" aria-label="商品运费方式"><option value="template">套用模板</option><option value="free">包邮</option></select></label><label v-if="form.freightMode==='template'">运费模板<select v-model="form.freightTemplateId" aria-label="商品运费模板"><option v-for="f in freight" :key="f._id" :value="f._id">{{f.name}}</option></select></label></div>
<label>副标题<input v-model="form.subtitle" aria-label="商品副标题" maxlength="120" placeholder="显示在商品名下方，可不填"/></label><label>关键词（逗号分隔）<input v-model="form.keywords" aria-label="商品关键词" placeholder="如：保温，礼盒"/><span class="field-hint">最多 20 个，每个至多 40 字，用于店内搜索。</span></label>
<label>描述<textarea v-model="form.desc" aria-label="商品描述" rows="3"/></label><div class="form-grid"><label>主图（HTTPS地址，每行一张）<textarea v-model="form.images" aria-label="商品主图" rows="3" required/><input type="file" accept="image/png,image/jpeg,image/webp" aria-label="上传商品主图" @change="upload($event)"/><span class="field-hint">规格：1:1 方图，建议 1080×1080，单张≤2MB</span></label><label>详情图（每行一张）<textarea v-model="form.detailImages" aria-label="商品详情图" rows="3"/><input type="file" accept="image/png,image/jpeg,image/webp" aria-label="上传商品详情图" @change="upload($event,true)"/><span class="field-hint">规格：宽 1080，高≤8000，单张≤2MB</span></label></div>
<h3 class="group-title">规格（0–3 维）</h3><p class="muted">轴名留空时用店铺配置里的轴名；某轴不填规格值表示商品不用此轴。三个轴都留空就是无规格商品，只有一个规格组合。</p><div v-for="ai in [0,1,2]" :key="ai" class="axis-block"><label>轴 {{ai+1}} 名称<input v-model="form.axisNames[ai]" :aria-label="'规格轴'+(ai+1)+'名称'" maxlength="10" :placeholder="globalAxisName(ai)"/></label><label>{{resolveAxisName(ai, form.axisNames)}}（逗号分隔，留空表示不用此轴）<input v-model="form.axisValues[ai]" :aria-label="'规格轴'+(ai+1)+'规格值'" placeholder="如：红色，蓝色"/><span class="field-hint">最多 20 个值，不可重复。</span></label></div><ElButton @click="generate">生成规格组合</ElButton><p class="muted">新规格填写初始库存；已存在规格用增减量调整，避免覆盖销售中的库存。</p><div class="sku-scroll"><table><thead><tr><th>{{resolveAxisName(0, form.axisNames)}}</th><th>{{resolveAxisName(1, form.axisNames)}}</th><th>{{resolveAxisName(2, form.axisNames)}}</th><th>库存</th><th>预占</th><th>调整增减量</th></tr></thead><tbody><tr v-for="(s,index) in form.skus" :key="s.color+'|'+s.size+'|'+s.pattern"><td>{{s.color||'—'}}</td><td>{{s.size||'—'}}</td><td>{{s.pattern||'—'}}</td><td><input v-model.number="s.stock" :aria-label="'规格库存'+index" type="number" min="0" :readonly="!!s._id"/></td><td>{{s.reserved||0}}</td><td><div v-if="s._id" class="action-row"><input v-model.number="s.delta" :aria-label="'库存调整'+index" type="number"/><ElButton @click="adjust(s)">调整</ElButton></div><span v-else>保存后可调整</span></td></tr></tbody></table></div>
<h3 class="group-title">{{chartTitle}}</h3><p v-if="!chartEnabled" class="muted">店铺配置里已关闭规格说明展示，填了也不会在顾客端显示。</p><div class="chart-editor"><div class="chart-columns"><div v-for="(col,ci) in chart.columns" :key="ci" class="chart-col-head"><input v-model="chart.columns[ci]" :aria-label="'规格表列名'+(ci+1)" maxlength="20" placeholder="列名"/><ElButton @click="removeColumn(ci)">删列</ElButton></div><ElButton :disabled="chart.columns.length>=8" @click="addColumn">添加列</ElButton></div><p v-if="!chart.columns.length" class="muted">还没有列：点「添加列」开始填规格说明表；不填表示没有规格说明表。</p><div v-if="chart.columns.length" class="sku-scroll"><table class="chart-grid"><thead><tr><th v-for="(col,ci) in chart.columns" :key="ci">{{col||'列 '+(ci+1)}}</th><th>操作</th></tr></thead><tbody><tr v-for="(row,ri) in chart.rows" :key="ri"><td v-for="(cell,ci) in chart.columns" :key="ci"><input v-model="chart.rows[ri][ci]" :aria-label="'规格表第'+(ri+1)+'行第'+(ci+1)+'列'" maxlength="40"/></td><td><ElButton @click="removeRow(ri)">删除行</ElButton></td></tr></tbody></table></div><div v-if="chart.columns.length" class="action-row"><ElButton :disabled="chart.rows.length>=50" @click="addRow">添加行</ElButton></div><p class="muted">最多 8 列、50 行，单元格至多 40 字。</p></div>
<div class="form-footer"><ElButton @click="editor=false">取消</ElButton><ElButton type="primary" native-type="submit" :loading="busy">保存商品</ElButton></div></form></ElDialog>
<ElDialog :model-value="!!rejectId" @update:model-value="rejectId=''" title="打回上新池" width="min(440px, calc(100vw - 24px))"><form class="admin-form" @submit.prevent="run(async()=>{await callAdmin('catalog.reject',{id:rejectId,data:{reason:rejectReason}});rejectId='';await load()})"><label>打回原因<textarea v-model="rejectReason" aria-label="打回原因" required/></label><ElButton type="primary" native-type="submit" :loading="busy">确认打回</ElButton></form></ElDialog>
<ElDialog v-model="categoryOpen" title="分类管理" width="min(720px, calc(100vw - 24px))"><ElAlert v-if="error" :title="error" type="error" :closable="false"/><div v-for="c in categories" :key="c._id" class="category-row"><span>{{c.parentId?'└ ':''}}{{c.name}} · {{c.visible?'显示':'隐藏'}} · {{c.sort}}</span><div class="action-row"><ElButton @click="category={...c,parentId:c.parentId||''}">编辑</ElButton><ElButton @click="categoryDelete(c)">删除</ElButton></div></div><form class="admin-form" @submit.prevent="categorySave"><h3>{{category._id?'编辑分类':'新增分类'}}</h3><label>分类名称<input v-model="category.name" aria-label="分类名称" required/></label><label>上级分类<select v-model="category.parentId" aria-label="上级分类"><option value="">一级分类</option><option v-for="c in categories.filter(c=>c._id!==category._id)" :value="c._id" :key="c._id">{{c.name}}</option></select></label><label>排序<input v-model.number="category.sort" type="number" min="0" aria-label="分类排序"/></label><label class="checkbox-label"><input v-model="category.visible" type="checkbox" aria-label="分类显示"/>显示</label><ElButton type="primary" native-type="submit" :loading="busy">保存分类</ElButton></form></ElDialog>
</section></template>
<style>
.admin-form{display:grid;gap:18px}.admin-form label{display:flex;flex-direction:column;gap:7px;font-size:13px;color:#3d4658}.admin-form input,.admin-form select,.admin-form textarea,.catalog-toolbar input,.catalog-toolbar select{width:100%;min-width:0;border:1px solid #dce2ec;border-radius:6px;padding:10px;font:inherit;color:#141414;background:white}.catalog-toolbar select{width:160px}.group-title{font-size:15px;color:#3d4658;margin:10px 0 0}.field-hint{font-size:12px;color:#677185}.admin-form textarea{resize:vertical}.form-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}.form-grid.three{grid-template-columns:repeat(3,minmax(0,1fr))}.admin-form .checkbox-label{flex-direction:row;align-items:center}.checkbox-label input{width:auto}.action-row,.form-footer{display:flex;flex-wrap:wrap;gap:8px;align-items:center}.action-row .el-button+.el-button{margin-left:0}.form-footer{justify-content:flex-end;margin-top:16px}.catalog-toolbar{display:flex;gap:16px;align-items:center;flex-wrap:wrap;margin:24px 0}.catalog-toolbar input{width:220px}.tab-row{display:flex;gap:4px}.tab-row button{padding:10px 12px;border:0;border-radius:6px;cursor:pointer;background:white;color:#596274}.tab-row button.active{color:white;background:var(--brand-blue)}.product-grid{display:grid;gap:16px}.product-card{display:flex;gap:20px;background:white;padding:20px;border:1px solid #e4e9f1;border-radius:8px;min-width:0}.product-card img{width:120px;height:140px;object-fit:cover;background:#edf1f7;border-radius:4px}.product-copy{min-width:0}.product-copy h2{font-size:18px;margin:2px 0 10px}.product-copy p{font-size:13px;color:#596274;line-height:1.7;overflow-wrap:anywhere}.empty-state{padding:40px;background:white;color:#677185}.sku-scroll{overflow-x:auto;max-width:100%;border:1px solid #e4e9f1}.sku-scroll table{border-collapse:collapse;min-width:680px;width:100%;font-size:13px}.sku-scroll td,.sku-scroll th{padding:10px;border-bottom:1px solid #e4e9f1;text-align:left}.sku-scroll input{max-width:100px}.category-row{display:flex;justify-content:space-between;gap:8px;align-items:center;border-bottom:1px solid #edf1f6;padding:12px 0}.catalog-manager .el-dialog__body{overflow-wrap:anywhere}.sub-tabs{margin-bottom:16px}.axis-block{display:grid;grid-template-columns:200px 1fr;gap:16px}.chart-editor{display:grid;gap:12px}.chart-columns{display:flex;flex-wrap:wrap;gap:8px;align-items:flex-end}.chart-col-head{display:flex;gap:6px;align-items:center}.chart-col-head input{width:130px}.chart-grid td input{max-width:none;width:100%}@media(max-width:768px){.form-grid,.form-grid.three,.axis-block{grid-template-columns:1fr}.catalog-manager .section-heading{align-items:flex-start;gap:12px;flex-direction:column}.product-card{padding:16px;gap:12px}.product-card img{width:70px;height:90px}.product-copy{flex:1}.catalog-toolbar{gap:10px}.catalog-toolbar input{flex:1;width:100%}.tab-row{width:100%}.category-row{flex-wrap:wrap}}
</style>
