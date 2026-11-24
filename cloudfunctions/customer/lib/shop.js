'use strict'
const tcb = require('@cloudbase/node-sdk')
const money = require('./money')
const mt = require('./member-tiers')
function createApp() {
  const env = process.env.TCB_ENV || process.env.SCF_NAMESPACE
  if (!env) throw new Error('CLOUD_ENV_UNAVAILABLE')
  return tcb.init({ env, region: process.env.TCB_REGION || 'ap-shanghai' })
}
async function rows(query) {
  const { data, error } = await query
  if (error) throw new Error(`PG_READ_FAILED: ${error.code || ''} ${error.message || 'unknown'}`)
  return data || []
}
function integer(value) {
  const number = Number(value)
  if (!Number.isSafeInteger(number)) throw new Error('INVALID_STORED_INTEGER')
  return number
}
exports.main = async (event, context) => {
  const action = event?.action || 'catalog'
  if (!['catalog', 'product'].includes(action)) return { ok: false, code: 'UNKNOWN_ACTION', message: '不支持的商品操作' }
  const app = createApp()
  const db = app.rdb()
  const [categories, products, skus, settings, tiers] = await Promise.all([
    rows(db.from('categories').select('*').eq('visible', true).order('sort')),
    rows(db.from('products').select('*').eq('stage', 'shelf').eq('reviewStatus', 'approved').eq('onShelf', true).limit(200)),
    rows(db.from('skus').select('_id,productId,color,size,pattern,stock,reserved').limit(2000)),
    rows(db.from('settings').select('shopName,servicePhone,serviceHours,notices,sizeChart,realPaymentEnabled,smsEnabled,shopConfig,announcementIntervalSeconds,splashEnabled,splashImage,splashLink,splashSeconds').eq('_id', 'global')),
    rows(db.from('member_tiers').select('*').eq('enabled', true).order('level')),
  ])
  const who = require('./runtime').invocationIdentity(context)
  const user = who.openId && who.appId === (process.env.WECHAT_APP_ID || '') ? (await rows(db.from('users').select('level').eq('openid', who.openId).limit(1)))[0] : null
  const shopConfig = settings[0]?.shopConfig || {}
  const mc = mt.memberConfig(shopConfig)
  const normTiers = tiers.map(t => ({ level: integer(t.level), threshold: integer(t.threshold), discountBps: integer(t.discountBps) }))
  const bps = mt.discountBpsFor(normTiers, user ? integer(user.level) : 0, mc.enabled)
  const memberRate = bps / 10000
  const visibleCategoryIds = new Set(categories.filter(c => !c.parentId || categories.some(p => p._id === c.parentId && p.visible)).map(c => c._id))
  const shapeProduct = p => {
    const { customEnabled, autoRule, ...rest } = p
    return {
    ...rest, price: integer(p.price), estimatedPrice: money.totals(integer(p.price), 0, memberRate).payAmount,
    skus: skus.filter(s => s.productId === p._id).map(s => ({ _id: s._id, color: s.color, size: s.size, pattern: s.pattern, available: integer(s.stock) - integer(s.reserved) })),
    }
  }
  const visibleProducts = products.filter(p => visibleCategoryIds.has(p.categoryId)).map(shapeProduct)
  const keyword = typeof event?.keyword === 'string' ? event.keyword.trim().slice(0, 100).toLowerCase() : ''
  const terms = keyword.split(/\s+/).filter(Boolean)
  const filtered = visibleProducts.filter(p => {
    const category = categories.find(c => c._id === p.categoryId)
    const parent = category && categories.find(c => c._id === category.parentId)
    const text = [p.name, p.subtitle, ...p.keywords, category?.name || '', parent?.name || ''].join(' ').toLowerCase()
    return terms.every(term => text.includes(term))
  })
  if (action === 'product') return { ok: true, product: visibleProducts.find(p => p._id === event.productId) || null, source: 'cloudbase-pg' }
  const [banners, picks, announcements, faqs] = await Promise.all([
    rows(db.from('banners').select('*').eq('visible', true).order('sort')),
    rows(db.from('home_picks').select('*').order('sort')),
    rows(db.from('announcements').select('*').eq('visible', true).order('sort')),
    rows(db.from('faqs').select('*').eq('visible', true).order('sort')),
  ])
  return { ok: true, source: 'cloudbase-pg', categories, products: filtered, settings: settings[0], tiers: tiers.map(t => ({ level: integer(t.level), name: t.name, threshold: integer(t.threshold), discountBps: integer(t.discountBps), cardBg: t.cardBg || '', cardText: t.cardText || '' })), banners, picks, announcements, faqs }
}
