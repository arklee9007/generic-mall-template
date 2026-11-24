'use strict'
const r=require('./runtime')
exports.main=r.handler(async(event,instance,db)=>{
  const who=r.identity(instance)
  let user=await r.caller(db,who,false).catch(e=>{if(e.code==='REGISTRATION_REQUIRED')return null;throw e})
  if(!user){
    const p=r.plan();const id=r.uuid()
    r.insert(p,'users',{_id:id,openid:who.openid,cloudUid:who.cloudUid})
    r.insert(p,'member_accounts',{userId:id})
    await r.commit(db,p);user=await r.caller(db,who,false)
  }
  const action=event.action||'login'
  if(action==='bindPhone'){
    if(typeof event.phone!=='string'||!/^1\d{10}$/.test(event.phone))r.fail('INVALID_PHONE','请输入正确的11位手机号')
    if(event.agreed!==true)r.fail('AGREEMENT_REQUIRED','请先同意绑定手机号说明')
    const existing=(await r.rows(db.from('users').select('_id').eq('phone',event.phone).limit(1)))[0]
    if(existing&&existing._id!==user._id)r.fail('PHONE_ALREADY_BOUND','该手机号已绑定其他账户')
    const p=r.plan();r.lock(p,'users',user,['version','phone'])
    r.update(p,'users',user._id,{phone:event.phone,version:user.version+1})
    await r.commit(db,p);user=await r.caller(db,who,false)
  }else if(!['login','me'].includes(action))r.fail('UNKNOWN_ACTION')
  return {user:{_id:user._id,phone:user.phone,nickname:user.nickname,memberNo:user.memberNo,level:user.level,balance:user.balance,totalPurchase:user.totalPurchase},needsPhone:!user.phone,smsEnabled:false}
})
