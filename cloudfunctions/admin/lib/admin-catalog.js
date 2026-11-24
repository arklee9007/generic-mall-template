'use strict'
const r=require('./runtime'),{createHash}=require('node:crypto')
function text(v,max=120){if(typeof v!=='string'||!v.trim()||v.trim().length>max)r.fail('INVALID_CATALOG_FIELD','请检查必填字段与长度');return v.trim()}
function axis(v,max=20){if(!Array.isArray(v)||v.length>max)r.fail('INVALID_SPEC','规格列表不正确');const list=v.map(x=>text(x,500));if(new Set(list).size!==list.length)r.fail('DUPLICATE_SPEC','规格不可重复');return list}
function array(v,max=20){if(!Array.isArray(v)||!v.length||v.length>max)r.fail('INVALID_SPEC','规格或图片列表不正确');const list=v.map(x=>text(x,500));if(new Set(list).size!==list.length)r.fail('DUPLICATE_SPEC','规格不可重复');return list}
function image(value){const url=text(value,1200);if(!/^https:\/\//.test(url)&&!url.startsWith('/static/'))r.fail('INVALID_IMAGE_URL','图片须为HTTPS云存储地址');return url}
function integer(v,min=0,max=100000000){const n=Number(v);if(!Number.isSafeInteger(n)||n<min||n>max)r.fail('INVALID_NUMBER','数值超出范围');return n}
function specLabels(v){
  if(v===undefined||v===null)return []
  if(!Array.isArray(v)||v.length>3)r.fail('INVALID_SPEC_LABELS','轴名最多 3 个')
  return v.map(x=>{if(typeof x!=='string'||x.length>10)r.fail('INVALID_SPEC_LABELS','轴名须为 10 字以内文字');return x.trim()})
}
function specChart(v){
  if(v===undefined||v===null)return []
  if(Array.isArray(v)&&!v.length)return []
  if(typeof v!=='object'||Array.isArray(v))r.fail('INVALID_SPEC_CHART','规格说明表格式不正确')
  const columns=v.columns,rows=v.rows
  if(!Array.isArray(columns)||!columns.length||columns.length>8||!columns.every(x=>typeof x==='string'&&x.trim()&&x.trim().length<=20))r.fail('INVALID_SPEC_CHART','规格说明表列名不正确')
  if(!Array.isArray(rows)||rows.length>50||!rows.every(row=>Array.isArray(row)&&row.length===columns.length&&row.every(cell=>typeof cell==='string'&&cell.length<=40)))r.fail('INVALID_SPEC_CHART','规格说明表行数据不正确')
  return {columns:columns.map(x=>x.trim()),rows:rows.map(row=>row.map(cell=>cell.trim()))}
}
async function prepareProduct(db,id,data){
 const axes=[axis(data.colors||[]),axis(data.sizes||[]),axis(data.patterns||[])]
 const lists=axes.map(list=>list.length?list:[''])
 if(lists[0].length*lists[1].length*lists[2].length>400)r.fail('TOO_MANY_SKUS','单款最多400个规格组合')
 const keywords=Array.isArray(data.keywords)?data.keywords.map(x=>text(x,40)):[]
 if(keywords.length>20)r.fail('INVALID_CATALOG_FIELD','关键词最多 20 个')
 const value={name:text(data.name),categoryId:text(data.categoryId),images:array(data.images).map(image),detailImages:(data.detailImages||[]).map(image),desc:typeof data.desc==='string'?data.desc.slice(0,5000):'',subtitle:typeof data.subtitle==='string'?data.subtitle.trim().slice(0,120):'',keywords,colors:axes[0],sizes:axes[1],patterns:axes[2],specLabels:specLabels(data.specLabels),sizeChart:specChart(data.specChart ?? data.sizeChart),price:integer(data.price,0,100000000),freightMode:data.freightMode,freightTemplateId:data.freightMode==='template'?text(data.freightTemplateId):null,skus:[]}
 if(!['template','free'].includes(value.freightMode))r.fail('INVALID_FREIGHT_MODE')
 const existing=await r.rows(db.from('skus').select('_id,color,size,pattern').eq('productId',id))
 for(const color of lists[0])for(const size of lists[1])for(const pattern of lists[2]){const previous=existing.find(s=>s.color===color&&s.size===size&&s.pattern===pattern);const skuId=previous?._id||id+'-'+createHash('sha256').update(JSON.stringify([color,size,pattern])).digest('hex').slice(0,16);const input=(data.skus||[]).find(s=>s.color===color&&s.size===size&&s.pattern===pattern);value.skus.push({_id:skuId,color,size,pattern,stock:integer(input?.stock??0)})}
 return value
}
async function storeImage(instance,bytes){
 const sniff=bytes.length>=8&&bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))?['image/png','.png']:bytes.length>=3&&bytes[0]===255&&bytes[1]===216&&bytes[2]===255?['image/jpeg','.jpg']:bytes.length>=12&&bytes.toString('ascii',0,4)==='RIFF'&&bytes.toString('ascii',8,12)==='WEBP'?['image/webp','.webp']:null
 if(!sniff||bytes.length>2097152)r.fail('INVALID_IMAGE','图片内容无法识别，请换一张PNG/JPEG/WebP图片')
 const key='products/'+r.uuid()+sniff[1]
 const env=process.env.TCB_ENV||process.env.SCF_NAMESPACE,base='https://'+env+'.api.tcloudbasegateway.com/v1/storages/object/admin-media/'
 const credential=await instance.auth().getClientCredential()
 const response=await fetch(base+key,{method:'POST',headers:{Authorization:'Bearer '+credential.access_token,'Content-Type':sniff[0]},body:bytes})
 if(!response.ok)r.fail('MEDIA_UPLOAD_FAILED','云存储上传失败（'+response.status+'）')
 return base+key
}
async function handle(e,instance,db,admin){
 if(e.action==='catalog.list'){
  const settings=await r.one(db,'settings','global')
  const _products=await r.rows(db.from('products').select('*').order('createdAt',{ascending:false}).limit(500))
  return {products:_products.map(_p=>({..._p,specChart:Array.isArray(_p.sizeChart)?null:_p.sizeChart})),skus:await r.rows(db.from('skus').select('*').limit(10000)),categories:await r.rows(db.from('categories').select('*').order('sort').limit(500)),freight:await r.rows(db.from('freight_templates').select('*').limit(100)),shopConfig:settings?.shopConfig||{}}
 }
 if(e.action==='catalog.upload'){
  if(typeof e.base64!=='string'||e.base64.length>2800000)r.fail('INVALID_IMAGE','图片只支持2MB内PNG/JPEG/WebP')
  return {url:await storeImage(instance,Buffer.from(e.base64,'base64'))}
 }
 const op=e.action.slice('catalog.'.length),id=e.id||r.uuid(),data=e.data||{}
 if(typeof id!=='string'||! /^[a-zA-Z0-9_-]{1,80}$/.test(id))r.fail('INVALID_ID')
 let value
 if(op==='save')value=await prepareProduct(db,id,data)
 else if(op==='category.save')value={name:text(data.name),parentId:typeof data.parentId==='string'?data.parentId:'',sort:integer(data.sort||0,0,100000),visible:data.visible!==false}
 else if(op==='stock')value={skuId:text(data.skuId),delta:integer(data.delta,-100000,100000)}
 else if(op==='shelf'){if(typeof data.onShelf!=='boolean')r.fail('INVALID_SHELF_STATE');value={onShelf:data.onShelf}}
 else if(op==='reject')value={reason:text(data.reason,300)}
 else if(['complete','approve','category.delete','clearDemo'].includes(op))value={}
 else r.fail('UNKNOWN_ACTION')
 const {data:result,error}=await db.rpc('mall_admin_catalog',{p_admin:admin._id,p_op:op,p_id:id,p_data:value})
 if(error)r.fail('CATALOG_REJECTED',({'23503':'分类或规格仍在使用，不能删除'}[error.code])||error.message?.split('\n')[0]||'商品操作被拒绝')
 return result
}
module.exports={handle,prepareProduct,storeImage}
