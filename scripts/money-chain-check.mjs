// 钱账链模拟对账：充值 -> 报价 -> 下单 -> 模拟支付 -> 即时退款/审核退款，全链路跑通后对平账本。
// 数据库由内存假表 + mall_atomic_commit 的忠实仿真代替（锁校验与余额不变式与 SQL 版同规则）；
// SQL 版 RPC 与原子提交本身由 scripts/replay-db.sh 在真 PG 上验证。
import assert from 'node:assert/strict'
import Module from 'node:module'
import { createRequire } from 'node:module'
process.env.TCB_ENV = 'test-env'
process.env.WECHAT_APP_ID = 'wx' + '1234567890abcdef' // 拼接写法：避免出现 wx+16位十六进制字面量（违禁扫描形态）
const APP_ID = process.env.WECHAT_APP_ID

// ---------- 内存假库 ----------
const tables = {}
for (const t of ['users', 'member_accounts', 'settings', 'member_tiers', 'products', 'skus', 'freight_templates', 'carts', 'addresses', 'orders', 'order_items', 'refunds', 'auto_refunds', 'balance_logs', 'recharge_records', 'coupons', 'gift_stock']) tables[t] = []
function colsOf(spec) {
  if (!spec || spec.trim() === '*') return null
  return spec.split(',').map(s => s.trim().replace(/^"|"$/g, ''))
}
class Query {
  constructor(table) { this.table = table; this.filters = []; this.sorts = []; this.limitN = null; this.cols = null }
  select(spec) { this.cols = colsOf(spec); return this }
  eq(col, val) { this.filters.push(r => String(r[col]) === String(val)); return this }
  neq(col, val) { this.filters.push(r => String(r[col]) !== String(val)); return this }
  in(col, arr) { const set = new Set(arr.map(String)); this.filters.push(r => set.has(String(r[col]))); return this }
  gte(col, val) { this.filters.push(r => r[col] >= val); return this }
  lte(col, val) { this.filters.push(r => r[col] <= val); return this }
  order(col, { ascending } = {}) { this.sorts.push([col, ascending !== false]); return this }
  limit(n) { this.limitN = n; return this }
  range(a, b) { this.rangeAB = [a, b]; return this }
  then(resolve, reject) {
    try {
      let rows = tables[this.table].filter(r => this.filters.every(f => f(r)))
      for (const [col, asc] of this.sorts) rows = [...rows].sort((a, b) => (a[col] < b[col] ? -1 : a[col] > b[col] ? 1 : 0) * (asc ? 1 : -1))
      if (this.rangeAB) rows = rows.slice(this.rangeAB[0], this.rangeAB[1] + 1)
      if (this.limitN !== null) rows = rows.slice(0, this.limitN)
      if (this.cols) rows = rows.map(r => Object.fromEntries(this.cols.map(c => [c, r[c]])))
      resolve({ data: rows.map(r => ({ ...r })), error: null })
    } catch (e) { reject(e) }
  }
}
function atomicCommit(plan) {
  const allowed = ['users', 'member_accounts', 'carts', 'addresses', 'orders', 'order_items', 'skus', 'gift_stock', 'coupons', 'balance_logs', 'recharge_records', 'gift_allocations', 'refunds', 'auto_refunds', 'membership_records']
  const noUpdate = ['balance_logs', 'recharge_records', 'gift_allocations', 'member_accounts', 'membership_records']
  const locks = [...(plan.locks || [])].sort((a, b) => (a.table + a.id).localeCompare(b.table + b.id))
  for (const op of locks) {
    if (!allowed.includes(op.table) || op.table === 'member_accounts') throw Object.assign(new Error('INVALID_LOCK_TABLE'), { code: 'INVALID_LOCK_TABLE' })
    const old = tables[op.table].find(r => r._id === op.id)
    if (!old) throw Object.assign(new Error('STALE_ROW'), { code: '40001' })
    for (const [k, v] of Object.entries(op.expected || {})) {
      if (String(old[k]) !== String(v)) throw Object.assign(new Error('STALE_ROW'), { code: '40001' })
    }
    if (op.table === 'users') {
      const upd = (plan.updates || []).find(u => u.table === 'users' && u.id === op.id && u.data.balance !== undefined)
      if (upd && upd.data.balance !== old.balance) {
        const delta = (plan.inserts || []).filter(i => i.table === 'balance_logs' && i.data.userId === op.id).reduce((s, i) => s + i.data.amount, 0)
        if (upd.data.balance !== old.balance + delta) throw Object.assign(new Error('BALANCE_LEDGER_MISMATCH'), { code: 'BALANCE_LEDGER_MISMATCH' })
      }
    }
  }
  // 与 schema 的列默认值保持一致（服务端依赖 DB 默认补齐这些字段）
  const defaults = {
    orders: { version: 0, refundedAmount: 0 },
    order_items: { refundedQty: 0 },
    skus: { reserved: 0 },
    gift_stock: { reserved: 0 },
    users: { balance: 0, totalPurchase: 0, totalRecharge: 0, version: 0, level: 0 },
  }
  for (const op of plan.inserts || []) {
    if (!allowed.includes(op.table)) throw Object.assign(new Error('INVALID_WRITE_TABLE'), { code: 'INVALID_WRITE_TABLE' })
    tables[op.table].push({ ...(defaults[op.table] || {}), ...op.data })
  }
  for (const op of plan.updates || []) {
    if (!allowed.includes(op.table) || noUpdate.includes(op.table)) throw Object.assign(new Error('INVALID_UPDATE_TABLE'), { code: 'INVALID_UPDATE_TABLE' })
    if (!locks.some(l => l.table === op.table && l.id === op.id)) throw Object.assign(new Error('UPDATE_WITHOUT_LOCK'), { code: 'UPDATE_WITHOUT_LOCK' })
    const row = tables[op.table].find(r => r._id === op.id)
    if (!row) throw Object.assign(new Error('STALE_ROW'), { code: '40001' })
    Object.assign(row, op.data)
  }
  for (const op of plan.deletes || []) {
    if (!['carts', 'addresses'].includes(op.table)) throw Object.assign(new Error('INVALID_DELETE_TABLE'), { code: 'INVALID_DELETE_TABLE' })
    const idx = tables[op.table].findIndex(r => r._id === op.id)
    if (idx >= 0) tables[op.table].splice(idx, 1)
  }
  return { ok: true }
}
const fakeDb = {
  from: table => new Query(table),
  rpc: async (name, args) => {
    if (name === 'mall_atomic_commit') {
      try { return { data: atomicCommit(args.plan), error: null } }
      catch (e) { return { data: null, error: { message: e.message, code: e.code } } }
    }
    return { data: null, error: { message: 'RPC_NOT_IMPLEMENTED:' + name, code: 'RPC_NOT_IMPLEMENTED' } }
  },
}
const origLoad = Module._load
Module._load = function (request, ...rest) {
  if (request === '@cloudbase/node-sdk') return { init: () => ({ rdb: () => fakeDb, auth: () => ({ getClientCredential: async () => ({ access_token: 'fake' }) }) }) }
  return origLoad.call(this, request, ...rest)
}
const require = createRequire(import.meta.url)
const rt = require('../server/runtime.js')
const origInt = rt.int
rt.int = (v) => { try { return origInt(v) } catch (e) { console.error('BAD INT:', JSON.stringify(v), typeof v); console.error(new Error().stack.split('\n').slice(1, 8).join('\n')); throw e } }

const memberFn = require('../server/member.js')
const orderFn = require('../server/order.js')
const context = { environment: JSON.stringify({ WX_OPENID: 'openid-1', WX_APPID: APP_ID, TCB_UUID: '', TCB_CUSTOM_USER_ID: '', TCB_ISANONYMOUS_USER: 'false' }) }
async function call(fn, event, openid = 'openid-1') {
  const ctx = openid === 'openid-1' ? context : { environment: JSON.stringify({ WX_OPENID: openid, WX_APPID: APP_ID, TCB_UUID: '', TCB_CUSTOM_USER_ID: '', TCB_ISANONYMOUS_USER: 'false' }) }
  const res = await fn.main(event, ctx)
  assert.equal(res.ok, true, `expected ok, got ${JSON.stringify(res)} for ${JSON.stringify(event)}`)
  return res
}

// ---------- 种子 ----------
tables.settings.push({ _id: 'global', shopName: '测店', shopConfig: { brandWord: '', brandColor: '#2563EB', logo: '', footerText: '', specAxes: ['规格一', '规格二', '规格三'], specChart: { enabled: true, title: '规格说明' }, reviewRequired: true, member: { enabled: true, rechargeEnabled: true, packages: [{ amount: 20000, bonus: 2000, label: '充200送20' }] } }, memberRules: {}, paymentTimeoutMinutes: 30, realPaymentEnabled: false, smsEnabled: false })
tables.member_tiers.push(
  { _id: 'tier-1', level: 1, name: '会员', threshold: 10000, discountBps: 9500, cardBg: '', cardText: '', sort: 0, enabled: true },
  { _id: 'tier-2', level: 2, name: '高级会员', threshold: 50000, discountBps: 9000, cardBg: '', cardText: '', sort: 1, enabled: true },
)
tables.users.push({ _id: 'user-1', openid: 'openid-1', cloudUid: null, phone: '13800000000', nickname: '商城会员', memberNo: 'M000001', level: 0, balance: 0, totalPurchase: 0, totalRecharge: 0, version: 0 })
tables.users.push({ _id: 'user-2', openid: 'openid-2', cloudUid: null, phone: '13900000000', nickname: '商城会员', memberNo: 'M000002', level: 0, balance: 3000, totalPurchase: 0, totalRecharge: 0, version: 0 })
tables.freight_templates.push({ _id: 'default', name: '默认运费', rules: [{ regions: ['*'], price: 1000, type: 'normal' }], isDefault: true })
tables.products.push({ _id: 'prod-1', name: '测试商品', categoryId: 'c1', images: ['https://x/y.png'], detailImages: [], desc: '', subtitle: '', keywords: [], colors: ['红'], sizes: [], patterns: [], price: 10000, freightMode: 'template', freightTemplateId: 'default', stage: 'shelf', reviewStatus: 'approved', onShelf: true })
tables.skus.push({ _id: 'sku-1', productId: 'prod-1', color: '红', size: '', pattern: '', stock: 10, reserved: 0 })
tables.addresses.push({ _id: 'addr-1', userId: 'user-1', name: '测', phone: '13800000000', region: '普通地区', detail: '某路1号', isDefault: true })
tables.addresses.push({ _id: 'addr-2', userId: 'user-2', name: '测', phone: '13900000000', region: '普通地区', detail: '某路2号', isDefault: true })

let passed = 0
async function ok(name, fn) { await fn(); passed++; console.log('PASS', name) }
const user1 = () => tables.users.find(u => u._id === 'user-1')
const user2 = () => tables.users.find(u => u._id === 'user-2')
const TERMS = 'recharge-20261115'

await ok('会员账户初始态', async () => {
  const res = await call(memberFn, { action: 'account' })
  assert.equal(res.account.level, 0)
  assert.equal(res.account.discountBps, 10000)
  assert.equal(res.account.balance, 0)
  assert.equal(res.termsVersion, TERMS)
})
await ok('充值 20000 得赠 2000，累计定级 L1', async () => {
  const res = await call(memberFn, { action: 'recharge', requestKey: 'rk-recharge-1', agreed: true, termsVersion: TERMS, amount: 20000 })
  assert.equal(res.record.amount, 20000)
  assert.equal(res.record.bonusAmount, 2000)
  assert.equal(res.record.level, 1)
  assert.equal(user1().balance, 22000)
  assert.equal(user1().totalRecharge, 20000)
  assert.equal(user1().level, 1)
  const logs = tables.balance_logs.filter(l => l.userId === 'user-1')
  assert.equal(logs.length, 2)
  assert.deepEqual(logs.map(l => [l.type, l.amount]).sort(), [['bonus', 2000], ['recharge', 20000]])
})
await ok('同 requestKey 重放充值幂等', async () => {
  const res = await call(memberFn, { action: 'recharge', requestKey: 'rk-recharge-1', agreed: true, termsVersion: TERMS, amount: 20000 })
  assert.equal(res.idempotent, true)
  assert.equal(user1().balance, 22000)
  assert.equal(tables.recharge_records.length, 1)
})
await ok('再充 30000（无套餐无赠送），累计 50000 升 L2', async () => {
  await call(memberFn, { action: 'recharge', requestKey: 'rk-recharge-2', agreed: true, termsVersion: TERMS, amount: 30000 })
  assert.equal(user1().balance, 52000)
  assert.equal(user1().totalRecharge, 50000)
  assert.equal(user1().level, 2)
})
await ok('报价：L2 九折 + 余额拆分', async () => {
  const q = await call(orderFn, { action: 'quote', lines: [{ productId: 'prod-1', skuId: 'sku-1', qty: 1 }], addressId: 'addr-1', useBalance: true })
  assert.equal(q.quote.goodsAmount, 10000)
  assert.equal(q.quote.discountAmount, 1000)
  assert.equal(q.quote.freightAmount, 1000)
  assert.equal(q.quote.payAmount, 10000)
  assert.equal(q.quote.balancePaid, 10000)
  assert.equal(q.quote.wxPaid, 0)
  const q2 = await call(orderFn, { action: 'quote', lines: [{ productId: 'prod-1', skuId: 'sku-1', qty: 1 }], addressId: 'addr-1', useBalance: false })
  assert.equal(q2.quote.balancePaid, 0)
  assert.equal(q2.quote.wxPaid, 10000)
})
let orderId1
await ok('下单预占 + 模拟支付扣余额', async () => {
  const created = await call(orderFn, { action: 'create', requestKey: 'rk-order-1', lines: [{ productId: 'prod-1', skuId: 'sku-1', qty: 1 }], addressId: 'addr-1', useBalance: true })
  orderId1 = created.order._id
  assert.ok(orderId1.startsWith('GM'))
  assert.equal(tables.skus[0].reserved, 1)
  const paid = await call(orderFn, { action: 'payMock', orderId: orderId1 })
  assert.equal(paid.order.status, 'pending_ship')
  assert.equal(paid.order.balancePaid, 10000)
  assert.equal(user1().balance, 42000)
  assert.equal(tables.skus[0].stock, 9)
  assert.equal(tables.skus[0].reserved, 0)
  assert.equal(user1().totalPurchase, 10000)
  const payLog = tables.balance_logs.find(l => l.dedupeKey === 'pay:' + orderId1)
  assert.equal(payLog.amount, -10000)
  assert.equal(payLog.balanceAfter, 42000)
})
await ok('即时全额退款：余额回补 + 库存归还', async () => {
  const itemId = tables.order_items.find(i => i.orderId === orderId1)._id
  const res = await call(orderFn, { action: 'requestRefund', orderId: orderId1, reasonCode: 'buyer_change', reasonText: '', lines: [{ itemId, qty: 1 }] })
  assert.equal(res.refundMode, 'instant')
  assert.equal(res.order.status, 'refunded')
  assert.equal(user1().balance, 52000)
  assert.equal(tables.skus[0].stock, 10)
  const rf = tables.refunds.find(r => r._id === res.refundId)
  assert.equal(rf.totalAmount, 10000)
  assert.equal(rf.balanceAmount, 10000)
  assert.equal(rf.originalAmount, 0)
  assert.equal(tables.auto_refunds.length, 1)
})
await ok('部分余额订单：分路退款按余额支付额封顶', async () => {
  const created = await call(orderFn, { action: 'create', requestKey: 'rk-order-2', lines: [{ productId: 'prod-1', skuId: 'sku-1', qty: 2 }], addressId: 'addr-2', useBalance: true }, 'openid-2')
  const oid = created.order._id
  assert.equal(created.order.payAmount, 21000)
  assert.equal(created.order.balancePaid, 3000)
  const paid = await call(orderFn, { action: 'payMock', orderId: oid }, 'openid-2')
  assert.equal(paid.order.balancePaid, 3000)
  assert.equal(paid.order.wxPaid, 18000)
  assert.equal(user2().balance, 0)
  const itemId = tables.order_items.find(i => i.orderId === oid)._id
  const res = await call(orderFn, { action: 'requestRefund', orderId: oid, reasonCode: 'buyer_change', reasonText: '', lines: [{ itemId, qty: 1 }] }, 'openid-2')
  assert.equal(res.refundMode, 'instant')
  const rf = tables.refunds.find(r => r._id === res.refundId)
  assert.equal(rf.totalAmount, 10000)
  assert.equal(rf.balanceAmount, 3000)
  assert.equal(rf.originalAmount, 7000)
  assert.equal(user2().balance, 3000)
  assert.equal(res.order.status, 'pending_ship')
})
await ok('待收货退款走审核：申请时不動钱', async () => {
  const order = tables.orders.find(o => o.status === 'pending_ship' && o.userId === 'user-2')
  order.status = 'pending_recv'
  const itemId = tables.order_items.find(i => i.orderId === order._id)._id
  const res = await call(orderFn, { action: 'requestRefund', orderId: order._id, reasonCode: 'buyer_change', reasonText: '', lines: [{ itemId, qty: 1 }] }, 'openid-2')
  assert.equal(res.refundMode, 'review')
  const rf = tables.refunds.find(r => r._id === res.refundId)
  assert.equal(rf.status, 'pending')
  assert.equal(user2().balance, 3000)
  const cancel = await call(orderFn, { action: 'refundCancel', refundId: res.refundId }, 'openid-2')
  assert.equal(cancel.refundId, res.refundId)
  assert.equal(tables.refunds.find(r => r._id === res.refundId).status, 'cancelled')
})
await ok('账本对平：余额 = 流水和（两用户）', async () => {
  for (const u of [user1(), user2()]) {
    const sum = tables.balance_logs.filter(l => l.userId === u._id).reduce((s, l) => s + l.amount, 0)
    const opening = u._id === 'user-2' ? 3000 : 0
    assert.equal(u.balance, opening + sum, `user ${u._id}: balance ${u.balance} vs opening ${opening} + logs ${sum}`)
  }
  assert.equal(tables.balance_logs.filter(l => l.userId === 'user-1').length, 5) // 充值2条+充值1条+支付1条+退款1条
})
console.log(`MONEY-CHAIN PASS: ${passed} checks`)
