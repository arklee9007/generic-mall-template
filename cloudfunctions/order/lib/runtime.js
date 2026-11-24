'use strict'
const { randomUUID } = require('node:crypto')
const tcb = require('@cloudbase/node-sdk')
// 微信小程序 AppID 由云函数环境变量 WECHAT_APP_ID 提供；未配置时一律拒绝登录。
const APPID = process.env.WECHAT_APP_ID || ''
const uuid = () => randomUUID()
function app() {
  const env = process.env.TCB_ENV || process.env.SCF_NAMESPACE
  if (!env) throw new Error('CLOUD_ENV_UNAVAILABLE')
  return tcb.init({ env,region:process.env.TCB_REGION || 'ap-shanghai' })
}
function fail(code,message=code) { const error=new Error(message);error.code=code;throw error }
function int(value) { const number=Number(value);if(!Number.isSafeInteger(number)) fail('INVALID_INTEGER');return number }
function identity(instance) {
  const info=instance.mallIdentity
  if(!info.openId || info.appId!==APPID) fail('WECHAT_LOGIN_REQUIRED','请在微信小程序中登录')
  return {openid:info.openId,cloudUid:info.uid||null}
}
async function rows(query) { const result=await query;if(result.error) {const error=new Error(result.error.message||'PG_ERROR');error.code=result.error.code;throw error}return result.data||[] }
async function one(db,table,id) { return (await rows(db.from(table).select('*').eq('_id',id).limit(1)))[0]||null }
async function caller(db,who,requirePhone=true) {
  const user=(await rows(db.from('users').select('*').eq('openid',who.openid).limit(1)))[0]
  if(!user) fail('REGISTRATION_REQUIRED','请先登录并绑定手机号')
  if(requirePhone && !user.phone) fail('PHONE_BINDING_REQUIRED','请先绑定手机号')
  for(const key of ['balance','totalPurchase','totalRecharge','version','level']) user[key]=int(user[key]||0)
  return user
}
function plan() {return {locks:[],inserts:[],updates:[],deletes:[]}}
function lock(p,table,row,keys) {
  if(!p.locks.some(l=>l.table===table&&l.id===row._id)) p.locks.push({table,id:row._id,expected:Object.fromEntries(keys.map(k=>[k,row[k]]))})
}
function insert(p,table,data) {p.inserts.push({table,data});return data}
function update(p,table,id,data) {p.updates.push({table,id,data})}
async function commit(db,p) { const {data,error}=await db.rpc('mall_atomic_commit',{plan:p});if(error){const e=new Error(error.message||'COMMIT_FAILED');e.code=error.code;throw e}return data }
async function retry(fn) {for(let attempt=0;attempt<3;attempt++){try{return await fn()}catch(e){if(!['40001','23505'].includes(e.code)||attempt===2)throw e}}}
function invocationIdentity(context){
  // Warm processes can retain a previous invocation's WX_OPENID in process.env.
  // Only the CURRENT platform-supplied context is identity authority. Never merge stale env or event fields.
  let env
  if(typeof context?.environment==='string')env=JSON.parse(context.environment)
  else if(typeof context?.environ==='string')env=Object.fromEntries(context.environ.split(';').filter(s=>s.includes('=')).map(s=>{const i=s.indexOf('=');return [s.slice(0,i),s.slice(i+1)]}))
  else fail('IDENTITY_CONTEXT_UNAVAILABLE')
  return {openId:env.WX_OPENID||'',appId:env.WX_APPID||'',uid:env.TCB_UUID||'',customUserId:env.TCB_CUSTOM_USER_ID||'',isAnonymous:env.TCB_ISANONYMOUS_USER==='true'}
}
function handler(fn) {return async (event,context)=>{try{const instance=app();instance.mallIdentity=invocationIdentity(context);return {ok:true,...await retry(()=>fn(event||{},instance,instance.rdb(),context))}}catch(error){console.warn('Business request rejected',error.code||'INTERNAL_ERROR');return {ok:false,code:error.code||'INTERNAL_ERROR',message:error.code&&error.code!=='INTERNAL_ERROR'?error.message:'服务暂时不可用，请稍后重试'}}}}
module.exports={app,uuid,fail,int,identity,invocationIdentity,rows,one,caller,plan,lock,insert,update,commit,retry,handler}
