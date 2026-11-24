'use strict'
const r=require('./runtime')
const FIELDS='_id,phone,nickname,memberNo,level,balance,totalPurchase,totalRecharge,createdAt'
exports.handle=async(e,instance,db,admin)=>{
 if(e.action==='member.list'){
  let query=db.from('users').select(FIELDS).order('createdAt',{ascending:false}).limit(100)
  if(e.phone){if(typeof e.phone!=='string'||! /^1\d{10}$/.test(e.phone))r.fail('INVALID_PHONE','请输入完整手机号');query=query.eq('phone',e.phone)}
  return {members:await r.rows(query)}
 }
 if(e.action==='member.detail'){
  const members=await r.rows(db.from('users').select(FIELDS).eq('_id',e.id).limit(1));if(!members.length)r.fail('MEMBER_NOT_FOUND')
  const [records,logs]=await Promise.all([r.rows(db.from('recharge_records').select('amount,bonusAmount,level,requestKey,createdAt,simulated').eq('userId',e.id).order('createdAt',{ascending:false}).limit(100)),r.rows(db.from('balance_logs').select('type,amount,orderId,balanceAfter,remark,createdAt').eq('userId',e.id).order('createdAt',{ascending:false}).limit(100))])
  return {member:members[0],records,logs}
 }
 r.fail('UNKNOWN_MEMBER_OPERATION')
}
