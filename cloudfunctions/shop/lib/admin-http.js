'use strict'
const admin=require('./admin')
// 后台网页来源由云函数环境变量 ADMIN_ORIGIN 提供（精确匹配）；未配置时 HTTP 入口一律拒绝。
const ORIGIN=process.env.ADMIN_ORIGIN || ''
exports.main=async(event,context)=>{
  // Retain the existing SDK entry; HTTP transport never bypasses core auth.
  if(!event||typeof event.httpMethod!=='string')return admin.main(event,context)
  const headers=Object.fromEntries(Object.entries(event.headers||{}).map(([k,v])=>[k.toLowerCase(),v]))
  const cors=headers.origin===ORIGIN?{'Access-Control-Allow-Origin':ORIGIN,'Vary':'Origin','Access-Control-Allow-Methods':'POST, OPTIONS','Access-Control-Allow-Headers':'Content-Type','Access-Control-Max-Age':'300'}:{}
  const reply=(statusCode,body)=>({statusCode,headers:{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store',...cors},body:body===null?'':JSON.stringify(body),isBase64Encoded:false})
  if(headers.origin!==ORIGIN)return reply(403,{ok:false,code:'ORIGIN_NOT_ALLOWED',message:'不支持的请求来源'})
  if(event.httpMethod==='OPTIONS')return reply(204,null)
  if(event.httpMethod!=='POST')return reply(405,{ok:false,code:'METHOD_NOT_ALLOWED'})
  if(!/^application\/json(?:;|$)/i.test(headers['content-type']||''))return reply(415,{ok:false,code:'JSON_REQUIRED'})
  if(typeof event.body!=='string'||Buffer.byteLength(event.body)>3145728)return reply(413,{ok:false,code:'INVALID_BODY_SIZE'})
  let data
  try{data=JSON.parse(event.isBase64Encoded===true?Buffer.from(event.body,'base64').toString('utf8'):event.body)}catch{return reply(400,{ok:false,code:'INVALID_JSON'})}
  if(!data||Array.isArray(data)||typeof data!=='object')return reply(400,{ok:false,code:'INVALID_BODY'})
  const result=await admin.main(data,context)
  const status=result.ok?200:result.code==='ACCOUNT_LOCKED'?423:result.code==='INVALID_CREDENTIALS'||result.code?.startsWith('ADMIN_TOKEN')?401:result.code==='INTERNAL_ERROR'||result.code==='ADMIN_STORAGE_ERROR'?503:400
  return reply(status,result)
}
