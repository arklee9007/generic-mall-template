'use strict'
const r=require('./runtime'),security=require('./admin-security')
async function rpc(db,name,args={}){const {data,error}=await db.rpc(name,args);if(error)r.fail('ADMIN_STORAGE_ERROR','后台数据服务暂不可用');return data}
async function authenticated(db,token){
  if(typeof token!=='string'||! /^[a-f0-9]{64}$/.test(token))r.fail('ADMIN_TOKEN_REQUIRED','请重新登录')
  const session=await r.one(db,'admin_sessions',security.tokenHash(token))
  if(!session||session.revokedAt||Date.parse(session.expiresAt)<=Date.now())r.fail('ADMIN_TOKEN_INVALID','登录已失效')
  const admin=await r.one(db,'admins',session.adminId)
  if(!admin)r.fail('ADMIN_TOKEN_INVALID','登录已失效')
  return {admin,session}
}
exports.main=async(event)=>{
  try{
    const e=event&&typeof event==='object'?event:{},db=r.app().rdb()
    if(e.action==='login'){
      const username=typeof e.username==='string'?e.username.slice(0,80):''
      if(process.env.ADMIN_INITIAL_USERNAME&&process.env.ADMIN_INITIAL_PASSWORD_HASH)await rpc(db,'mall_admin_bootstrap',{p_username:process.env.ADMIN_INITIAL_USERNAME,p_hash:process.env.ADMIN_INITIAL_PASSWORD_HASH})
      const admin=(await r.rows(db.from('admins').select('*').eq('username',username).limit(1)))[0]
      const accepted=security.verifyPassword(e.password,admin?.passwordHash),token=security.newToken()
      const result=await rpc(db,'mall_admin_login',{p_username:username,p_expected:admin?.passwordHash||'',p_accepted:accepted,p_session:security.tokenHash(token)})
      if(!result.accepted)r.fail(result.code,'账号或密码错误，或账号已锁定')
      let expiresIn=86400
      if(e.remember===true){const until=new Date(Date.now()+2592000000).toISOString();const {error:extendError}=await db.from('admin_sessions').update({expiresAt:until}).eq('_id',security.tokenHash(token));if(!extendError)expiresIn=2592000}
      return {ok:true,token,username:result.username,expiresIn}
    }
    const {admin,session}=await authenticated(db,e.token)
    if(typeof e.action==='string'&&e.action.startsWith('catalog.'))return {ok:true,...await require('./admin-catalog').handle(e,r.app(),db,admin)}
    if(typeof e.action==='string'&&e.action.startsWith('home.'))return {ok:true,...await require('./admin-home').handle(e,r.app(),db,admin)}
    if(typeof e.action==='string'&&e.action.startsWith('order.'))return {ok:true,...await require('./admin-orders').handle(e,r.app(),db,admin)}
    if(typeof e.action==='string'&&e.action.startsWith('refund.'))return {ok:true,...await require('./admin-orders').handleRefund(e,r.app(),db,admin)}
    if(typeof e.action==='string'&&e.action.startsWith('member.'))return {ok:true,...await require('./admin-members').handle(e,r.app(),db,admin)}
    if(typeof e.action==='string'&&e.action.startsWith('membership.'))return {ok:true,...await require('./admin-membership').handle(e,r.app(),db,admin)}
    if(typeof e.action==='string'&&e.action.startsWith('freight.'))return {ok:true,...await require('./admin-freight').handle(e,r.app(),db,admin)}
    if(typeof e.action==='string'&&e.action.startsWith('faq.'))return {ok:true,...await require('./admin-faq').handle(e,r.app(),db,admin)}
    if(typeof e.action==='string'&&e.action.startsWith('system.'))return {ok:true,...await require('./admin-system').handle(e,r.app(),db,admin)}
    if(typeof e.action==='string'&&e.action.startsWith('audit.'))return {ok:true,...await require('./admin-audit').handle(e,r.app(),db,admin)}
    if(typeof e.action==='string'&&e.action.startsWith('upload.'))return {ok:true,...await require('./upload-service').handle(e,r.app(),db,admin)}
    if(e.action==='dashboard')return {ok:true,dashboard:await rpc(db,'mall_admin_dashboard')}
    if(e.action==='logout'){
      const {error}=await db.from('admin_sessions').update({revokedAt:new Date().toISOString()}).eq('_id',session._id)
      if(error)r.fail('ADMIN_STORAGE_ERROR');return {ok:true}
    }
    if(e.action==='changePassword'){
      if(!security.verifyPassword(e.oldPassword,admin.passwordHash))r.fail('INVALID_CREDENTIALS','原密码错误')
      if(!security.strong(e.newPassword)||e.newPassword===e.oldPassword)r.fail('WEAK_PASSWORD','新密码至少16位，须含大小写、数字及符号，且与原密码不同')
      if(!await rpc(db,'mall_admin_change_password',{p_admin:admin._id,p_expected:admin.passwordHash,p_hash:security.hashPassword(e.newPassword)}))r.fail('PASSWORD_CHANGED','账号状态已变化，请重新登录')
      return {ok:true,relogin:true}
    }
    r.fail('UNKNOWN_ACTION')
  }catch(error){return {ok:false,code:error.code||'INTERNAL_ERROR',message:error.code&&error.code!=='INTERNAL_ERROR'?error.message:'后台服务暂不可用'}}
}

