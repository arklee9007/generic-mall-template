'use strict'
const r=require('./runtime')
function shopConfigValue(d){
  if(!d||typeof d!=='object')r.fail('INVALID_SHOP_CONFIG','店铺配置不正确')
  if(typeof d.brandWord!=='string'||d.brandWord.length>40)r.fail('INVALID_SHOP_CONFIG','品牌字须为 40 字以内')
  if(typeof d.brandColor!=='string'||!/^#[0-9a-fA-F]{6}$/.test(d.brandColor))r.fail('INVALID_SHOP_CONFIG','主色须为 #RRGGBB 形态')
  if(typeof d.logo!=='string'||d.logo.length>1200||(d.logo&&!/^https:\/\//.test(d.logo)&&!d.logo.startsWith('/static/')))r.fail('INVALID_SHOP_CONFIG','Logo 须为HTTPS地址或站内图片')
  if(typeof d.footerText!=='string'||d.footerText.length>200)r.fail('INVALID_SHOP_CONFIG','页脚文字须为 200 字以内')
  if(!Array.isArray(d.specAxes)||d.specAxes.length>3||!d.specAxes.every(x=>typeof x==='string'&&x.trim()&&x.trim().length<=10))r.fail('INVALID_SHOP_CONFIG','规格轴名须为 1–10 字，最多 3 轴')
  const chart=d.specChart||{}
  if(typeof chart.enabled!=='boolean'||typeof chart.title!=='string'||!chart.title.trim()||chart.title.trim().length>20)r.fail('INVALID_SHOP_CONFIG','规格说明标题不正确')
  if(typeof d.reviewRequired!=='boolean')r.fail('INVALID_SHOP_CONFIG','审核开关不正确')
  return {brandWord:d.brandWord.trim(),brandColor:d.brandColor,logo:d.logo.trim(),footerText:d.footerText.trim(),specAxes:d.specAxes.map(x=>x.trim()),specChart:{enabled:chart.enabled,title:chart.title.trim()},reviewRequired:d.reviewRequired}
}
exports.handle=async(e,instance,db,admin)=>{
 if(e.action==='system.get'){const rows=await r.rows(db.from('settings').select('shopName,servicePhone,serviceHours,notifyEmail,smsEnabled,realPaymentEnabled,shopConfig').eq('_id','global'));return {config:rows[0]}}
 if(e.action==='system.shopConfig'){
  const value=shopConfigValue(e.data||{})
  const {data,error}=await db.rpc('mall_admin_shop_config',{p_admin:admin._id,p_data:value});if(error)r.fail('SHOP_CONFIG_REJECTED','店铺配置保存失败');return data
 }
 if(e.action!=='system.save')r.fail('UNKNOWN_SYSTEM_OPERATION')
 const d=e.data||{},value={};if(d.smsEnabled||d.realPaymentEnabled||d.smsKeys!==undefined||d.wxpayKeys!==undefined)r.fail('LIVE_INTEGRATION_DISABLED','本窗仅预留短信与支付参数位，不启用真实服务')
 for(const [key,max] of [['shopName',120],['servicePhone',40],['serviceHours',120],['notifyEmail',254]]){if(typeof d[key]!=='string'||d[key].length>max)r.fail('INVALID_SYSTEM_INPUT');value[key]=d[key].trim()}
 if(!value.shopName||!value.serviceHours||value.servicePhone&&! /^[+\d()\-\s]{3,40}$/.test(value.servicePhone)||value.notifyEmail&&! /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.notifyEmail))r.fail('INVALID_SYSTEM_INPUT','请检查店名、服务时间、联系电话和邮箱格式')
 const {data,error}=await db.rpc('mall_admin_system',{p_admin:admin._id,p_data:value});if(error)r.fail('SYSTEM_SAVE_FAILED','系统设置保存失败');return data
}
