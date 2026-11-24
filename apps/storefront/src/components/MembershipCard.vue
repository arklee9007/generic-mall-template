<script setup lang="ts">
import { computed, ref } from 'vue'
import { money } from '../services/catalog'
const props = withDefaults(defineProps<{ member: boolean; tierName?: string; level?: number; discountLabel?: string; balance?: number; totalRecharge?: number; cardBg?: string; cardText?: string; brandWord?: string }>(), { tierName: '普通顾客', level: 0, discountLabel: '不打折', balance: 0, totalRecharge: 0, cardBg: '', cardText: '', brandWord: '' })
defineEmits<{ recharge: [] }>()
const expanded = ref(false)
const cardStyle = computed(() => props.cardBg ? { backgroundImage: 'url(' + props.cardBg + ')', backgroundSize: 'cover', backgroundPosition: 'center' } : undefined)
</script>
<template>
  <view class="membership-card" :class="['membership-card--' + (member ? 'member' : 'basic'), { expanded }]" :style="cardStyle">
    <button class="member-toggle" :aria-expanded="expanded" @click="expanded = !expanded">
      <view class="member-summary"><text class="member-level">{{ member ? tierName : '普通顾客' }}</text><text class="member-summary-balance">{{ member ? '等级 ' + level + ' · 购物 ' + discountLabel : '充值享会员折扣' }}</text></view>
      <text class="member-fold">{{ expanded ? '收起 −' : '展开 ＋' }}</text>
    </button>
    <view class="member-detail" :aria-hidden="!expanded">
      <view class="member-signature"><text class="member-brand">{{ brandWord || tierName }}</text><text class="member-edition">{{ member ? '等级 ' + level : '欢迎光临' }}</text></view>
      <text v-if="cardText" class="member-motto">{{ cardText }}</text>
      <template v-if="!member">
        <view class="member-basic-benefits"><text>充值成为会员，余额可用于购物抵扣</text><text>累计充值实付金额定级，只升不降</text><text>购物享会员折扣</text></view>
        <button class="member-action" @click="$emit('recharge')">去充值 →</button>
      </template>
      <template v-else>
        <view class="member-wallet"><text class="member-label">店铺余额</text><text class="member-amount">¥{{ money(balance) }}</text></view>
        <view class="member-wallet"><text class="member-label">累计充值（实付）</text><text class="member-amount">¥{{ money(totalRecharge) }}</text></view>
        <view class="member-progress"><text class="member-label">会员权益</text><text class="member-progress-label">购物 {{ discountLabel }} · 余额可用于结算抵扣</text></view>
        <button class="member-action" @click="$emit('recharge')">去充值 →</button>
      </template>
    </view>
  </view>
</template>
