// 通用模板演示数据：中性示例商品，与数据库种子演示行一致（名字带 [示例] 前缀）。
// 规格用三轴槽位：colors/sizes/patterns 为轴 0/1/2；某轴数组为空表示该商品不用此轴。
export interface Category { id: string; name: string; children: { id: string; name: string }[] }
export interface Sku { id: string; color: string; size: string; pattern: string; stock: number }
export interface SpecChart { columns: string[]; rows: string[][] }
export interface Product {
  id: string; name: string; subtitle: string; category: string; subcategory: string
  keywords: string[]; price: number; image: string; gallery: string[]; detail: string; detailImages: string[]
  colors: string[]; sizes: string[]; patterns: string[]; specLabels: string[]; specChart: SpecChart | null; skus: Sku[]; freeShipping: boolean
}
export const categories: Category[] = [
  { id: 'demo-home', name: '[示例]家居日用', children: [] },
  { id: 'demo-office', name: '[示例]文具办公', children: [] },
  { id: 'demo-food', name: '[示例]休闲食品', children: [] },
]
const PLACEHOLDER = '/static/products/placeholder.svg'
function makeSkus(id: string, colors: string[], sizes: string[], patterns: string[]): Sku[] {
  const axes = [colors.length ? colors : [''], sizes.length ? sizes : [''], patterns.length ? patterns : ['']]
  const skus: Sku[] = []
  axes[0].forEach((color, c) => axes[1].forEach((size, s) => axes[2].forEach((pattern, p) => {
    skus.push({ id: `${id}-${c}-${s}-${p}`, color, size, pattern, stock: 10 })
  })))
  return skus
}
function product(id: string, name: string, subtitle: string, category: string, price: number, colors: string[], sizes: string[], patterns: string[], specLabels: string[], specChart: SpecChart | null, keywords: string[]): Product {
  return { id, name, subtitle, category, subcategory: '', keywords, price, image: PLACEHOLDER, gallery: [PLACEHOLDER], detail: PLACEHOLDER, detailImages: [PLACEHOLDER], colors, sizes, patterns, specLabels, specChart, skus: makeSkus(id, colors, sizes, patterns), freeShipping: false }
}
export const products: Product[] = [
  product('demo-cup', '[示例]双层保温杯', '保温保冷 / 食品级内胆', 'demo-home', 8900, ['米白', '深灰'], ['350ml', '500ml'], ['简约款', '磨砂款'], ['颜色', '容量', '款式'], { columns: ['容量', '高度', '口径'], rows: [['350ml', '19cm', '6cm'], ['500ml', '22cm', '6.5cm']] }, ['[示例]双层保温杯', '保温杯', '水杯']),
  product('demo-notebook', '[示例]布面笔记本', '96 页 / 点阵内页', 'demo-office', 3900, ['藏青', '砖红'], ['A5', 'B5'], [], ['颜色', '规格'], null, ['[示例]布面笔记本', '笔记本', '本子']),
  product('demo-box', '[示例]桌面收纳盒', '三格 / 可叠放', 'demo-home', 5900, ['透明', '白色'], [], [], ['颜色'], null, ['[示例]桌面收纳盒', '收纳盒']),
  product('demo-pen', '[示例]中性笔三支装', '0.5mm / 速干', 'demo-office', 1900, [], [], [], [], null, ['[示例]中性笔三支装', '中性笔', '笔']),
  product('demo-nuts', '[示例]坚果礼盒', '四种坚果 / 独立小包', 'demo-food', 12800, ['原味', '椒盐'], ['500g', '1kg'], [], ['口味', '规格'], null, ['[示例]坚果礼盒', '坚果', '零食']),
  product('demo-tea', '[示例]红茶小罐', '小罐 / 密封防潮', 'demo-food', 6800, ['正山小种', '金骏眉'], ['50g'], [], ['口味', '规格'], null, ['[示例]红茶小罐', '红茶', '茶叶']),
]
export const shopConfig = {
  mode: 'local-demo', realPaymentEnabled: false, smsEnabled: false,
  paymentTimeoutMinutes: 30,
  regions: ['普通地区', '新疆', '西藏', '青海', '宁夏', '甘肃', '内蒙古', '香港', '澳门', '台湾'],
  notices: ['示例商品仅用于演示，占位图非实拍。', '下单前请联系客服确认库存与运费。'],
  serviceHours: '周一至周六 10:00–19:00',
  faqs: [
    { id: 'shipping', question: '运费怎么算？', answer: '按收货地区与运费模板计算，下单时显示实收运费。' },
    { id: 'service', question: '收到商品有问题怎么办？', answer: '请先联系客服，售后按店铺公示规则处理。' },
    { id: 'payment', question: '体验订单会扣款吗？', answer: '不会。本次为本地样例体验，支付按钮只改变本机样例订单状态，不调用真实微信支付，也不发送短信。' },
    { id: 'orders', question: '如何取消订单和查看物流？', answer: '待付款订单可在订单详情取消；待收货订单支持查看快递公司、单号并复制查询。' },
  ],
}
export const money = (cents: number) => (cents / 100).toFixed(2)
export const findProduct = (id: string) => products.find(item => item.id === id)
export function searchProducts(keyword: string) {
  const words = keyword.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean)
  return products.filter(item => {
    const category = categories.find(c => c.id === item.category)
    const subcategory = category && category.children.find(c => c.id === item.subcategory)
    const text = [...item.keywords, category ? category.name : '', subcategory ? subcategory.name : ''].join(' ').toLocaleLowerCase()
    return words.every(word => text.includes(word))
  })
}
