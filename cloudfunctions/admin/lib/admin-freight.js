'use strict'
const r=require('./runtime'),c=require('./commerce')
exports.handle=async(e,instance,db,admin)=>{
 if(e.action==='freight.list')return {templates:await r.rows(db.from('freight_templates').select('*').order('name'))}
 if(e.action==='freight.preview'){const template=await r.one(db,'freight_templates',e.id);if(!template)r.fail('TEMPLATE_NOT_FOUND');if(typeof e.region!=='string'||!e.region||e.region.length>200)r.fail('INVALID_REGION');return {amount:c.freight(template,e.region)}}
 const op=e.action.slice(8),id=e.id||r.uuid(),d=e.data||{};let value
 if(typeof id!=='string'||! /^[a-zA-Z0-9_-]{1,80}$/.test(id))r.fail('INVALID_ID')
 if(op==='save'){
  if(typeof d.name!=='string'||!d.name.trim()||d.name.length>120||!Array.isArray(d.rules)||d.rules.length<1||d.rules.length>30)r.fail('INVALID_FREIGHT_RULES')
  const rules=d.rules.map(rule=>{
   if(!['normal','extra','no_delivery'].includes(rule.type)||!Array.isArray(rule.regions)||!rule.regions.length||rule.regions.length>40||!rule.regions.every(x=>typeof x==='string'&&x.trim()&&x.length<=40)||!Number.isSafeInteger(rule.price)||rule.price<0||rule.price>100000000)r.fail('INVALID_FREIGHT_RULES','请检查地区与价格')
   return {type:rule.type,regions:[...new Set(rule.regions.map(x=>x.trim()))],price:rule.type==='no_delivery'?0:rule.price}
  })
  if(rules.filter(x=>x.type==='normal'&&x.regions.includes('*')).length!==1||rules.some(x=>x.type!=='normal'&&x.regions.includes('*')))r.fail('INVALID_FREIGHT_RULES','须有且仅有一个普通地区通用价')
  // Specific normal prices (e.g. Hong Kong) precede the universal fallback consumed by commerce.freight.
  rules.sort((a,b)=>Number(a.type==='normal'&&a.regions.includes('*'))-Number(b.type==='normal'&&b.regions.includes('*')))
  value={name:d.name.trim(),rules,isDefault:d.isDefault===true}
 }else if(op==='delete')value={};else r.fail('UNKNOWN_FREIGHT_OPERATION')
 const {data,error}=await db.rpc('mall_admin_freight',{p_admin:admin._id,p_op:op,p_id:id,p_data:value});if(error)r.fail('FREIGHT_REJECTED',error.code==='23503'?'模板仍被商品或赠品使用，不能删除':error.message?.includes('DEFAULT_TEMPLATE_REQUIRED')?'必须保留一个默认模板，请先指定其他模板为默认':'运费模板操作被拒绝');return data
}
