'use strict'
// 分片上传：网关对单次请求体大小有上限，文件改为分片发送、服务端拼装后存云存储。
// 每片 base64 不超过 43692 字符（请求体约 44KB）。本模板只支持 purpose=image（图片上传）。
const r=require('./runtime'),catalog=require('./admin-catalog')
const MAX_BYTES=2097152,SLICE_CHARS=43692
function validId(v){return typeof v==='string'&&/^[a-zA-Z0-9-]{8,80}$/.test(v)}
async function drop(db,admin,uploadId){const {error}=await db.from('upload_chunks').delete().eq('uploadId',uploadId).eq('adminId',admin._id);if(error)r.fail('UPLOAD_STORAGE_ERROR','上传缓存清理失败')}
async function handle(e,instance,db,admin){
 if(e.action==='upload.abort'){if(validId(e.uploadId))await drop(db,admin,e.uploadId);return {aborted:true}}
 if(e.action==='upload.chunk'){
  if(!validId(e.uploadId))r.fail('INVALID_UPLOAD','上传标识不正确')
  const index=Number(e.index);if(!Number.isSafeInteger(index)||index<0||index>4096)r.fail('INVALID_UPLOAD','分片序号不正确')
  if(typeof e.data!=='string'||!e.data.length||e.data.length>SLICE_CHARS)r.fail('INVALID_UPLOAD','分片大小不正确')
  const first=await db.from('upload_chunks').insert({uploadId:e.uploadId,adminId:admin._id,idx:index,data:e.data})
  if(first.error){const again=await db.from('upload_chunks').update({data:e.data}).eq('uploadId',e.uploadId).eq('idx',index).eq('adminId',admin._id);if(again.error)r.fail('UPLOAD_STORAGE_ERROR','分片保存失败')}
  return {received:index}
 }
 if(e.action==='upload.finish'){
  if(!validId(e.uploadId))r.fail('INVALID_UPLOAD','上传标识不正确')
  const total=Number(e.chunks),size=Number(e.size)
  if(!Number.isSafeInteger(total)||total<1||total>4096||!Number.isSafeInteger(size)||size<1||size>MAX_BYTES)r.fail('INVALID_UPLOAD','上传信息不完整或文件超过2MB')
  const rows=await r.rows(db.from('upload_chunks').select('idx,data').eq('uploadId',e.uploadId).eq('adminId',admin._id).order('idx',{ascending:true}).limit(5000))
  if(rows.length!==total||rows.some((row,i)=>row.idx!==i))r.fail('UPLOAD_INCOMPLETE','分片不完整，请重新上传')
  const bytes=Buffer.from(rows.map(row=>row.data).join(''),'base64')
  if(bytes.length!==size)r.fail('UPLOAD_INCOMPLETE','文件大小对不上，请重新上传')
  if(e.purpose!=='image')r.fail('INVALID_UPLOAD','上传用途不正确')
  const result={url:await catalog.storeImage(instance,bytes)}
  await drop(db,admin,e.uploadId)
  return result
 }
 r.fail('UNKNOWN_ACTION')
}
module.exports={handle}
