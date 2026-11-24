'use strict'
const r=require('./runtime'),c=require('./commerce'),money=require('./money')
async function owned(db,user,id){const order=await r.one(db,'orders',id);if(!order||order.userId!==user._id)r.fail('ORDER_NOT_FOUND','订单不存在');return order}
async function cancel(db,user,order,expired=false){
  if(order.status==='cancelled')return order
  if(order.status!=='pending_pay')r.fail('ORDER_NOT_CANCELLABLE','仅待付款订单可以取消')
  const items=await r.rows(db.from('order_items').select('*').eq('orderId',order._id))
  const p=r.plan();r.lock(p,'orders',order,['status','version'])
  for(const table of ['skus','gift_stock']){
    const field=table==='skus'?'skuId':'giftStockId',quantities=new Map()
    for(const item of items)if(item[field])quantities.set(item[field],(quantities.get(item[field])||0)+r.int(item.qty))
    if(quantities.size)c.reserve(p,table,await c.inventory(db,table,[...quantities.keys()]),quantities,'release')
  }
  r.update(p,'orders',order._id,{status:'cancelled',cancelledAt:new Date().toISOString(),version:r.int(order.version)+1,remark:order.remark})
  await r.commit(db,p);return {...order,status:'cancelled',expired}
}
exports.main=r.handler(async(event,instance,db)=>{
  const user=await r.caller(db,r.identity(instance)),action=event.action||'list'
  if(action==='quote')return {quote:c.publicQuote(await c.quote(db,user,event))}
  if(action==='create'){
    c.requestKey(event.requestKey)
    const existing=(await r.rows(db.from('orders').select('*').eq('userId',user._id).eq('requestKey',event.requestKey).limit(1)))[0]
    if(existing)return {order:existing,idempotent:true}
    const q=await c.quote(db,user,event);if(!q.address)r.fail('ADDRESS_REQUIRED','请选择收货地址')
    const p=r.plan();r.lock(p,'users',user,['version','level'])
    c.reserve(p,'skus',q.skus,q.quantities,'reserve')
    const id='GM'+r.uuid().replaceAll('-','').toUpperCase()
    const order={_id:id,userId:user._id,requestKey:event.requestKey,items:q.items,...c.publicQuote(q),address:q.address,remark:typeof event.remark==='string'?event.remark.trim().slice(0,200):'',status:'pending_pay',useBalance:q.useBalance,isGift:false,isCustom:false,customDetail:null,customReview:null,payDeadline:new Date(Date.now()+r.int(q.config.paymentTimeoutMinutes)*60000).toISOString()}
    r.insert(p,'orders',order)
    for(const item of q.items)r.insert(p,'order_items',{_id:r.uuid(),orderId:id,...item})
    if(event.source==='cart'){
      const cart=await r.rows(db.from('carts').select('*').eq('userId',user._id))
      for(const [skuId,qty] of q.quantities){const line=cart.find(item=>item.skuId===skuId);if(!line||r.int(line.qty)<qty)r.fail('CART_CHANGED','购物车已变化，请重新确认');r.lock(p,'carts',line,['qty','selected']);if(r.int(line.qty)===qty)p.deletes.push({table:'carts',id:line._id});else r.update(p,'carts',line._id,{qty:r.int(line.qty)-qty})}
    }
    await r.commit(db,p);return {order:await r.one(db,'orders',id)}
  }
  if(action==='list')return {orders:await r.rows(db.from('orders').select('*').eq('userId',user._id).order('createdAt',{ascending:false}).limit(100))}
  if(action==='refundCancel'){
    const refund=await r.one(db,'refunds',typeof event.refundId==='string'?event.refundId:'')
    if(!refund||refund.userId!==user._id)r.fail('REFUND_NOT_FOUND','退款记录不存在')
    if(refund.status!=='pending')r.fail('REFUND_NOT_PENDING','这笔退款已处理，无法撤销')
    const p=r.plan();r.lock(p,'refunds',refund,['status']);r.update(p,'refunds',refund._id,{status:'cancelled',decidedAt:new Date().toISOString()});await r.commit(db,p)
    return {ok:true,refundId:refund._id}
  }
  const order=await owned(db,user,event.orderId)
  if(action==='detail')return {order}
  if(action==='cancel')return {order:await cancel(db,user,order)}
  if(action==='payMock'){
    if(order.paidAt)return {order,idempotent:true}
    if(order.status!=='pending_pay')r.fail('ORDER_NOT_PAYABLE','订单状态已变化')
    if(Date.now()>=Date.parse(order.payDeadline)){await cancel(db,user,order,true);r.fail('ORDER_EXPIRED','订单已超时取消')}
    const config=await c.settings(db)
    if(config.realPaymentEnabled||config.smsEnabled)r.fail('UNSUPPORTED_LIVE_MODE')
    const items=await r.rows(db.from('order_items').select('*').eq('orderId',order._id)),p=r.plan()
    r.lock(p,'orders',order,['status','version']);r.lock(p,'users',user,['version','balance','totalPurchase'])
    for(const table of ['skus','gift_stock']){
      const field=table==='skus'?'skuId':'giftStockId',quantities=new Map()
      for(const item of items)if(item[field])quantities.set(item[field],(quantities.get(item[field])||0)+r.int(item.qty))
      if(quantities.size)c.reserve(p,table,await c.inventory(db,table,[...quantities.keys()]),quantities,'pay')
    }
    const payAmount=money.amount(order.payAmount)
    const balancePaid=order.useBalance?Math.min(user.balance,payAmount):0
    const totalPurchase=money.add(user.totalPurchase,payAmount)
    if(balancePaid>0)c.ledger(p,user,-balancePaid,'pay','pay:'+order._id,order._id,user.balance-balancePaid,'订单支付（余额部分）')
    r.update(p,'users',user._id,{balance:user.balance-balancePaid,totalPurchase,version:user.version+1})
    r.update(p,'orders',order._id,{balancePaid,wxPaid:payAmount-balancePaid,status:'pending_ship',paidAt:new Date().toISOString(),version:r.int(order.version)+1})
    await r.commit(db,p);return {order:await r.one(db,'orders',order._id),simulated:true}
  }
  if(action==='receive'){
    if(order.status==='done')return {order,idempotent:true}
    if(order.status!=='pending_recv')r.fail('ORDER_NOT_RECEIVABLE','订单尚未发货')
    const p=r.plan();r.lock(p,'orders',order,['status','version']);r.update(p,'orders',order._id,{status:'done',version:r.int(order.version)+1});await r.commit(db,p)
    return {order:await r.one(db,'orders',order._id)}
  }
  if(action==='refundData')return {items:await r.rows(db.from('order_items').select('*').eq('orderId',order._id)),refunds:await r.rows(db.from('refunds').select('*').eq('orderId',order._id).order('createdAt',{ascending:false}).limit(50))}
  if(action==='requestRefund'){
    if(!['pending_ship','pending_recv','done'].includes(order.status))r.fail('REFUND_NOT_ALLOWED','待发货、待收货或已完成订单才可申请退款')
    const codes=['seller_wrong','seller_quality','seller_size','buyer_change','buyer_size','buyer_other']
    if(!codes.includes(event.reasonCode))r.fail('REFUND_REASON_REQUIRED','请选择退款原因')
    const reasonText=typeof event.reasonText==='string'?event.reasonText.trim().slice(0,300):''
    if(!Array.isArray(event.lines)||!event.lines.length||event.lines.length>50)r.fail('REFUND_LINES_REQUIRED','请选择要退款的商品')
    const items=await r.rows(db.from('order_items').select('*').eq('orderId',order._id))
    const pendings=await r.rows(db.from('refunds').select('*').eq('orderId',order._id).eq('status','pending'))
    const pendingQty=new Map()
    for(const rf of pendings)for(const l of rf.lines)pendingQty.set(l.itemId,(pendingQty.get(l.itemId)||0)+r.int(l.qty))
    const seen=new Set(),lines=[]
    for(const want of event.lines){
      const item=items.find(i=>i._id===want?.itemId)
      if(!item||seen.has(item._id))r.fail('REFUND_LINE_INVALID','退款商品不正确')
      seen.add(item._id)
      if(!Number.isInteger(want.qty))r.fail('REFUND_QTY_INVALID','退款数量不正确')
      const available=r.int(item.qty)-r.int(item.refundedQty||0)-(pendingQty.get(item._id)||0)
      if(want.qty<1||want.qty>available)r.fail('REFUND_QTY_INVALID','退款数量超过可退数量')
      lines.push({itemId:item._id,skuId:item.skuId||null,giftStockId:item.giftStockId||null,name:item.name,color:item.color,size:item.size,pattern:item.pattern,price:r.int(item.price),qty:want.qty})
    }
    // 会员折扣按行小计比例分摊（最大余数法），保证逐件退总额与实付分毫不差
    const subtotal=items.map(i=>r.int(i.price)*r.int(i.qty)),goodsTotal=subtotal.reduce((a,b)=>a+b,0),discount=r.int(order.discountAmount)
    const shares=subtotal.map((s,idx)=>{if(!goodsTotal||!discount)return{idx,base:0,rem:0};const exact=BigInt(s)*BigInt(discount),gt=BigInt(goodsTotal);return{idx,base:Number(exact/gt),rem:Number(exact%gt)}})
    let assigned=shares.reduce((a,s)=>a+s.base,0)
    ;[...shares].sort((a,b)=>b.rem-a.rem).forEach(s=>{if(assigned<discount){s.base+=1;assigned+=1}})
    const lineRefundable=items.map((it,idx)=>subtotal[idx]-(shares.find(s=>s.idx===idx)?.base||0))
    let goods=0
    const valued=lines.map(l=>{
      const idx=items.findIndex(i=>i._id===l.itemId),line=items[idx],total=lineRefundable[idx],lineQty=r.int(line.qty),doneQty=r.int(line.refundedQty||0)
      const upto=q=>Math.round(total*q/lineQty),amount=upto(doneQty+l.qty)-upto(doneQty)
      goods+=amount
      return {...l,amount}
    })
    const willComplete=items.every(i=>r.int(i.refundedQty||0)+(pendingQty.get(i._id)||0)+(lines.find(l=>l.itemId===i._id)?.qty||0)>=r.int(i.qty))
    const freightRefund=order.status==='pending_ship'&&willComplete?r.int(order.freightAmount):0
    let freightComp=0
    if(event.reasonCode.startsWith('seller')&&['pending_recv','done'].includes(order.status)&&r.int(order.freightAmount)>0){
      const prior=await r.rows(db.from('refunds').select('"freightComp"').eq('orderId',order._id).neq('status','rejected'))
      if(!prior.some(x=>x.status!=='cancelled'&&r.int(x.freightComp)>0))freightComp=r.int(order.freightAmount)
    }
    const stream=goods+freightRefund,total=stream+freightComp
    if(total<=0)r.fail('REFUND_NOT_ALLOWED','本次退款金额为零')
    const before=r.int(order.refundedAmount||0)
    // 退款分路：余额支付部分优先退回余额（不超该单余额支付额减去已退余额部分），其余走原路；
    // 审核型退款的最终分路以管理员裁定为准（mall_admin_refund 按分路重算）。
    const decided=await r.rows(db.from('refunds').select('balanceAmount,status').eq('orderId',order._id))
    const refundedBalance=decided.filter(x=>x.status==='done'||x.status==='pending').reduce((sum,x)=>sum+r.int(x.balanceAmount||0),0)
    const balanceAmount=Math.min(total,Math.max(0,r.int(order.balancePaid||0)-refundedBalance)),originalAmount=total-balanceAmount
    const instant=order.status==='pending_ship'&&!order.isCustom&&!order.isGift
    const refundId=r.uuid(),p=r.plan()
    r.lock(p,'orders',order,['status','version'])
    if(instant){
      for(const table of ['skus','gift_stock']){
        const field=table==='skus'?'skuId':'giftStockId',quantities=new Map()
        for(const l of valued)if(l[field])quantities.set(l[field],(quantities.get(l[field])||0)+l.qty)
        if(quantities.size){const invRows=await c.inventory(db,table,[...quantities.keys()]);for(const [sid,qty] of quantities){const row=invRows.find(s=>s._id===sid);if(!row)r.fail('STOCK_NOT_FOUND');r.lock(p,table,row,['stock','reserved']);r.update(p,table,sid,{stock:r.int(row.stock)+qty})}}
      }
      for(const l of valued){const item=items.find(i=>i._id===l.itemId);r.lock(p,'order_items',item,['refundedQty']);r.update(p,'order_items',l.itemId,{refundedQty:r.int(item.refundedQty||0)+l.qty})}
      const allDone=items.every(i=>r.int(i.refundedQty||0)+(valued.find(l=>l.itemId===i._id)?.qty||0)>=r.int(i.qty))
      if(balanceAmount>0){
        r.lock(p,'users',user,['version','balance'])
        c.ledger(p,user,balanceAmount,'refund_in','refund:'+refundId,order._id,user.balance+balanceAmount,'即时退款（余额部分）')
        r.update(p,'users',user._id,{balance:user.balance+balanceAmount,version:r.int(user.version)+1})
      }
      r.update(p,'orders',order._id,{refundedAmount:before+stream,status:allDone?'refunded':order.status,refundReason:reasonText||order.refundReason,version:r.int(order.version)+1})
      r.insert(p,'refunds',{_id:refundId,orderId:order._id,userId:user._id,lines:valued,reasonCode:event.reasonCode,reasonText,goodsAmount:goods,freightAmount:freightRefund,freightComp:0,totalAmount:total,balanceAmount,originalAmount,mode:'instant',status:'done',decidedAt:new Date().toISOString()})
      const autoExists=(await r.rows(db.from('auto_refunds').select('_id').eq('orderId',order._id).limit(1)))[0]
      if(!autoExists)r.insert(p,'auto_refunds',{_id:r.uuid(),orderId:order._id,balanceAmount,originalAmount,reason:reasonText||event.reasonCode})
    }else{
      r.insert(p,'refunds',{_id:refundId,orderId:order._id,userId:user._id,lines:valued,reasonCode:event.reasonCode,reasonText,goodsAmount:goods,freightAmount:freightRefund,freightComp,totalAmount:total,balanceAmount,originalAmount,mode:'review',status:'pending'})
    }
    await r.commit(db,p)
    return {order:await r.one(db,'orders',order._id),refundId,refundMode:instant?'instant':'review'}
  }
  r.fail('UNKNOWN_ACTION')
})
exports.cancel=cancel
