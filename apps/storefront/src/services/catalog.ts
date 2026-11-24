import { computed, reactive } from 'vue'
import { callCloud } from './cloud'
import type { Product, Category, SpecChart } from '../data/demo'
export type { Product, Category, SpecChart } from '../data/demo'
export interface MemberPackage { amount: number; bonus: number; label: string }
export interface ShopTier { level: number; name: string; threshold: number; discountBps: number; cardBg: string; cardText: string }
interface CloudCategory { _id: string; name: string; parentId: string | null; sort: number }
interface CloudSku { _id: string; color: string; size: string; pattern: string; available: number }
interface CloudProduct { _id: string; name: string; subtitle: string; categoryId: string; keywords: string[]; price: number; images: string[]; detailImages: string[]; colors: string[]; sizes: string[]; patterns: string[]; specLabels: string[]; sizeChart: unknown; freightMode: string; skus: CloudSku[] }
interface CloudShopConfig { brandWord?: string; brandColor?: string; logo?: string; footerText?: string; specAxes?: unknown; specChart?: { enabled?: boolean; title?: string }; reviewRequired?: boolean; member?: { enabled?: boolean; rechargeEnabled?: boolean; packages?: unknown } }
interface CatalogReply { categories: CloudCategory[]; products: CloudProduct[]; settings: { shopName: string; servicePhone: string; serviceHours: string; notices: string[]; splashEnabled: boolean; splashImage: string; splashLink: string; splashSeconds: number; shopConfig?: CloudShopConfig }; tiers?: ShopTier[]; faqs: { _id: string; question: string; answer: string }[]; announcements: { _id: string; text: string }[]; banners: { _id: string; image: string }[] }
export const splashState = reactive({ visible: false })
export const products = reactive<Product[]>([]), categories = reactive<Category[]>([])
export const listedProducts = computed(() => products)
export const catalogStatus = reactive({ loading: false, ready: false, error: '' })
const DEFAULT_AXES = ['规格一', '规格二', '规格三']
export const shopConfig = reactive({ shopName: '我的店铺', brandWord: '', brandColor: '#2563EB', logo: '', footerText: '', specAxes: [...DEFAULT_AXES] as string[], specChart: { enabled: true, title: '规格说明' }, reviewRequired: true, member: { enabled: true, rechargeEnabled: true, packages: [] as MemberPackage[] }, tiers: [] as ShopTier[], paymentTimeoutMinutes: 30, notices: [] as string[], regions: ['普通地区', '新疆', '西藏', '青海', '宁夏', '甘肃', '内蒙古', '香港', '澳门', '台湾'], servicePhone: '', serviceHours: '', faqs: [] as { id: string; question: string; answer: string }[] })
export const homeData = reactive({ notices: [] as { id: string; text: string }[], slides: [] as { id: string; image: string; alt: string; caption: string }[], splash: { enabled: false, image: '', link: '', seconds: 5 } })
let splashClaimed = false
let lastFetchOkAt = 0
export function claimSplash() { if (splashClaimed) return false; splashClaimed = true; return true }
let rawCategories: CloudCategory[] = [], pending: Promise<void> | null = null
// 商品规格说明表在服务端以 sizeChart 列存储：对象 {columns, rows} 为有效表，空数组 [] 表示无表。
function normalizeSpecChart(value: unknown): SpecChart | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const v = value as { columns?: unknown; rows?: unknown }
  if (!Array.isArray(v.columns) || !Array.isArray(v.rows)) return null
  const columns = v.columns.filter((c): c is string => typeof c === 'string')
  const rows = v.rows.filter((r): r is unknown[] => Array.isArray(r)).map(r => r.map(cell => String(cell)))
  if (!columns.length || !rows.length) return null
  return { columns, rows }
}
function normalizeAxes(value: unknown): string[] {
  if (!Array.isArray(value)) return [...DEFAULT_AXES]
  return [0, 1, 2].map(i => typeof value[i] === 'string' ? value[i] : '')
}
function normalizePackages(value: unknown): MemberPackage[] {
  if (!Array.isArray(value)) return []
  return value.filter((p): p is MemberPackage => !!p && typeof p === 'object' && Number.isSafeInteger((p as MemberPackage).amount) && Number.isSafeInteger((p as MemberPackage).bonus)).map(p => ({ amount: p.amount, bonus: p.bonus, label: typeof p.label === 'string' ? p.label : '' }))
}
// 轴名三级回落：商品 specLabels[i]（非空）→ 全局 specAxes[i]（非空）→ 默认「规格一/规格二/规格三」。
export function axisLabel(product: Product, index: number): string {
  const own = product.specLabels?.[index]?.trim()
  if (own) return own
  const global = shopConfig.specAxes[index]?.trim()
  if (global) return global
  return DEFAULT_AXES[index] || '规格'
}
export function axisValues(product: Product, index: number): string[] {
  return [product.colors, product.sizes, product.patterns][index] || []
}
function mapProduct(p: CloudProduct): Product {
  const category = rawCategories.find(c => c._id === p.categoryId)
  return { id: p._id, name: p.name, subtitle: p.subtitle || '', category: category?.parentId || p.categoryId, subcategory: category?.parentId ? p.categoryId : '', keywords: p.keywords || [], price: p.price, image: p.images[0] || '', gallery: p.images || [], detail: p.detailImages[0] || '', detailImages: p.detailImages || [], colors: p.colors || [], sizes: p.sizes || [], patterns: p.patterns || [], specLabels: Array.isArray(p.specLabels) ? p.specLabels.slice(0, 3).map(v => typeof v === 'string' ? v : '') : [], specChart: normalizeSpecChart(p.sizeChart), freeShipping: p.freightMode === 'free', skus: (p.skus || []).map(s => ({ id: s._id, color: s.color, size: s.size, pattern: s.pattern, stock: s.available })) }
}
export async function ensureCatalog(force = false) {
  if (pending) return pending
  if (catalogStatus.ready && !force) return
  pending = (async () => {
    catalogStatus.loading = true; catalogStatus.error = ''
    try {
      const data = await callCloud<CatalogReply>('shop', { action: 'catalog' })
      rawCategories = data.categories
      categories.splice(0, categories.length, ...data.categories.filter(c => !c.parentId).map(c => ({ id: c._id, name: c.name, children: data.categories.filter(s => s.parentId === c._id).map(s => ({ id: s._id, name: s.name })) })))
      products.splice(0, products.length, ...data.products.map(mapProduct))
      const cfg = data.settings.shopConfig || {}
      const memberCfg = cfg.member || {}
      Object.assign(shopConfig, { shopName: data.settings.shopName || '我的店铺', brandWord: cfg.brandWord || '', brandColor: cfg.brandColor || '#2563EB', logo: cfg.logo || '', footerText: cfg.footerText || '', specAxes: normalizeAxes(cfg.specAxes), specChart: { enabled: cfg.specChart?.enabled !== false, title: cfg.specChart?.title || '规格说明' }, reviewRequired: cfg.reviewRequired !== false, member: { enabled: memberCfg.enabled !== false, rechargeEnabled: memberCfg.rechargeEnabled !== false, packages: normalizePackages(memberCfg.packages) }, tiers: (data.tiers || []).map(t => ({ level: t.level, name: t.name, threshold: t.threshold, discountBps: t.discountBps, cardBg: t.cardBg || '', cardText: t.cardText || '' })), notices: data.settings.notices || [], servicePhone: data.settings.servicePhone || '', serviceHours: data.settings.serviceHours || '', faqs: data.faqs.map(f => ({ ...f, id: f._id })) })
      homeData.notices = data.announcements.map(a => ({ id: a._id, text: a.text }))
      homeData.slides = data.banners.map(b => ({ id: b._id, image: b.image, alt: '店铺主图', caption: '' }))
      homeData.splash = { enabled: data.settings.splashEnabled === true, image: data.settings.splashImage || '', link: data.settings.splashLink || '', seconds: data.settings.splashSeconds || 5 }
      lastFetchOkAt = Date.now()
      catalogStatus.ready = true
    } catch (error) { catalogStatus.error = error instanceof Error ? error.message : '商品读取失败'; throw error }
    finally { catalogStatus.loading = false; pending = null }
  })()
  return pending
}
export async function searchProducts(keyword: string) { await ensureCatalog(); const data = await callCloud<CatalogReply>('shop', { action: 'catalog', keyword }); return data.products.map(mapProduct) }
export const findProduct = (id: string) => products.find(p => p.id === id)
export const money = (cents: number) => (cents / 100).toFixed(2)
// 后台改动（开关/价格/名单）对已打开的小程序尽快生效：距上次成功拉取超过 maxAge 时 onShow 强制刷新。
export async function ensureCatalogStale(maxAge = 60000) { if (catalogStatus.ready && Date.now() - lastFetchOkAt > maxAge) return ensureCatalog(true); return ensureCatalog() }
