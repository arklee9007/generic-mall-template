// 通用模板纯函数自检：钱账舍入、档位引擎、规格哨兵。不连数据库、不连网络。
import assert from 'node:assert/strict'
import Module from 'node:module'
import { createRequire } from 'node:module'
const origLoad = Module._load
Module._load = function (request, ...rest) {
  if (request === '@cloudbase/node-sdk') return { init: () => { throw new Error('no-cloud-in-test') } }
  return origLoad.call(this, request, ...rest)
}
const require = createRequire(import.meta.url)
const money = require('../server/money.js')
const mt = require('../server/member-tiers.js')
const catalog = require('../server/admin-catalog.js')
let passed = 0
async function ok(name, fn) { await fn(); passed++; console.log('PASS', name) }

// ---- money ----
await ok('money: 9折半入整', () => {
  const t = money.totalsBps(10001, 0, 9000)
  assert.equal(t.discountAmount, 1000)
  assert.equal(t.payAmount, 9001)
  assert.equal(t.balancePaid, 0)
  assert.equal(t.wxPaid, 9001)
})
await ok('money: 余额拆分（余额足/不足/不用余额）', () => {
  assert.deepEqual(money.totalsBps(10000, 1000, 10000, { balance: 20000, useBalance: true }), { goodsAmount: 10000, discountAmount: 0, freightAmount: 1000, payAmount: 11000, balancePaid: 11000, wxPaid: 0 })
  const t = money.totalsBps(10000, 1000, 9500, { balance: 3000, useBalance: true })
  assert.equal(t.discountAmount, 500)
  assert.equal(t.payAmount, 10500)
  assert.equal(t.balancePaid, 3000)
  assert.equal(t.wxPaid, 7500)
  assert.equal(money.totalsBps(10000, 0, 10000, { balance: 5000, useBalance: false }).balancePaid, 0)
})
await ok('money: totals 浮点口径与基点口径一致', () => {
  assert.deepEqual(money.totals(10000, 500, 0.95), money.totalsBps(10000, 500, 9500))
  assert.throws(() => money.totalsBps(100, 0, 10001), /INVALID_DISCOUNT_CONFIG/)
  assert.throws(() => money.amount(-1), /INVALID_MONEY/)
  assert.throws(() => money.multiply(100, 0), /INVALID_QUANTITY/)
})
await ok('money: 折扣不打到运费', () => {
  const t = money.totalsBps(10000, 2000, 5000)
  assert.equal(t.discountAmount, 5000)
  assert.equal(t.payAmount, 7000)
})

// ---- member tiers ----
const tiers = [
  { level: 1, name: '会员', threshold: 10000, discountBps: 9500, cardBg: '', cardText: '', sort: 0 },
  { level: 2, name: '高级会员', threshold: 50000, discountBps: 9000, cardBg: '', cardText: '', sort: 1 },
]
await ok('tiers: 累计定级（边界值）', () => {
  assert.equal(mt.levelForCumulative(tiers, 0), 0)
  assert.equal(mt.levelForCumulative(tiers, 9999), 0)
  assert.equal(mt.levelForCumulative(tiers, 10000), 1)
  assert.equal(mt.levelForCumulative(tiers, 49999), 1)
  assert.equal(mt.levelForCumulative(tiers, 50000), 2)
})
await ok('tiers: 档位回落（档位被删时取更低档）', () => {
  assert.equal(mt.tierForLevel(tiers, 5).level, 2)
  assert.equal(mt.tierForLevel(tiers, 0), null)
  assert.equal(mt.discountBpsFor(tiers, 1, true), 9500)
  assert.equal(mt.discountBpsFor(tiers, 1, false), 10000)
  assert.equal(mt.discountBpsFor([], 3, true), 10000)
})
await ok('tiers: 充赠只认整额套餐', () => {
  const pkgs = [{ amount: 20000, bonus: 2000, label: '充200送20' }]
  assert.equal(mt.bonusFor(pkgs, 20000), 2000)
  assert.equal(mt.bonusFor(pkgs, 19999), 0)
  assert.equal(mt.bonusFor([], 20000), 0)
})
await ok('tiers: 会员配置默认开', () => {
  assert.deepEqual(mt.memberConfig({}), { enabled: true, rechargeEnabled: true, packages: [] })
  assert.deepEqual(mt.memberConfig({ member: { enabled: false } }), { enabled: false, rechargeEnabled: true, packages: [] })
})

// ---- catalog prepareProduct (fake db: no existing SKUs) ----
const fakeDb = { from: () => ({ select: () => ({ eq: () => Promise.resolve({ data: [], error: null }) }) }) }
const base = { name: '测', categoryId: 'c1', images: ['https://x/y.png'], price: 100, freightMode: 'free' }
await ok('catalog: 0维商品只留一条全空SKU', async () => {
  const v = await catalog.prepareProduct(fakeDb, 'p0', { ...base, colors: [], sizes: [], patterns: [] })
  assert.equal(v.skus.length, 1)
  assert.deepEqual([v.skus[0].color, v.skus[0].size, v.skus[0].pattern], ['', '', ''])
  assert.deepEqual([v.colors, v.sizes, v.patterns], [[], [], []])
})
await ok('catalog: 2维笛卡尔积与哨兵', async () => {
  const v = await catalog.prepareProduct(fakeDb, 'p2', { ...base, colors: ['红', '蓝'], sizes: ['S', 'M'], patterns: [] })
  assert.equal(v.skus.length, 4)
  assert.ok(v.skus.every(s => s.pattern === ''))
  assert.equal(new Set(v.skus.map(s => s._id)).size, 4)
})
await ok('catalog: 规格重复与超限被拒', async () => {
  await assert.rejects(() => catalog.prepareProduct(fakeDb, 'p3', { ...base, colors: ['红', '红'] }), (e) => e.code === 'DUPLICATE_SPEC')
  await assert.rejects(() => catalog.prepareProduct(fakeDb, 'p4', { ...base, colors: Array.from({ length: 21 }, (_, i) => 'c' + i) }), (e) => e.code === 'INVALID_SPEC')
})
await ok('catalog: 规格说明表校验', async () => {
  const good = await catalog.prepareProduct(fakeDb, 'p5', { ...base, colors: ['红'], specChart: { columns: ['容量', '高度'], rows: [['350ml', '19cm']] } })
  assert.equal(good.sizeChart.columns.length, 2)
  assert.equal('specChart' in good, false, 'payload key must be sizeChart (DB column / RPC field)')
  assert.equal(good.sizeChart.rows[0][0], '350ml')
  await assert.rejects(() => catalog.prepareProduct(fakeDb, 'p6', { ...base, colors: ['红'], specChart: { columns: ['容量'], rows: [['a', 'b']] } }), (e) => e.code === 'INVALID_SPEC_CHART')
  const labels = await catalog.prepareProduct(fakeDb, 'p7', { ...base, colors: ['红'], specLabels: ['口味', '', ''] })
  assert.deepEqual(labels.specLabels, ['口味', '', ''])
})
console.log(`SELFCHECK PASS: ${passed} checks`)
