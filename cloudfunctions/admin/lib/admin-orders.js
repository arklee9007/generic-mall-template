'use strict'
const r=require('./runtime')
const states=['pending_pay','pending_ship','pending_recv','done','cancelled','refunding','refunded']
exports.handle=async(e,instance,db,admin)=>{
 if(e.action==='order.list'){
  let query=db.from('orders').select('*').order('createdAt',{ascending:false}).limit(100)
  if(e.status){if(!states.includes(e.status))r.fail('INVALID_STATUS');query=query.eq('status',e.status)}
  return {orders:await r.rows(query),limit:100}
 }
 if(e.action==='order.detail'){
  const order=await r.one(db,'orders',e.id);if(!order)r.fail('ORDER_NOT_FOUND')
  const buyer=await r.one(db,'users',order.userId);if(buyer)order.memberNo=buyer.memberNo
  const refunds=await r.rows(db.from('admin_refunds').select('*').eq('orderId',e.id))
  const partRefunds=await r.rows(db.from('refunds').select('*').eq('orderId',e.id).order('createdAt',{ascending:false}).limit(50))
  return {order,refund:refunds[0]||null,refunds:partRefunds}
 }
 const op=e.action.slice(6);if(!['ship','refund.approve','refund.reject'].includes(op))r.fail('UNKNOWN_ORDER_OPERATION')
 if(typeof e.id!=='string'||!e.id||!Number.isSafeInteger(e.version)||e.version<0)r.fail('INVALID_ORDER_VERSION')
 const d=e.data||{},data={}
 for(const key of ['company','tracking','reason'])if(d[key]!==undefined){if(typeof d[key]!=='string')r.fail('INVALID_ORDER_INPUT');data[key]=d[key].trim().slice(0,key==='reason'?501:100)}
 if(op==='ship'&&(!data.company||data.company.length>60||!data.tracking||data.tracking.length>80))r.fail('SHIPPING_REQUIRED','请填写快递公司与单号')
 if(op.endsWith('reject')&&(!data.reason||data.reason.length<2||data.reason.length>500))r.fail('REASON_REQUIRED','请填写2–500字理由')
 if(op==='refund.approve'){if(d.mode!==undefined&&!['balance','original'].includes(d.mode))r.fail('INVALID_REFUND_MODE','退款分路不正确');data.mode=d.mode||'original'}
 const {data:result,error}=await db.rpc('mall_admin_order',{p_admin:admin._id,p_op:op,p_id:e.id,p_version:e.version,p_data:data})
 if(error){const code=['ORDER_NOT_FOUND','ORDER_CHANGED_REFRESH','ORDER_NOT_SHIPPABLE','CUSTOM_REVIEW_NOT_ALLOWED','REFUND_REJECTION_NOT_ALLOWED','REFUND_NOT_ALLOWED','BALANCE_OVERFLOW'].find(c=>error.message?.includes(c));r.fail(code||'ADMIN_STORAGE_ERROR',code==='ORDER_NOT_SHIPPABLE'?'订单未付款、状态不符或定制尚未通过，请刷新核对':code==='ORDER_CHANGED_REFRESH'?'订单已更新，请刷新后重试':'该订单当前不能执行此操作')}
 return result
}
exports.handleRefund=async(e,instance,db,admin)=>{
 if(e.action==='refund.list'){
  let query=db.from('refunds').select('*').order('createdAt',{ascending:false}).limit(100)
  if(e.status){if(!['pending','done','rejected'].includes(e.status))r.fail('INVALID_STATUS');query=query.eq('status',e.status)}
  return {refunds:await r.rows(query),limit:100}
 }
 const op=e.action.slice('refund.'.length)
 if(!['approve','reject'].includes(op))r.fail('UNKNOWN_REFUND_OPERATION')
 if(typeof e.id!=='string'||!e.id)r.fail('INVALID_REFUND')
 const d=e.data||{},data={}
 if(op==='reject'){if(typeof d.reason!=='string'||d.reason.trim().length<2||d.reason.trim().length>500)r.fail('REASON_REQUIRED','请填写2–500字理由');data.reason=d.reason.trim()}
 if(op==='approve'){if(d.route!==undefined&&!['source','balance'].includes(d.route))r.fail('INVALID_REFUND_ROUTE','退款分路不正确');data.route=d.route||'source'}
 const {data:result,error}=await db.rpc('mall_admin_refund',{p_admin:admin._id,p_id:e.id,p_op:op,p_data:data})
 if(error){const code=['REFUND_NOT_FOUND','REFUND_DECIDED','REASON_REQUIRED','BALANCE_OVERFLOW','ORDER_NOT_FOUND'].find(c=>error.message?.includes(c));r.fail(code||'ADMIN_STORAGE_ERROR',code==='REFUND_DECIDED'?'该退款已处理，请刷新':code==='REASON_REQUIRED'?'请填写2–500字理由':'该退款当前不能执行此操作')}
 return result
}
