<script setup lang="ts">
defineOptions({ options: { virtualHost: true } })
import { ref, watch } from 'vue'
import { confirmedValue } from '../services/input'
const props = defineProps<{ modelValue: string }>()
const emit = defineEmits<{ 'update:modelValue': [value: string]; submit: [value: string] }>()
const model = ref(props.modelValue)
watch(() => props.modelValue, value => { if (model.value !== value) model.value = value })
watch(model, value => emit('update:modelValue', value))
function blur(event: unknown) {
  model.value = confirmedValue(event, model.value)
  emit('update:modelValue', model.value)
}
function confirm(event: unknown) {
  const value = confirmedValue(event, model.value)
  model.value = value
  emit('update:modelValue', value)
  emit('submit', value)
}
</script>
<template><view class="catalog-search"><image src="/static/icons/search-blue.svg" class="small-icon" /><input v-model="model" class="catalog-search-input" placeholder="搜索分类、商品或关键词" maxlength="80" confirm-type="search" @confirm="confirm" @blur="blur" /><button v-if="model" class="text-button" aria-label="清空关键词" @click="model = ''">清空</button><button class="text-button blue" @click="emit('submit', model)">搜索</button></view></template>
