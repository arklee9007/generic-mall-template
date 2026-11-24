'use strict'
const r=require('./runtime')
function string(value,max=500,required=false){if(typeof value!=='string'||value.length>max||required&&!value.trim())r.fail('INVALID_HOME_FIELD','请检查首页字段长度及必填项');return value.trim()}
function integer(value,min=0,max=100000){const n=Number(value);if(!Number.isSafeInteger(n)||n<min||n>max)r.fail('INVALID_HOME_NUMBER','排序或间隔数值超出范围');return n}
function link(value){const s=string(value||'');if(s&&!s.startsWith('/pages/')&&!s.startsWith('https://'))r.fail('INVALID_HOME_LINK','跳转仅支持小程序页面路径或HTTPS链接');return s}
async function handle(e,instance,db,admin){
 if(e.action==='home.list'){
  const [banners,picks,announcements,settings,products,categories]=await Promise.all([r.rows(db.from('banners').select('*').order('sort')),r.rows(db.from('home_picks').select('*').order('sort')),r.rows(db.from('announcements').select('*').order('sort')),r.one(db,'settings','global'),r.rows(db.from('products').select('_id,name,stage,reviewStatus,onShelf,categoryId').limit(500)),r.rows(db.from('categories').select('_id,parentId,visible').limit(500))])
  return {banners,picks,announcements,seconds:Number(settings.announcementIntervalSeconds),splash:{enabled:settings.splashEnabled===true,image:settings.splashImage||'',link:settings.splashLink||'',seconds:Number(settings.splashSeconds||5)},products:products.map(p=>({...p,eligible:p.stage==='shelf'&&p.reviewStatus==='approved'&&p.onShelf&&categories.some(c=>c._id===p.categoryId&&c.visible&&(!c.parentId||categories.some(parent=>parent._id===c.parentId&&parent.visible)))}))}
 }
 const op=e.action.slice('home.'.length),id=(op==='interval'||op==='splash.save')?'global':e.id||r.uuid(),data=e.data||{};let value
 if(typeof id!=='string'||id.length>100)r.fail('INVALID_HOME_ID')
 if(op==='banner.save'){const image=string(data.image,1200,true);if(!image.startsWith('https://')&&!image.startsWith('/static/'))r.fail('INVALID_HOME_IMAGE','请选择HTTPS或已部署的站内图片');value={image,link:link(data.link),sort:integer(data.sort),visible:data.visible===true}}
 else if(op==='announcement.save')value={text:string(data.text,300,true),link:link(data.link),sort:integer(data.sort),visible:data.visible===true}
 else if(op==='pick.save')value={sort:integer(data.sort)}
 else if(op==='interval')value={seconds:integer(data.seconds,1,60)}
 else if(op==='splash.save'){const splashImage=string(data.image||'',1200);if(splashImage&&!splashImage.startsWith('https://')&&!splashImage.startsWith('/static/'))r.fail('INVALID_HOME_IMAGE','开屏图片须为HTTPS或已部署的站内图片');if(data.enabled===true&&!splashImage)r.fail('INVALID_HOME_IMAGE','启用开屏广告前请先填写广告图');value={enabled:data.enabled===true,image:splashImage,link:link(data.link),seconds:integer(data.seconds,1,15)}}

 else if(['banner.delete','announcement.delete','pick.delete'].includes(op))value={}
 else r.fail('UNKNOWN_ACTION')
 const result=await db.rpc('mall_admin_home',{p_admin:admin._id,p_op:op,p_id:id,p_data:value})
 if(result.error)r.fail('HOME_SAVE_REJECTED',result.error.message?.includes('PICK_PRODUCT_NOT_VISIBLE')?'主推商品须已审核上架且分类可见':'首页设置保存失败')
 return result.data
}
module.exports={handle}

