'use strict'
const r=require('./runtime')
exports.handle=async(e,instance,db,admin)=>{
 if(e.action==='faq.list')return {faqs:await r.rows(db.from('faqs').select('*').order('sort').limit(500))}
 const op=e.action.slice(4),id=e.id||r.uuid(),d=e.data||{};let value
 if(typeof id!=='string'||! /^[a-zA-Z0-9_-]{1,80}$/.test(id))r.fail('INVALID_ID')
 if(op==='save'){
  if(typeof d.question!=='string'||!d.question.trim()||d.question.length>200||typeof d.answer!=='string'||!d.answer.trim()||d.answer.length>3000||!Number.isSafeInteger(d.sort)||d.sort<0||d.sort>100000)r.fail('INVALID_FAQ','请填写问题、答案与有效排序')
  value={question:d.question.trim(),answer:d.answer.trim(),sort:d.sort,visible:d.visible===true}
 }else if(op==='delete')value={};else r.fail('UNKNOWN_FAQ_OPERATION')
 const {data,error}=await db.rpc('mall_admin_faq',{p_admin:admin._id,p_op:op,p_id:id,p_data:value});if(error)r.fail('FAQ_REJECTED','FAQ保存失败');return data
}
