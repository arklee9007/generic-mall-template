import pagesConfig from '../pages.json'
import type { NavigationDestination } from '../components/navigation'
export function toast(title: string) { uni.showToast({ title, icon: 'none' }) }
export function decodeRouteQuery(value: unknown): string {
  const text = typeof value === 'string' ? value : ''
  // uni-h5 already decodes route options; WeChat passes URI-encoded values.
  // #ifdef MP-WEIXIN
  try { return decodeURIComponent(text) } catch { return text }
  // #endif
  // #ifndef MP-WEIXIN
  return text
  // #endif
}
export function openPage(url: string, replace = false) {
  const path = url.split('?')[0].replace(/^\//, '')
  if (!pagesConfig.pages.some(page => page.path === path)) { toast('页面正在准备中'); return }
  const options = { url, fail: () => toast('页面打开失败，请重试') }
  if (replace || getCurrentPages().length >= 8) uni.redirectTo(options)
  else uni.navigateTo(options)
}
export function goMain(destination: NavigationDestination) {
  // B-27：主页都在滑块壳里。壳在栈顶→发事件即时滑过去；不在→存目标后 reLaunch 到壳。
  const stack = getCurrentPages()
  const top = stack[stack.length - 1] as unknown as { route?: string } | undefined
  if (top?.route === 'pages/index/index') { uni.$emit('mall-main-panel', destination); return }
  try { uni.setStorageSync('mall-main-target', destination) } catch { /* 事件通道兜底 */ }
  uni.reLaunch({ url: '/pages/index/index', fail: () => toast('导航失败，请重试') })
}
export function goSearch(keyword: string) { openPage('/pages/search/index?q=' + encodeURIComponent(keyword), getCurrentPages().slice(-1)[0]?.route === 'pages/search/index') }
export function goBack() {
  if (getCurrentPages().length > 1) uni.navigateBack()
  else goMain('home')
}
