'use strict'
const r=require('./runtime')
const money=require('./money')
async function cartReply(db,user){
  const cart=await r.rows(db.from('carts').select('*').eq('userId',user._id))
  if(!cart.length)return {cart,goodsAmount:0}
  const skus=await r.rows(db.from('skus').select('*').in('_id',cart.map(l=>l.skuId)))
  const products=await r.rows(db.from('products').select('*').in('_id',[...new Set(skus.map(s=>s.productId))]))
  let goodsAmount=0
  for(const line of cart){const sku=skus.find(s=>s._id===line.skuId),product=products.find(p=>p._id===sku?.productId);line.productId=sku?.productId;line.available=sku?r.int(sku.stock)-r.int(sku.reserved):0;if(line.selected&&product?.stage==='shelf'&&product.reviewStatus==='approved'&&product.onShelf)goodsAmount=money.add(goodsAmount,money.multiply(product.price,r.int(line.qty)))}
  return {cart,goodsAmount}
}
exports.main=r.handler(async(event,instance,db)=>{
  const user=await r.caller(db,r.identity(instance)),action=event.action||'addresses'
  if(action==='addresses')return {addresses:await r.rows(db.from('addresses').select('*').eq('userId',user._id))}
  if(action==='saveAddress'){
    const a=event.address||{}
    if(typeof a.name!=='string'||!a.name.trim()||a.name.trim().length>30||typeof a.phone!=='string'||!/^1\d{10}$/.test(a.phone)||typeof a.region!=='string'||!a.region.trim()||typeof a.detail!=='string'||a.detail.trim().length<5)r.fail('INVALID_ADDRESS','请完整填写收货地址和手机号')
    let addresses=await r.rows(db.from('addresses').select('*').eq('userId',user._id))
    let current=a._id?addresses.find(row=>row._id===a._id):null
    if(a._id&&!current)r.fail('ADDRESS_NOT_FOUND')
    if(!current){
      const p=r.plan(),id=r.uuid();r.insert(p,'addresses',{_id:id,userId:user._id,name:a.name.trim(),phone:a.phone,region:a.region.trim(),detail:a.detail.trim(),isDefault:addresses.length===0});await r.commit(db,p)
      // Preserve the created ID across optimistic retries of default switching.
      a._id=id;current=await r.one(db,'addresses',id);addresses=await r.rows(db.from('addresses').select('*').eq('userId',user._id))
    }
    const p=r.plan()
    if(a.isDefault)for(const other of addresses.filter(row=>row.isDefault&&row._id!==current._id)){
      r.lock(p,'addresses',other,['isDefault']);r.update(p,'addresses',other._id,{isDefault:false})
    }
    r.lock(p,'addresses',current,['name','phone','region','detail','isDefault'])
    r.update(p,'addresses',current._id,{name:a.name.trim(),phone:a.phone,region:a.region.trim(),detail:a.detail.trim(),isDefault:a.isDefault===true||current.isDefault})
    await r.commit(db,p);return {address:await r.one(db,'addresses',current._id)}
  }
  if(action==='deleteAddress'){
    const address=await r.one(db,'addresses',event.addressId);if(!address)return {deleted:true,idempotent:true};if(address.userId!==user._id)r.fail('ADDRESS_NOT_FOUND')
    const p=r.plan();r.lock(p,'addresses',address,['isDefault']);p.deletes.push({table:'addresses',id:address._id});await r.commit(db,p)
    if(address.isDefault){const others=await r.rows(db.from('addresses').select('*').eq('userId',user._id));if(others.length&&!others.some(a=>a.isDefault)){const next=r.plan();r.lock(next,'addresses',others[0],['isDefault']);r.update(next,'addresses',others[0]._id,{isDefault:true});await r.commit(db,next)}}
    return {deleted:true}
  }
  if(action==='cart')return cartReply(db,user)
  if(['setCart','removeCart'].includes(action)){
    const sku=await r.one(db,'skus',event.skuId);if(!sku)r.fail('SKU_NOT_FOUND')
    const existing=(await r.rows(db.from('carts').select('*').eq('userId',user._id).eq('skuId',event.skuId).limit(1)))[0]
    const p=r.plan()
    if(action==='removeCart'){if(existing){r.lock(p,'carts',existing,['qty','selected']);p.deletes.push({table:'carts',id:existing._id})}}
    else{
      const product=await r.one(db,'products',sku.productId)
      if(!product||product.stage!=='shelf'||product.reviewStatus!=='approved'||!product.onShelf)r.fail('PRODUCT_UNAVAILABLE')
      const qty=event.add===true?r.int(event.qty)+(existing?r.int(existing.qty):0):r.int(event.qty)
      if(qty<1||qty>99||qty>r.int(sku.stock)-r.int(sku.reserved))r.fail('OUT_OF_STOCK','数量超出可用库存')
      if(existing){r.lock(p,'carts',existing,['qty','selected']);r.update(p,'carts',existing._id,{qty,selected:event.selected!==false,updatedAt:new Date().toISOString()})}
      else r.insert(p,'carts',{_id:r.uuid(),userId:user._id,skuId:event.skuId,qty,selected:event.selected!==false})
    }
    if(p.inserts.length||p.updates.length||p.deletes.length)await r.commit(db,p)
    return cartReply(db,user)
  }
  r.fail('UNKNOWN_ACTION')
})
