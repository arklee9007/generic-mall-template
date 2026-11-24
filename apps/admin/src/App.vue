<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount } from 'vue'
import { ElButton, ElInput, ElForm, ElFormItem, ElAlert, ElDialog } from 'element-plus'
import 'element-plus/dist/index.css'
import { callAdmin, hasStoredSession, setRemember, type Dashboard } from './api'
import CatalogManager from './CatalogManager.vue'
import HomeManager from './HomeManager.vue'
import OrderManager from './OrderManager.vue'
import MemberManager from './MemberManager.vue'
import MembershipManager from './MembershipManager.vue'
import FreightManager from './FreightManager.vue'
import FaqManager from './FaqManager.vue'
import SystemManager from './SystemManager.vue'
import AuditManager from './AuditManager.vue'
const username = ref(''), password = ref(''), remember = ref(false), loggedIn = ref(false), busy = ref(false), error = ref(''), dashboard = ref<Dashboard>(), changeOpen = ref(false), oldPassword = ref(''), newPassword = ref('')
const shopTitle = ref('商城后台')
try { username.value = localStorage.getItem('admin-username') || '' } catch { username.value = '' }
const menuOpen = ref(false)
const view = ref('dashboard')
function expired() { loggedIn.value = false; dashboard.value = undefined; menuOpen.value = false; changeOpen.value = false; view.value = 'dashboard'; password.value = ''; oldPassword.value = ''; newPassword.value = ''; error.value = '登录已失效，请重新登录' }
onMounted(() => { window.addEventListener('admin-session-expired', expired); if (hasStoredSession()) { refresh().then(() => { loggedIn.value = true }).catch(() => { loggedIn.value = false; error.value = '' }) } })
onBeforeUnmount(() => window.removeEventListener('admin-session-expired', expired))
async function execute(task: () => Promise<void>) { busy.value = true; error.value = ''; try { await task() } catch (e) { error.value = e instanceof Error ? e.message : '后台服务暂不可用' } finally { busy.value = false } }
async function refresh() {
  const reply = await callAdmin('dashboard'); dashboard.value = reply.dashboard
  try {
    const sys = await callAdmin<{ config: { shopName: string; shopConfig?: { brandWord?: string } } }>('system.get')
    shopTitle.value = sys.config?.shopConfig?.brandWord?.trim() || sys.config?.shopName?.trim() || '商城后台'
  } catch { /* 店名读不到时用默认字标，不影响工作台 */ }
}
function login() { execute(async () => { setRemember(remember.value); await callAdmin('login', { username: username.value, password: password.value, remember: remember.value }); try { localStorage.setItem('admin-username', username.value) } catch { /* ignore */ } password.value = ''; await refresh(); loggedIn.value = true }) }
function logout() { execute(async () => { await callAdmin('logout'); loggedIn.value = false; dashboard.value = undefined }) }
function changePassword() { execute(async () => { await callAdmin('changePassword', { oldPassword: oldPassword.value, newPassword: newPassword.value }); oldPassword.value = ''; newPassword.value = ''; changeOpen.value = false; loggedIn.value = false; dashboard.value = undefined }) }
</script>
<template>
  <div v-if="!loggedIn" class="login-layout">
    <section class="brand"><div class="wordmark">{{ shopTitle }}</div><p>管理后台</p><h1>店铺日常，<br>从这里开始。</h1><p class="caption">管理员专用入口</p></section>
    <main class="login-main"><div class="login-panel"><p class="eyebrow">店铺运营</p><h2>管理员登录</h2><p class="muted">使用管理员账号与密码进入工作台</p>
      <ElAlert v-if="error" :title="error" type="error" :closable="false" role="alert"/>
      <ElForm label-position="top" @submit.prevent="login">
        <ElFormItem label="账号"><ElInput v-model="username" name="username" autocomplete="username" aria-label="账号" maxlength="80"/></ElFormItem>
        <ElFormItem label="密码"><ElInput v-model="password" name="password" type="password" autocomplete="current-password" aria-label="密码" maxlength="128"/></ElFormItem>
        <label class="checkbox-label remember-row"><input v-model="remember" type="checkbox" aria-label="记住我"/>记住我（30 天内免登录）</label>
        <ElButton type="primary" native-type="submit" :loading="busy" class="login-button">登录</ElButton>
      </ElForm><p class="muted security-note">连续登录失败 5 次将锁定 30 分钟</p>
    </div></main>
  </div>
  <div v-else class="layout"><button v-if="menuOpen" class="menu-backdrop" aria-label="关闭菜单" @click="menuOpen=false"/><aside :class="{open:menuOpen}"><div class="logo">{{ shopTitle }}</div><p>管理后台</p><nav><button :class="{selected:view==='dashboard'}" @click="view='dashboard';menuOpen=false">工作台</button><button :class="{selected:view==='catalog'}" @click="view='catalog';menuOpen=false">商品管理</button><button :class="{selected:view==='home'}" @click="view='home';menuOpen=false">首页管理</button><button :class="{selected:view==='orders'}" @click="view='orders';menuOpen=false">订单管理</button><button :class="{selected:view==='members'}" @click="view='members';menuOpen=false">会员管理</button><button :class="{selected:view==='membership'}" @click="view='membership';menuOpen=false">会员设置</button><button :class="{selected:view==='freight'}" @click="view='freight';menuOpen=false">运费模板</button><button :class="{selected:view==='faq'}" @click="view='faq';menuOpen=false">FAQ管理</button><button :class="{selected:view==='system'}" @click="view='system';menuOpen=false">系统设置</button><button :class="{selected:view==='audit'}" @click="view='audit';menuOpen=false">操作留痕</button></nav></aside>
    <main class="workspace"><header><div class="header-title"><ElButton class="mobile-menu" aria-label="打开菜单" @click="menuOpen=true"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 6h16M4 12h16M4 18h16"/></svg></ElButton><strong>工作台</strong></div><div class="header-actions"><ElButton @click="changeOpen=true">修改密码</ElButton><ElButton @click="logout" :loading="busy">退出登录</ElButton></div></header>
      <section v-if="view==='dashboard'" class="content"><p class="eyebrow">店铺运营</p><div class="section-heading"><h1>店铺概况</h1><ElButton @click="execute(refresh)" :loading="busy">刷新数据</ElButton></div>
        <ElAlert v-if="error" :title="error" type="error" :closable="false" role="alert"/>
        <div v-if="dashboard" class="metrics"><article><p>今日订单数</p><strong data-testid="today-orders">{{dashboard.todayOrders}}</strong><span>笔订单</span></article><article><p>今日销售额</p><strong data-testid="today-sales">¥{{(dashboard.todaySales/100).toFixed(2)}}</strong><span>今日已付款订单应付合计</span><span data-testid="today-refunds">今日退款 ¥{{((dashboard.todayRefunds||0)/100).toFixed(2)}}</span></article><article><p>待发货数</p><strong data-testid="pending-ship">{{dashboard.pendingShip}}</strong><span>待处理订单</span></article><article><p>本月销售额</p><strong data-testid="month-sales">¥{{((dashboard.monthSales||0)/100).toFixed(2)}}</strong><span>本月已付款订单应付合计</span></article><article><p>本月退款金额</p><strong data-testid="month-refunds">¥{{((dashboard.monthRefunds||0)/100).toFixed(2)}}</strong><span>本月已执行退款合计</span></article></div>
        <p v-if="dashboard" class="muted">上海时间 · 更新于 {{new Date(dashboard.checkedAt).toLocaleString('zh-CN',{timeZone:'Asia/Shanghai'})}}</p>
      </section>
      <CatalogManager v-else-if="view==='catalog'"/>
      <HomeManager v-else-if="view==='home'"/>
      <OrderManager v-else-if="view==='orders'"/>
      <MemberManager v-else-if="view==='members'"/>
      <MembershipManager v-else-if="view==='membership'"/>
      <FreightManager v-else-if="view==='freight'"/>
      <FaqManager v-else-if="view==='faq'"/>
      <SystemManager v-else-if="view==='system'"/>
      <AuditManager v-else-if="view==='audit'"/>
    </main>
    <ElDialog v-model="changeOpen" title="修改管理员密码" width="min(440px, calc(100vw - 32px))"><p class="muted">改密后所有登录会话失效，请重新登录。</p><ElForm label-position="top" @submit.prevent="changePassword"><ElFormItem label="原密码"><ElInput v-model="oldPassword" type="password" aria-label="原密码" autocomplete="current-password"/></ElFormItem><ElFormItem label="新密码"><ElInput v-model="newPassword" type="password" aria-label="新密码" autocomplete="new-password"/></ElFormItem><p class="muted">至少16位，含大写、小写、数字及符号</p><ElAlert v-if="error" :title="error" type="error" :closable="false"/><ElButton native-type="submit" type="primary" :loading="busy">确认修改</ElButton></ElForm></ElDialog>
  </div>
</template>
<style>
:root{--brand-blue:#2563EB;--el-color-primary:#2563EB;font-family:'Microsoft YaHei',sans-serif;color:#141414;background:#f3f5f9}*{box-sizing:border-box}body{margin:0}.login-layout{display:flex;min-height:100vh}.layout{display:flex;height:100dvh;overflow:hidden}.brand{width:44%;background:var(--brand-blue);color:white;padding:64px 7%}.wordmark{font:900 60px Impact,sans-serif}.brand h1{font-size:42px;line-height:1.5;margin:130px 0 24px}.brand p{font-size:14px}.caption{opacity:.75}.login-main{flex:1;display:grid;place-items:center;background:white;padding:48px}.login-panel{width:100%;max-width:390px}h2{font-size:28px;margin:14px 0}.muted{color:#677185;font-size:13px;line-height:1.8}.eyebrow{font-size:11px;color:var(--brand-blue);letter-spacing:2px}.login-panel .el-form{margin-top:32px}.el-input{--el-input-height:44px}.login-button{width:100%;height:44px}.security-note{margin-top:24px}.remember-row{display:flex;align-items:center;gap:8px;font-size:13px;color:#3d4658;margin:2px 0 16px;cursor:pointer}.remember-row input{width:auto;margin:0}.logo{font:900 34px Impact,sans-serif;color:var(--brand-blue)}aside{width:240px;flex-shrink:0;background:white;padding:32px 24px;border-right:1px solid #e5e9f0;position:sticky;top:0;height:100dvh;overflow-y:auto}aside p{font-size:12px;color:#596274;margin:8px 0 48px}nav button{border:0;width:100%;text-align:left;padding:16px;font:inherit;border-radius:8px;cursor:pointer}.selected{background:var(--brand-blue);color:white}.workspace{flex:1;min-width:0;height:100dvh;overflow-y:auto;display:flex;flex-direction:column}header{height:80px;border-bottom:1px solid #e5e9f0;padding:24px 32px;display:flex;align-items:center;justify-content:space-between;background:white;position:sticky;top:0;z-index:15;flex-shrink:0}.content{padding:40px 32px;max-width:1200px}.section-heading{display:flex;align-items:center;justify-content:space-between}.section-heading h1{font-size:30px}.metrics{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:20px;margin:24px 0}.metrics article{background:white;border:1px solid #e3e8ef;border-radius:10px;padding:28px}.metrics p{font-size:14px;color:#596274;margin:0 0 24px}.metrics strong{display:block;font-size:36px;font-variant-numeric:tabular-nums}.metrics span{display:block;font-size:12px;color:#677185;margin-top:12px}.el-alert{margin:16px 0}@media(max-width:800px){.login-layout{flex-direction:column}.brand{display:block;width:100%;padding:26px 24px 18px}.wordmark{font-size:38px}.brand h1{font-size:22px;line-height:1.4;margin:12px 0 6px}.login-main{flex:none}aside{width:180px;padding:24px 16px}.metrics{grid-template-columns:1fr}.content{padding:24px}.metrics strong{font-size:28px}}
</style>
<style>
.header-title,.header-actions{display:flex;align-items:center;gap:12px}.header-actions .el-button+.el-button{margin-left:0}.mobile-menu{display:none}.menu-backdrop{display:none}
@media(max-width:768px){.login-main{padding:28px 24px}.layout aside{overflow-y:auto;position:fixed;inset:0 auto 0 0;width:260px;max-width:85vw;z-index:30;transform:translateX(-100%);transition:transform .2s}.layout aside.open{transform:translateX(0)}.menu-backdrop{display:block;position:fixed;inset:0;z-index:20;background:#14141470;border:0}.mobile-menu{display:inline-flex;padding:8px}.workspace header{height:auto;min-height:72px;padding:16px;gap:12px;flex-wrap:wrap}.header-title{gap:8px}.header-actions{gap:8px}.header-actions .el-button{padding:8px 10px}.content{padding:24px 16px}.metrics{grid-template-columns:1fr}.metrics article{padding:24px}.el-dialog{max-height:calc(100dvh - 40px);overflow:auto}.el-overlay-dialog{overflow-x:hidden}}
</style>
