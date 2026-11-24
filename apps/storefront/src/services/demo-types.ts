export interface CartLine { key: string; productId: string; skuId: string; quantity: number; selected: boolean }
export interface DraftLine { productId: string; skuId: string; quantity: number }
export interface CheckoutDraft { token: string; source: 'cart' | 'direct'; lines: DraftLine[] }
export interface Address { id: string; name: string; phone: string; region: string; detail: string; isDefault: boolean }
export type OrderStatus = 'pending' | 'processing' | 'shipped' | 'completed' | 'cancelled' | 'refund'
export interface OrderLine extends DraftLine { name: string; image: string; spec: string; unitPrice: number }
export interface Quote { lines: OrderLine[]; subtotal: number; shipping: number; total: number; discount?: number; balancePaid?: number; wxPaid?: number }
export interface DemoOrder extends Quote { id: string; token: string; createdAt: number; payDeadline?: number; status: OrderStatus; address: Address; remark: string; carrier?: string; tracking?: string; sample: boolean }
export interface DemoUser { phone: string; nickname: string; id?: string; level?: number; balance?: number; totalPurchase?: number; memberNo?: string }
export interface DemoState { cart: CartLine[]; user: DemoUser | null; owner: string; addresses: Address[]; selectedAddressId: string; orders: DemoOrder[]; draft: CheckoutDraft | null }
