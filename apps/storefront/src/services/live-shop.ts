// Live CloudBase adapter. No local orders, prices, balances or stock mutations.
import { reactive, ref } from 'vue'
import { callCloud } from './cloud'
import { ensureCatalog, products, type MemberPackage } from './catalog'
import type { Address, DemoOrder, DemoState, DraftLine, OrderStatus, Quote } from './demo-types'
export type { Address, DemoOrder, DraftLine, OrderStatus, Quote } from './demo-types'
export type { MemberPackage } from './catalog'
interface RawUser { _id: string; phone: string | null; nickname: string; memberNo: string; level: number; balance: number; totalPurchase: number }
interface RawAddress extends Omit<Address, 'id'> { _id: string }
interface RawItem { productId: string; skuId?: string; name: string; image: string; color?: string; size: string; pattern?: string; price: number; qty: number }
interface RawQuote { items: RawItem[]; goodsAmount: number; discountAmount: number; freightAmount: number; payAmount: number; balancePaid: number; wxPaid: number }
interface RawOrder extends RawQuote { _id: string; requestKey: string; createdAt: string; payDeadline: string; status: string; address: Address; remark: string; expressCompany: string; expressNo: string }
// 会员模型（基础会员）：等级按累计充值实付定级，只升不降；折扣单位为基点，10000=不打折。
export const TERMS_VERSION = 'recharge-20261115'
export interface MemberAccount { level: number; tierName: string; discountBps: number; balance: number; totalRecharge: number; isMember: boolean; cardBg: string; cardText: string }
export interface RechargeRecord { amount: number; bonusAmount: number; level: number; requestKey: string; termsVersion: string; createdAt: string; simulated: boolean }
export interface BalanceLog { type: string; amount: number; orderId: string | null; balanceAfter: number; remark: string; createdAt: string }
interface RawMemberAccount { level: number; tierName: string; discountBps: number; balance: number; cumulativeRecharge: number; isMember: boolean; cardBg: string; cardText: string }
interface MemberAccountReply { account: RawMemberAccount; memberEnabled: boolean; rechargeEnabled: boolean; packages: MemberPackage[]; terms: string; termsVersion: string }
export const memberState = reactive({ account: null as MemberAccount | null, memberEnabled: true, rechargeEnabled: true, packages: [] as MemberPackage[], terms: '', termsVersion: TERMS_VERSION, records: [] as RechargeRecord[], logs: [] as BalanceLog[] })
export const demoState = reactive<DemoState>({ cart: [], user: null, owner: '', addresses: [], selectedAddressId: '', orders: [], draft: null })
export const cartGoodsAmount = ref(0)
export const statusLabel: Record<OrderStatus, string> = { pending: '待付款', processing: '待发货', shipped: '待收货', completed: '已完成', cancelled: '已取消', refund: '退款' }
const statusMap: Record<string, OrderStatus> = { pending_pay: 'pending', pending_ship: 'processing', pending_recv: 'shipped', done: 'completed', cancelled: 'cancelled', refunding: 'refund', refunded: 'refund' }
// 会员价口径与服务端 money.totalsBps 一致：折扣额四舍五入到分，会员价 = 原价 - 折扣额。
export function memberPrice(price: number): number {
  const account = memberState.account
  if (!memberState.memberEnabled || !account?.isMember || !account.discountBps || account.discountBps >= 10000) return price
  const discount = Math.floor((price * (10000 - account.discountBps) + 5000) / 10000)
  return price - discount
}
export function discountLabel(discountBps: number): string {
  if (!discountBps || discountBps >= 10000) return '不打折'
  const zhe = discountBps / 1000
  return (Number.isInteger(zhe) ? String(zhe) : zhe.toFixed(1)) + ' 折'
}
function mapQuote(q: RawQuote): Quote {
  return { lines: q.items.map(item => ({ productId: item.productId, skuId: item.skuId || '', name: item.name, image: item.image, spec: [item.color, item.size, item.pattern].filter(Boolean).join(' / '), unitPrice: item.price, quantity: item.qty })), subtotal: q.goodsAmount, shipping: q.freightAmount, total: q.payAmount, discount: q.discountAmount, balancePaid: q.balancePaid, wxPaid: q.wxPaid }
}
function mapOrder(raw: RawOrder): DemoOrder {
  const quote = mapQuote(raw)
  return { ...quote, id: raw._id, token: raw.requestKey, createdAt: Date.parse(raw.createdAt), payDeadline: Date.parse(raw.payDeadline), status: statusMap[raw.status], address: raw.address, remark: raw.remark, carrier: raw.expressCompany, tracking: raw.expressNo, sample: false }
}
function cacheOrder(raw: RawOrder) { const order = mapOrder(raw); const index = demoState.orders.findIndex(o => o.id === order.id); if (index >= 0) demoState.orders[index] = order; else demoState.orders.unshift(order); return order }
function linesDto(lines: DraftLine[]) { return lines.map(line => ({ productId: line.productId, skuId: line.skuId, qty: line.quantity })) }
// 购物车乐观更新：界面先按本地状态变，写操作进同一条队列在后台对账同步，不再每次操作整表重存＋全量回拉。
// 合计口径与服务端 customer.cart 一致：已勾选、且在目录中（在售）商品的 单价×数量（单位：分）。
const syncedCartLines = new Map<string, { qty: number; selected: boolean }>()
let cartWriteQueue: Promise<void> = Promise.resolve()
function noteCartSynced() { syncedCartLines.clear(); demoState.cart.forEach(line => syncedCartLines.set(line.skuId, { qty: line.quantity, selected: line.selected })) }
function recountCart() { cartGoodsAmount.value = demoState.cart.reduce((sum, line) => { if (!line.selected) return sum; const product = products.find(item => item.id === line.productId); return sum + (product ? product.price * line.quantity : 0) }, 0) }
function enqueueCartWrite(task: () => Promise<void>) { cartWriteQueue = cartWriteQueue.then(task, task) }
async function flushCartChanges() {
  const pending = demoState.cart.filter(line => { const synced = syncedCartLines.get(line.skuId); return !synced || synced.qty !== line.quantity || synced.selected !== line.selected })
  for (const snapshot of pending) {
    const line = demoState.cart.find(item => item.skuId === snapshot.skuId)
    if (!line) continue
    const sent = { qty: line.quantity, selected: line.selected }
    try {
      await callCloud('customer', { action: 'setCart', skuId: line.skuId, qty: sent.qty, selected: sent.selected })
      syncedCartLines.set(line.skuId, sent)
    } catch (error) {
      await refreshCart().catch(() => undefined)
      uni.showToast({ title: '购物车同步失败，已恢复最新状态', icon: 'none' })
      return
    }
  }
}
function queueCartSync() { enqueueCartWrite(flushCartChanges) }
export async function refreshSession() {
  let nativeIdentity = false
  // #ifdef MP-WEIXIN
  nativeIdentity = true
  // #endif
  if (!nativeIdentity) { demoState.user = null; memberState.account = null; return }
  if (uni.getStorageSync('mall-session-hidden')) { demoState.user = null; return }
  try {
    const data = await callCloud<{ user: RawUser; needsPhone: boolean }>('auth', { action: 'me' })
    demoState.user = data.needsPhone || !data.user.phone ? null : { id: data.user._id, phone: data.user.phone, nickname: data.user.nickname, memberNo: data.user.memberNo || '', level: data.user.level, balance: data.user.balance, totalPurchase: data.user.totalPurchase }
  } catch (error) {
    if (error && typeof error === 'object' && 'code' in error && error.code === 'WECHAT_LOGIN_REQUIRED') { demoState.user = null; return }
    throw error
  }
}
export async function refreshMember() {
  if (!demoState.user) return
  const data = await callCloud<MemberAccountReply>('member', { action: 'account' })
  memberState.account = { level: data.account.level, tierName: data.account.tierName, discountBps: data.account.discountBps, balance: data.account.balance, totalRecharge: data.account.cumulativeRecharge, isMember: data.account.isMember, cardBg: data.account.cardBg || '', cardText: data.account.cardText || '' }
  memberState.memberEnabled = data.memberEnabled !== false
  memberState.rechargeEnabled = data.rechargeEnabled !== false
  memberState.packages = Array.isArray(data.packages) ? data.packages : []
  memberState.terms = data.terms || ''
  memberState.termsVersion = data.termsVersion || TERMS_VERSION
}
export async function refreshCart() {
  if (!demoState.user) { demoState.cart = []; cartGoodsAmount.value = 0; syncedCartLines.clear(); return }
  const data = await callCloud<{ cart: { _id: string; skuId: string; productId: string; qty: number; selected: boolean }[]; goodsAmount: number }>('customer', { action: 'cart' })
  demoState.cart = data.cart.map(l => ({ key: l._id, productId: l.productId, skuId: l.skuId, quantity: l.qty, selected: l.selected })); cartGoodsAmount.value = data.goodsAmount; noteCartSynced()
}
export async function refreshAddresses() { if (!demoState.user) return; const data = await callCloud<{ addresses: RawAddress[] }>('customer', { action: 'addresses' }); demoState.addresses = data.addresses.map(a => ({ ...a, id: a._id })); if (!demoState.addresses.some(a => a.id === demoState.selectedAddressId)) demoState.selectedAddressId = demoState.addresses.find(a => a.isDefault)?.id || demoState.addresses[0]?.id || '' }
export async function reconcileOrders(_now?: number) { await refreshSession(); if (!demoState.user) { demoState.orders = []; return }; const data = await callCloud<{ orders: RawOrder[] }>('order', { action: 'list' }); demoState.orders = data.orders.map(mapOrder) }
export async function refreshCommerce() { await ensureCatalog(true); await refreshSession(); if (demoState.user) await Promise.all([refreshCart(), refreshAddresses(), reconcileOrders(), refreshMember()]) }
export const availableStock = (skuId: string) => products.flatMap(p => p.skus).find(s => s.id === skuId)?.stock || 0
export async function addToCart(_productId: string, skuId: string, quantity: number) {
  if (!demoState.user) { await refreshSession(); if (!demoState.user) throw new Error('请在微信小程序中登录并绑定手机号') }
  const product = products.find(item => item.skus.some(sku => sku.id === skuId))
  const existing = demoState.cart.find(line => line.skuId === skuId)
  if (existing) existing.quantity += quantity
  else if (product) demoState.cart = [...demoState.cart, { key: 'local-' + skuId, productId: product.id, skuId, quantity, selected: true }]
  recountCart(); queueCartSync()
}
export async function setCartQuantity(key: string, quantity: number) { const line = demoState.cart.find(l => l.key === key); if (!line) throw new Error('购物车已变化'); line.quantity = Math.max(1, Math.floor(quantity) || 1); recountCart(); queueCartSync() }
export async function saveDemo() { recountCart(); queueCartSync() }
export async function removeCart(key: string) {
  const line = demoState.cart.find(l => l.key === key); if (!line) return
  demoState.cart = demoState.cart.filter(l => l.key !== key); recountCart(); syncedCartLines.delete(line.skuId)
  enqueueCartWrite(async () => {
    try { await callCloud('customer', { action: 'removeCart', skuId: line.skuId }) }
    catch (error) { await refreshCart().catch(() => undefined); uni.showToast({ title: '移除同步失败，已恢复最新状态', icon: 'none' }) }
  })
}
export function startCheckout(lines?: DraftLine[]) { const selected = lines || demoState.cart.filter(l => l.selected).map(({ productId, skuId, quantity }) => ({ productId, skuId, quantity })); if (!selected.length) throw new Error('请先选择商品'); demoState.draft = { token: Date.now().toString(36) + Math.random().toString(36).slice(2), source: lines ? 'direct' : 'cart', lines: JSON.parse(JSON.stringify(selected)) } }
export async function quoteDraft(address?: Address, useBalance = true): Promise<Quote> { if (!demoState.draft?.lines.length) throw new Error('没有待结算商品，请重新选择'); const data = await callCloud<{ quote: RawQuote }>('order', { action: 'quote', lines: linesDto(demoState.draft.lines), addressId: address?.id, useBalance }); return mapQuote(data.quote) }
export async function createOrder(addressId: string, remark: string, useBalance = true) { const draft = demoState.draft; if (!draft) throw new Error('结算已结束，请重新选择商品'); const data = await callCloud<{ order: RawOrder }>('order', { action: 'create', requestKey: draft.token, source: draft.source, lines: linesDto(draft.lines), addressId, remark, useBalance }); demoState.draft = null; await refreshCart(); return cacheOrder(data.order) }
export async function fetchOrder(id: string) { await refreshSession(); if (!demoState.user) return; const data = await callCloud<{ order: RawOrder }>('order', { action: 'detail', orderId: id }); return cacheOrder(data.order) }
export async function payOrder(id: string) { const data = await callCloud<{ order: RawOrder }>('order', { action: 'payMock', orderId: id }); await Promise.all([refreshSession(), refreshMember(), ensureCatalog(true)]); return cacheOrder(data.order) }
export async function cancelOrder(id: string) { const data = await callCloud<{ order: RawOrder }>('order', { action: 'cancel', orderId: id }); await ensureCatalog(true); return cacheOrder(data.order) }
export async function receiveOrder(id: string) { const data = await callCloud<{ order: RawOrder }>('order', { action: 'receive', orderId: id }); return cacheOrder(data.order) }
export interface RefundItemRow { _id: string; name: string; image: string; color: string; size: string; pattern: string; price: number; qty: number; refundedQty: number }
export interface RefundRecord { _id: string; lines: { itemId: string; name: string; color: string; size: string; pattern: string; qty: number; amount: number }[]; reasonCode: string; reasonText: string; goodsAmount: number; freightAmount: number; freightComp: number; totalAmount: number; balanceAmount: number; originalAmount: number; mode: string; status: string; rejectReason: string; createdAt: string }
export async function fetchRefundData(id: string) { return callCloud<{ items: RefundItemRow[]; refunds: RefundRecord[] }>('order', { action: 'refundData', orderId: id }) }
export async function cancelRefund(orderId: string, refundId: string) { return callCloud<{ ok: boolean; refundId: string }>('order', { action: 'refundCancel', orderId, refundId }) }
export async function requestRefund(id: string, lines: { itemId: string; qty: number }[], reasonCode: string, reasonText: string) { const data = await callCloud<{ order: RawOrder; refundMode?: string; refundId?: string }>('order', { action: 'requestRefund', orderId: id, lines, reasonCode, reasonText }); return { order: cacheOrder(data.order), refundMode: data.refundMode === 'instant' ? 'instant' as const : 'review' as const, refundId: data.refundId } }
export async function saveAddress(input: Omit<Address, 'id'> & { id?: string }) { const data = await callCloud<{ address: RawAddress }>('customer', { action: 'saveAddress', address: { ...input, _id: input.id } }); await refreshAddresses(); return { ...data.address, id: data.address._id } }
export async function deleteAddress(id: string) { await callCloud('customer', { action: 'deleteAddress', addressId: id }); await refreshAddresses() }
export async function loginDemo(phone: string) { await callCloud('auth', { action: 'bindPhone', phone, agreed: true }); uni.removeStorageSync('mall-session-hidden'); await refreshCommerce() }
export function logoutDemo() { uni.setStorageSync('mall-session-hidden', true); demoState.user = null; demoState.cart = []; demoState.addresses = []; demoState.orders = []; demoState.draft = null; memberState.account = null; syncedCartLines.clear(); cartGoodsAmount.value = 0 }
export async function rechargeMember(amount: number, agreed: boolean, requestKey: string) {
  const data = await callCloud<{ record: RechargeRecord } & MemberAccountReply>('member', { action: 'recharge', requestKey, agreed, termsVersion: memberState.termsVersion || TERMS_VERSION, amount })
  await Promise.all([refreshMember(), refreshSession()])
  return data.record
}
export async function refreshLogs() { const data = await callCloud<{ records: RechargeRecord[]; logs: BalanceLog[] }>('member', { action: 'logs' }); memberState.records = data.records || []; memberState.logs = data.logs || [] }
