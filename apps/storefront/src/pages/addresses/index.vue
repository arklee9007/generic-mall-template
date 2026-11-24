<script setup lang="ts">
import { reactive, ref } from 'vue'
import { onLoad, onShow } from '@dcloudio/uni-app'
import StoreLayout from '../../components/StoreLayout.vue'
import { demoState, deleteAddress, saveAddress, refreshCommerce } from '../../services/shop'
import type { Address } from '../../services/shop'
import { goBack, openPage, toast } from '../../services/routes'
import { confirmedValue } from '../../services/input'
import { shopConfig } from '../../services/catalog'
const choosing = ref(false); const editing = ref(false)
const form = reactive({ id: '', name: '', phone: '', region: '普通地区' as Address['region'], detail: '', isDefault: false })
function edit(address?: Address) { Object.assign(form, address || { id: '', name: '', phone: '', region: '普通地区', detail: '', isDefault: false }); editing.value = true }
async function save() { try { await saveAddress({ ...form, id: form.id || undefined }); editing.value = false; toast('地址已保存') } catch (error) { toast(error instanceof Error ? error.message : '保存失败') } }
function choose(address: Address) { if (!choosing.value) return; demoState.selectedAddressId = address.id; goBack() }
function remove(id: string) { uni.showModal({ title: '删除地址', content: '确认删除这条收货地址？', success: result => { if (result.confirm) deleteAddress(id).catch(error => toast(error instanceof Error ? error.message : '删除失败')) } }) }
onLoad(options => { choosing.value = !!options && options.choose === '1' })
onShow(() => refreshCommerce().catch(error => toast(error instanceof Error ? error.message : '地址读取失败')))
</script>
<template><StoreLayout id="store-layout" :title="choosing ? '选择收货地址' : '收货地址'" active="account"><view v-if="!demoState.user" class="empty-state"><text>登录后管理收货地址</text><button class="primary" @click="openPage('/pages/login/index?returnTo=' + encodeURIComponent('/pages/addresses/index' + (choosing ? '?choose=1' : '')))">去登录</button></view><view v-else class="section">
  <template v-if="!editing"><view v-for="address in demoState.addresses" :key="address.id" class="address-card" :class="{ chosen: choosing && address.id === demoState.selectedAddressId }"><view @click="choose(address)"><view class="row between"><text class="line-name">{{ address.name }} {{ address.phone.slice(0, 3) }}****{{ address.phone.slice(-4) }}</text><text v-if="address.isDefault" class="tag">默认</text></view><text class="paragraph small muted">{{ address.region }} · {{ address.detail }}</text></view><view class="row between"><button v-if="choosing" class="text-button blue choose-address" @click="choose(address)">寄到这里</button><button class="text-button" @click="edit(address)">编辑</button><button class="text-button" @click="remove(address.id)">删除</button></view></view><view v-if="!demoState.addresses.length" class="empty-state">还没有地址，请先新增</view><button class="primary full new-address" @click="edit()">新增收货地址</button></template>
  <view v-else class="address-form"><text class="block-title">{{ form.id ? '编辑地址' : '新增地址' }}</text><text class="field-label">收件人</text><input v-model="form.name" @blur="form.name = confirmedValue($event, form.name)" class="form-input address-name" maxlength="30" placeholder="请填写收件人姓名" /><text class="field-label">手机号</text><input v-model="form.phone" @blur="form.phone = confirmedValue($event, form.phone)" class="form-input address-phone" type="number" maxlength="11" placeholder="11位手机号" /><text class="field-label">配送地区</text><view class="chips"><button v-for="region in shopConfig.regions" :key="region" class="chip" :class="{ chosen: form.region === region }" @click="form.region = region">{{ region }}</button></view><text class="field-label">详细地址（含省市区、街道、门牌）</text><textarea v-model="form.detail" @blur="form.detail = confirmedValue($event, form.detail)" class="form-textarea address-detail" maxlength="200" placeholder="请填写省市区、街道和门牌号" /><button class="agreement" :class="{ checked: form.isDefault }" @click="form.isDefault = !form.isDefault">{{ form.isDefault ? '●' : '○' }} 设为默认地址</button><button class="primary full save-address" @click="save">保存地址</button><button class="text-button full" @click="editing = false">取消编辑</button></view>
</view></StoreLayout></template>
