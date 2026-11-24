'use strict'
const r=require('./runtime')
function int(v,min,max){const n=Number(v);if(!Number.isSafeInteger(n)||n<min||n>max)r.fail('INVALID_MEMBERSHIP_INPUT','数值超出范围');return n}
function imageUrl(v){if(typeof v!=='string'||v.length>1200)r.fail('INVALID_CARD_BG','会员卡背景图地址不正确');const u=v.trim();if(u&&!/^https:\/\//.test(u)&&!u.startsWith('/static/'))r.fail('INVALID_CARD_BG','会员卡背景图须为HTTPS地址或站内图片');return u}
function packages(v){
  if(!Array.isArray(v)||v.length>20)r.fail('INVALID_PACKAGES','充值套餐最多 20 个')
  const seen=new Set()
  return v.map(p=>{
    if(!p||typeof p!=='object')r.fail('INVALID_PACKAGES','充值套餐格式不正确')
    const amount=int(p.amount,100,100000000),bonus=int(p.bonus??0,0,100000000)
    if(bonus>amount)r.fail('INVALID_PACKAGES','赠送金额不能超过充值金额')
    if(typeof p.label!=='string'||!p.label.trim()||p.label.trim().length>40)r.fail('INVALID_PACKAGES','套餐名称须为 40 字以内')
    if(seen.has(amount))r.fail('INVALID_PACKAGES','充值套餐金额不可重复')
    seen.add(amount)
    return {amount,bonus,label:p.label.trim()}
  })
}
async function tiers(db){return r.rows(db.from('member_tiers').select('*').order('level'))}
exports.handle=async(e,instance,db,admin)=>{
 if(e.action==='membership.list'){
  const s=await r.one(db,'settings','global'),m=(s?.shopConfig&&s.shopConfig.member)||{}
  return {tiers:await tiers(db),config:{enabled:m.enabled!==false,rechargeEnabled:m.rechargeEnabled!==false,packages:Array.isArray(m.packages)?m.packages:[]}}
 }
 if(e.action==='membership.config.save'){
  const d=e.data||{}
  if(typeof d.enabled!=='boolean'||typeof d.rechargeEnabled!=='boolean')r.fail('INVALID_MEMBERSHIP_INPUT','会员开关不正确')
  const value={member:{enabled:d.enabled,rechargeEnabled:d.rechargeEnabled,packages:packages(d.packages||[])}}
  const {data,error}=await db.rpc('mall_admin_membership',{p_admin:admin._id,p_op:'config.save',p_id:'global',p_data:value});if(error)r.fail('MEMBERSHIP_REJECTED','会员设置保存失败');return data
 }
 if(e.action==='membership.tier.save'){
  const d=e.data||{}
  const value={level:int(d.level,1,20),name:typeof d.name==='string'&&d.name.trim()&&d.name.trim().length<=20?d.name.trim():r.fail('INVALID_TIER_NAME','档位名称须为 1–20 字'),threshold:int(d.threshold,0,9007199254740991),discountBps:int(d.discountBps,1000,10000),cardBg:imageUrl(d.cardBg||''),cardText:typeof d.cardText==='string'&&d.cardText.length<=200?d.cardText.trim():'',sort:int(d.sort??0,0,100000),enabled:d.enabled!==false}
  const all=await tiers(db),next=all.filter(t=>r.int(t.level)!==value.level);next.push(value);next.sort((a,b)=>a.level-b.level)
  for(let i=1;i<next.length;i++)if(r.int(next[i].threshold)<=r.int(next[i-1].threshold))r.fail('INVALID_TIER_THRESHOLD','高等级的累计充值门槛须高于低等级')
  const {data,error}=await db.rpc('mall_admin_membership',{p_admin:admin._id,p_op:'tier.save',p_id:'tier-'+value.level,p_data:value});if(error)r.fail('MEMBERSHIP_REJECTED','档位保存失败');return data
 }
 if(e.action==='membership.tier.delete'){
  if(typeof e.id!=='string'||!/^tier-\d{1,2}$/.test(e.id))r.fail('INVALID_TIER_ID')
  const {data,error}=await db.rpc('mall_admin_membership',{p_admin:admin._id,p_op:'tier.delete',p_id:e.id,p_data:{}});if(error)r.fail('MEMBERSHIP_REJECTED','档位删除失败');return data
 }
 if(e.action==='membership.setLevel'){
  if(typeof e.id!=='string'||!e.id)r.fail('INVALID_MEMBER')
  const level=int((e.data||{}).level,0,20)
  if(level>0){const all=await tiers(db);if(!all.some(t=>r.int(t.level)===level))r.fail('TIER_NOT_FOUND','该等级不存在，请先在会员设置里建档位')}
  const {data,error}=await db.rpc('mall_admin_membership',{p_admin:admin._id,p_op:'setLevel',p_id:e.id,p_data:{level}});if(error)r.fail('MEMBERSHIP_REJECTED','等级指定失败');return data
 }
 r.fail('UNKNOWN_MEMBERSHIP_OPERATION')
}
