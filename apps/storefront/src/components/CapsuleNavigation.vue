<script setup lang="ts">
import { computed, ref } from 'vue'
import { onHide } from '@dcloudio/uni-app'
import { navigationItems } from './navigation'
import type { NavigationDestination, NavigationItem } from './navigation'
import { confirmedValue } from '../services/input'
// Avoid a native wrapper constraining sticky positioning in WeChat.
defineOptions({ options: { virtualHost: true } })
const props = defineProps<{ active: NavigationItem; id?: string; floatIndex?: number; overlayTop?: string }>()
const emit = defineEmits<{
  navigate: [destination: NavigationDestination]
  search: [query: string]
  'search-visibility': [visible: boolean]
}>()
const searchOpen = ref(false)
const closing = ref(false)
let closeTimer: ReturnType<typeof setTimeout> | undefined
const query = ref('')
const hotTags = ['保温杯', '笔记本', '红茶']
const selectedIndex = computed(() => navigationItems.findIndex(item => item.id === selected.value))
// B-27：在滑块壳内 floatIndex 为面板空间的浮点位置（0–3），高亮块与各项宽度都由它实时驱动，与手指进度同步；壳外页面不传则保持原跳变行为。
const PANEL_ORDER: NavigationItem[] = ['home', 'category', 'cart', 'account']
const PANEL_POS: Record<string, number> = { home: 0, category: 1, cart: 2, account: 3 }
const NAV_POS: Record<string, number> = { home: 0, category: 1, cart: 3, account: 4 }
const floatMode = computed(() => typeof props.floatIndex === 'number')
const activeFloat = computed(() => Math.min(3, Math.max(0, props.floatIndex ?? 0)))
const dominant = computed(() => PANEL_ORDER[Math.round(activeFloat.value)])
const selected = computed(() => searchOpen.value ? 'search' : floatMode.value ? dominant.value : props.active)
function activation(id: NavigationItem) { if (!floatMode.value || id === 'search') return 0; return Math.max(0, 1 - Math.abs(activeFloat.value - PANEL_POS[id])) }
const indicatorStyle = computed(() => {
  if (!floatMode.value) return { transform: 'translateX(' + selectedIndex.value * 50 + '%)' }
  const seg = Math.min(2, Math.floor(activeFloat.value)), frac = activeFloat.value - seg
  const from = NAV_POS[PANEL_ORDER[seg]], to = NAV_POS[PANEL_ORDER[seg + 1]]
  return { left: 'calc(8px + (100% - 16px) * ' + (from + (to - from) * frac) + ' / 6)', transform: 'none' }
})
const itemStyle = (id: NavigationItem) => floatMode.value ? { flexGrow: 1 + activation(id) } : undefined
const placement = computed(() => 'top')
function closeSearch() {
  if (!searchOpen.value || closing.value) return
  closing.value = true
  emit('search-visibility', false)
  closeTimer = setTimeout(() => { searchOpen.value = false; closing.value = false }, 230)
}
function choose(id: NavigationItem) {
  if (searchOpen.value) {
    // 搜索打开时点胶囊任意键只收起搜索，不跳页（防误触）
    if (id === 'search' && !closing.value) closeSearch()
    else closeSearch()
    return
  }
  if (id === 'search') {
    if (closeTimer) { clearTimeout(closeTimer); closing.value = false }
    searchOpen.value = true
    emit('search-visibility', true)
  } else if (id !== props.active) emit('navigate', id)
}
function submitKeyword(keyword: string) {
  const value = keyword.trim()
  if (!value) {
    uni.showToast({ title: '请输入分类或商品关键词', icon: 'none' })
    return
  }
  emit('search', value)
  closeSearch()
}
function submitSearch(event: unknown) { submitKeyword(confirmedValue(event, query.value)) }
onHide(closeSearch)
</script>
<template>
  <view class="capsule-host" :id="id ? id + '-host' : undefined" :class="'capsule-host--' + placement">
    <view class="capsule" :class="{ 'capsule--float': floatMode }" aria-label="主导航">
      <view class="capsule-indicator" :style="indicatorStyle" />
      <button v-for="item in navigationItems" :key="item.id" class="capsule-item" :style="itemStyle(item.id)" :class="['capsule-item--' + item.id, { 'is-active': selected === item.id }]" :aria-label="item.label" :aria-current="selected === item.id ? 'page' : undefined" @click="choose(item.id)">
        <image class="capsule-icon" :src="'/static/icons/' + item.icon + (selected === item.id ? '-blue' : '') + '.svg'" mode="aspectFit" aria-hidden="true" />
        <text v-if="selected === item.id" class="capsule-label">{{ item.label }}</text>
      </button>
    </view>
  </view>
  <view v-if="searchOpen" class="search-overlay" :style="{ top: 'calc(' + (props.overlayTop || '84px') + ' + env(safe-area-inset-top))' }" :class="{ 'is-closing': closing }" @touchmove.stop.prevent @wheel.prevent @click="closeSearch">
    <view class="search-panel" role="dialog" aria-modal="true" aria-label="搜索分类或商品" @click.stop>
      <view class="search-panel-inner">
        <view class="search-field"><image class="search-icon" src="/static/icons/search-blue.svg" aria-hidden="true" /><input v-model="query" class="search-input" placeholder="搜索商品/分类" :focus="searchOpen" :maxlength="80" confirm-type="search" aria-label="搜索关键词" @confirm="submitSearch" /><button v-if="query" class="search-clear" aria-label="清空搜索" @click="query = ''">清空</button></view>
        <text class="search-hot-label">热门搜索</text>
        <view class="search-tags"><button v-for="tag in hotTags" :key="tag" class="search-tag" @click="submitKeyword(tag)">{{ tag }}</button></view>
      </view>
    </view>
    <text class="search-hint">点灰色处收起</text>
  </view>
</template>
<style scoped>
.capsule-host{z-index:20;position:sticky;top:12px;margin:0 24px}.capsule{position:relative;display:flex;align-items:center;padding:6px 8px;height:48px;border-radius:100px;background:var(--brand-blue);box-shadow:0 8px 24px #2563eb26}.capsule-indicator{position:absolute;left:8px;top:6px;bottom:6px;width:calc((100% - 16px)/3);border-radius:100px;background:#fff;transition:transform .28s cubic-bezier(.2,.8,.2,1);pointer-events:none}.capsule-item{z-index:1;position:relative;display:flex;align-items:center;justify-content:center;gap:8px;flex:1;min-width:0;height:48px;margin:0;padding:0;border-radius:100px;background:transparent;color:#fff;line-height:1;transition:flex .28s cubic-bezier(.2,.8,.2,1)}.capsule-item.is-active{flex:2;color:var(--brand-blue)}.capsule--float .capsule-indicator,.capsule--float .capsule-item{transition:none}.capsule-icon{height:20px;width:20px;flex-shrink:0}.capsule-label{font-size:12px;font-weight:700;white-space:nowrap}
/* B-17：遮罩从胶囊下方开始，胶囊全程露在最上层不变暗；面板是悬浮大圆角卡，从胶囊「搜索」格的位置长出 */
.search-overlay{position:fixed;left:0;right:0;bottom:0;top:calc(84px + env(safe-area-inset-top));z-index:100;background:#14141466;display:flex;flex-direction:column;align-items:center;padding:0 24px;animation:mall-fade-in .18s ease-out both;transition:background-color .23s ease}
.search-overlay.is-closing{background:#14141400}
.search-panel{box-sizing:border-box;background:#fff;width:100%;max-width:432px;border-radius:28px;box-shadow:0 18px 44px #14141430;padding:20px;transform-origin:50% -42px;animation:mall-search-grow .38s cubic-bezier(.22,1,.36,1) both}
.search-overlay.is-closing .search-panel{animation:mall-search-shrink .23s ease-in both}
.search-panel-inner{animation:mall-search-content .3s ease-out .1s both}
.search-field{display:flex;align-items:center;gap:10px;padding:6px 14px;background:#f1f3f7;border-radius:100px}
.search-icon{width:18px;height:18px;flex-shrink:0}
.search-input{flex:1;min-width:0;height:36px;font-size:14px;color:var(--ink);background:transparent}
.search-clear{background:transparent;padding:0;margin:0;font-size:12px;color:var(--muted);border-radius:0;line-height:36px;flex-shrink:0;min-width:32px}
.search-hot-label{display:block;margin:16px 2px 10px;font-size:12px;color:var(--muted)}
.search-tags{display:flex;flex-wrap:wrap;gap:8px}
.search-tag{margin:0;padding:0 14px;height:32px;line-height:32px;border-radius:100px;background:#f1f3f7;color:var(--ink);font-size:12px}
.search-hint{margin-top:18px;font-size:12px;color:#ffffffb3}
@keyframes mall-search-grow{from{opacity:0;transform:scale(.45) translateY(8px)}to{opacity:1;transform:scale(1) translateY(0)}}
@keyframes mall-search-shrink{from{opacity:1;transform:scale(1) translateY(0)}to{opacity:0;transform:scale(.5) translateY(6px)}}
@keyframes mall-search-content{from{opacity:0}to{opacity:1}}
@keyframes mall-fade-in{from{opacity:0}to{opacity:1}}
</style>
