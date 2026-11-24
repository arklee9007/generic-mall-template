import type { NavigationDestination } from '../components/navigation'
// B-27：四个主页同居一个滑块壳（pages/index/index）。壳外跳主页走「存储目标＋全局事件」双通道：
// 壳已在栈顶时事件即时切换；否则 reLaunch 到壳后由壳在 onShow 消费存储目标。
export const MAIN_PANELS: NavigationDestination[] = ['home', 'category', 'cart', 'account']
export const MAIN_TARGET_KEY = 'mall-main-target'
export const MAIN_CATEGORY_KEY = 'mall-category-target'
export function requestMainPanel(dest: NavigationDestination, categoryId?: string) {
  try {
    uni.setStorageSync(MAIN_TARGET_KEY, dest)
    if (categoryId) uni.setStorageSync(MAIN_CATEGORY_KEY, categoryId)
    else uni.removeStorageSync(MAIN_CATEGORY_KEY)
  } catch { /* 存储不可用时仅靠事件通道 */ }
  uni.$emit('mall-main-panel', dest)
}
export function takeMainTarget(): { dest: string; categoryId: string } | null {
  try {
    const dest = uni.getStorageSync(MAIN_TARGET_KEY)
    if (!dest) return null
    uni.removeStorageSync(MAIN_TARGET_KEY)
    const categoryId = uni.getStorageSync(MAIN_CATEGORY_KEY) || ''
    uni.removeStorageSync(MAIN_CATEGORY_KEY)
    return { dest: String(dest), categoryId: String(categoryId || '') }
  } catch { return null }
}
