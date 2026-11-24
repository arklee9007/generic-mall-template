export type NavigationDestination = 'home' | 'category' | 'cart' | 'account'
export type NavigationItem = NavigationDestination | 'search'
export const navigationItems: { id: NavigationItem; label: string; icon: string }[] = [
  { id: 'home', label: '首页', icon: 'house' },
  { id: 'category', label: '分类', icon: 'grid-2x2' },
  { id: 'search', label: '搜索', icon: 'search' },
  { id: 'cart', label: '购物车', icon: 'shopping-bag' },
  { id: 'account', label: '我的', icon: 'user-round' },
]
