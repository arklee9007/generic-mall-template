<script setup lang="ts">
import { onLaunch } from '@dcloudio/uni-app'
import project from '../../../config/project.json'
onLaunch(() => {
  // #ifdef MP-WEIXIN
  if (!wx.cloud) throw new Error('当前微信基础库不支持云开发')
  wx.cloud.init({ env: project.cloudbase.envId, traceUser: true })
  // #endif
  console.info('通用商城模板已启动')
})
</script>
<style>
@import './styles/shop.css';
page { --brand-blue: #2563EB; --ink: #141414; --muted: #596274; --paper: #f3f5f9; background: white; color: var(--ink); font-family: 'Microsoft YaHei', sans-serif; }
button::after { border: 0; }
</style>

