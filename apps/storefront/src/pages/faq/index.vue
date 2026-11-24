<script setup lang="ts">
import { computed, ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import StoreLayout from '../../components/StoreLayout.vue'
import CustomerService from '../../components/CustomerService.vue'
import SearchField from '../../components/SearchField.vue'
import { shopConfig, ensureCatalog } from '../../services/catalog'
const query = ref(''); const filter = ref(''); const expanded = ref('')
const faqs = computed(() => shopConfig.faqs.filter(faq => (faq.question + faq.answer).includes(filter.value)))
function search(value: string) { filter.value = value.trim() }
onShow(() => ensureCatalog().catch(error => { uni.showToast({ title: error instanceof Error ? error.message : '帮助信息读取失败', icon: 'none' }) }))
</script>
<template><StoreLayout id="store-layout" title="帮助与客服" eyebrow="WE ARE HERE / HELP" active="account"><view class="sticky-search"><SearchField v-model="query" @submit="search" /></view><view class="section"><text class="block-title">先看看常见问题</text><view v-for="faq in faqs" :key="faq.id" class="faq-item"><button class="faq-question" @click="expanded = expanded === faq.id ? '' : faq.id"><text>{{ faq.question }}</text><text>{{ expanded === faq.id ? '−' : '＋' }}</text></button><text v-if="expanded === faq.id" class="faq-answer">{{ faq.answer }}</text></view><view v-if="!faqs.length" class="empty-state">未找到相关问答，可联系人工客服。</view><view class="divided service-section"><text class="block-title">还需要帮助？</text><text class="small muted">自助问答之后，可转微信官方人工客服。</text><CustomerService /></view></view></StoreLayout></template>
