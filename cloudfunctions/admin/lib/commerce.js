'use strict'
const r=require('./runtime'),money=require('./money'),mt=require('./member-tiers')
function requestKey(value){if(typeof value!=='string'||value.length<8||value.length>100)r.fail('INVALID_REQUEST_KEY');return value}
async function settings(db){return (await r.one(db,'settings','global'))||r.fail('CONFIG_NOT_READY')}
async function inventory(db,table,ids){return r.rows(db.from(table).select('*').in('_id',[...new Set(ids)]))}
function checkRegion(template,region){if(template.rules.some(rule=>rule.type==='no_delivery'&&rule.regions.some(name=>region.includes(name))))r.fail('NO_DELIVERY','该地区暂不配送')}
function freight(template,region){
  checkRegion(template,region)
  const normal=template.rules.find(rule=>rule.type==='normal'&&(rule.regions.includes('*')||rule.regions.some(name=>region.includes(name))))
  if(!normal)r.fail('FREIGHT_NOT_CONFIGURED','该地区运费尚未配置')
  const extra=template.rules.filter(rule=>rule.type==='extra'&&rule.regions.some(name=>region.includes(name)))
  return money.add(normal.price,...extra.map(rule=>rule.price))
}
async function shipping(db,products,address){
  const templates=await r.rows(db.from('freight_templates').select('*'))
  const defaultTemplate=templates.find(t=>t.isDefault)
  if(!defaultTemplate)r.fail('FREIGHT_NOT_CONFIGURED')
  const region=address?.region||'普通地区'
  const ids=[...new Set(products.filter(p=>p.freightMode!=='free').map(p=>p.freightTemplateId||defaultTemplate._id))]
  if(ids.length>1)r.fail('MULTI_FREIGHT_UNCONFIGURED','不同运费模板的商品请分别结算')
  if(!ids.length){checkRegion(defaultTemplate,region);return 0}
  const template=templates.find(t=>t._id===ids[0]);if(!template)r.fail('FREIGHT_NOT_CONFIGURED')
  return freight(template,region)
}
async function addressFor(db,user,id,required=true){
  if(!id){if(required)r.fail('ADDRESS_REQUIRED','请选择收货地址');return null}
  const address=await r.one(db,'addresses',id)
  if(!address||address.userId!==user._id)r.fail('ADDRESS_NOT_FOUND','收货地址不存在')
  return {name:address.name,phone:address.phone,region:address.region,detail:address.detail}
}
async function quote(db,user,event){
  if(!Array.isArray(event.lines)||event.lines.length<1||event.lines.length>50)r.fail('INVALID_LINES','请选择商品')
  const [products,skus,config,tiers,address]=await Promise.all([
    inventory(db,'products',event.lines.map(l=>l.productId)),inventory(db,'skus',event.lines.map(l=>l.skuId)),
    settings(db),mt.loadTiers(db),addressFor(db,user,event.addressId,false),
  ])
  const mc=mt.memberConfig(config.shopConfig)
  const quantities=new Map()
  const items=event.lines.map(line=>{
    const p=products.find(p=>p._id===line.productId),s=skus.find(s=>s._id===line.skuId&&s.productId===line.productId)
    if(!p||!s||p.stage!=='shelf'||p.reviewStatus!=='approved'||!p.onShelf)r.fail('PRODUCT_UNAVAILABLE','商品不存在或已下架')
    if(!Number.isInteger(line.qty)||line.qty<1||line.qty>99)r.fail('INVALID_QUANTITY','商品数量不正确')
    quantities.set(s._id,(quantities.get(s._id)||0)+line.qty)
    if(quantities.get(s._id)>r.int(s.stock)-r.int(s.reserved))r.fail('OUT_OF_STOCK','该规格库存不足')
    return {productId:p._id,skuId:s._id,name:p.name,image:p.images[0]||'',color:s.color,size:s.size,pattern:s.pattern,price:money.amount(p.price),qty:line.qty}
  })
  const goodsAmount=money.add(...items.map(item=>money.multiply(item.price,item.qty)))
  const bps=mt.discountBpsFor(tiers,user.level,mc.enabled)
  const useBalance=event.useBalance!==false
  const amounts=money.totalsBps(goodsAmount,await shipping(db,products,address),bps,{balance:user.balance,useBalance})
  return {...amounts,items,address,customDetail:null,useBalance,skus,quantities,config}
}
function reserve(p,table,rows,quantities,mode){
  for(const [id,qty] of quantities){
    const row=rows.find(s=>s._id===id);if(!row)r.fail('STOCK_NOT_FOUND')
    const stock=r.int(row.stock),reserved=r.int(row.reserved)
    r.lock(p,table,row,['stock','reserved'])
    if(mode==='reserve'){if(stock-reserved<qty)r.fail('OUT_OF_STOCK','库存不足');r.update(p,table,id,{reserved:reserved+qty})}
    else{if(reserved<qty)r.fail('RESERVATION_INCONSISTENT');r.update(p,table,id,{stock:mode==='pay'?stock-qty:stock,reserved:reserved-qty})}
  }
}
function publicQuote(q){return {items:q.items,goodsAmount:q.goodsAmount,discountAmount:q.discountAmount,freightAmount:q.freightAmount,payAmount:q.payAmount,balancePaid:q.balancePaid,wxPaid:q.wxPaid}}
function ledger(p,user,amount,type,key,orderId,balanceAfter,remark){return r.insert(p,'balance_logs',{_id:r.uuid(),userId:user._id,type,amount,dedupeKey:key,orderId:orderId||null,balanceAfter,remark})}
module.exports={requestKey,settings,inventory,freight,shipping,addressFor,quote,reserve,publicQuote,ledger}
