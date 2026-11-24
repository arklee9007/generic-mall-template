<script setup lang="ts">
import { onLoad } from '@dcloudio/uni-app'
import { requestMainPanel } from '../../services/mainPanel'
// B-27：主页已并入滑块壳（pages/index），本页仅作旧链接落点，立即转交壳并指定面板。
onLoad(options => { requestMainPanel('category', options && typeof options.id === 'string' ? options.id : undefined); uni.reLaunch({ url: '/pages/index/index' }) })
</script>
<template><view /></template>
