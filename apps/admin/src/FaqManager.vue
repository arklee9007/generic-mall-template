<script setup lang="ts">
import {ref,onMounted} from 'vue'
import {ElButton,ElAlert,ElDialog} from 'element-plus'
import {callAdmin} from './api'
type Faq={_id:string;question:string;answer:string;sort:number;visible:boolean}
const items=ref<Faq[]>([]),busy=ref(false),error=ref(''),notice=ref(''),editor=ref(false),form=ref({_id:'',question:'',answer:'',sort:0,visible:false})
async function run(fn:()=>Promise<void>){if(busy.value)return;busy.value=true;error.value='';notice.value='';try{await fn()}catch(e){error.value=e instanceof Error?e.message:'操作失败'}finally{busy.value=false}}
async function load(){items.value=(await callAdmin<{faqs:Faq[]}>('faq.list')).faqs}
function open(f?:Faq){form.value=f?{...f}:{_id:'',question:'',answer:'',sort:0,visible:false};editor.value=true}
function save(){run(async()=>{await callAdmin('faq.save',{id:form.value._id||undefined,data:form.value});editor.value=false;await load();notice.value='FAQ已保存'})}
function remove(id:string){if(confirm('确认删除此FAQ？'))run(async()=>{await callAdmin('faq.delete',{id});await load();notice.value='FAQ已删除'})}
onMounted(()=>run(load))
</script>
<template><section class="content faq-manager"><div class="section-heading"><div><p class="eyebrow">CUSTOMER SUPPORT</p><h1>FAQ管理</h1></div><ElButton @click="open()">新增FAQ</ElButton></div><ElAlert v-if="error" :title="error" type="error" :closable="false"/><ElAlert v-if="notice" :title="notice" type="success" :closable="false"/><ElButton @click="run(load)" :loading="busy">刷新FAQ</ElButton><article v-for="f in items" :key="f._id" class="settings-card faq-card" :data-faq-id="f._id"><p class="muted">排序{{f.sort}} · {{f.visible?'显示':'隐藏'}}</p><h3>{{f.question}}</h3><p class="faq-answer">{{f.answer}}</p><div class="action-row"><ElButton @click="open(f)">编辑FAQ</ElButton><ElButton @click="remove(f._id)">删除FAQ</ElButton></div></article><ElDialog v-model="editor" title="FAQ资料" width="min(600px, calc(100vw - 24px))"><ElAlert v-if="error" :title="error" type="error" :closable="false"/><form class="admin-form" @submit.prevent="save"><label>问题<input v-model="form.question" aria-label="FAQ问题" required maxlength="200"/></label><label>答案<textarea v-model="form.answer" aria-label="FAQ答案" required maxlength="3000" rows="6"/></label><label>排序<input v-model.number="form.sort" aria-label="FAQ排序" type="number" min="0" max="100000" required/></label><label class="checkbox-label"><input v-model="form.visible" aria-label="FAQ显示" type="checkbox"/>显示此问题</label><ElButton native-type="submit" type="primary" :loading="busy">保存FAQ</ElButton></form></ElDialog></section></template>
<style>.faq-answer{white-space:pre-wrap;overflow-wrap:anywhere}.faq-card h3{overflow-wrap:anywhere;line-height:1.7}@media(max-width:768px){.faq-manager .section-heading{gap:12px;flex-wrap:wrap}.faq-manager .section-heading h1{font-size:26px}}</style>
