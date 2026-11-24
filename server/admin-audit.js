'use strict'
const r=require('./runtime')
exports.handle=async(e,instance,db)=>{
 if(e.action==='audit.meta')return {admins:await r.rows(db.from('admins').select('_id,username').order('username'))}
 if(e.action!=='audit.list')r.fail('UNKNOWN_AUDIT_OPERATION')
 const login=e.kind==='login';if(e.kind&&!['login','actions'].includes(e.kind))r.fail('INVALID_AUDIT_KIND')
 const page=e.page??0;if(!Number.isSafeInteger(page)||page<0||page>10000)r.fail('INVALID_PAGE')
 let query=db.from(login?'admin_login_logs':'admin_actions').select('*').order('createdAt',{ascending:false}).order('_id',{ascending:false}).range(page*50,page*50+50)
 for(const key of ['from','to'])if(e[key]){if(typeof e[key]!=='string'||! /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?Z$/.test(e[key])||!Number.isFinite(Date.parse(e[key])))r.fail('INVALID_AUDIT_DATE');query=key==='from'?query.gte('createdAt',e[key]):query.lte('createdAt',e[key])}
 if(e.from&&e.to&&Date.parse(e.from)>Date.parse(e.to))r.fail('INVALID_AUDIT_DATE')
 for(const [field,value] of login?[['username',e.username]]:[['action',e.operation],['target',e.target],['adminId',e.adminId]])if(value){if(typeof value!=='string'||value.length>120)r.fail('INVALID_AUDIT_FILTER');query=query.eq(field,value)}
 const rows=await r.rows(query);return {rows:rows.slice(0,50),hasMore:rows.length>50,page}
}
