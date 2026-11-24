'use strict'
// N 档会员档位引擎（纯函数为主，可单测）：等级只按累计充值实付定级，只升不降；赠送不计入。
const r=require('./runtime')
async function loadTiers(db){
  const rows=await r.rows(db.from('member_tiers').select('*').eq('enabled',true).order('level'))
  return rows.map(t=>({level:r.int(t.level),name:t.name,threshold:r.int(t.threshold),discountBps:r.int(t.discountBps),cardBg:t.cardBg||'',cardText:t.cardText||'',sort:r.int(t.sort||0)}))
}
function memberConfig(shopConfig){
  const m=(shopConfig&&shopConfig.member)||{}
  return {enabled:m.enabled!==false,rechargeEnabled:m.rechargeEnabled!==false,packages:Array.isArray(m.packages)?m.packages:[]}
}
function tierForLevel(tiers,level){let found=null;for(const t of tiers){if(t.level<=level&&(found===null||t.level>found.level))found=t}return found}
function discountBpsFor(tiers,level,enabled){if(!enabled)return 10000;const t=tierForLevel(tiers,level);return t?t.discountBps:10000}
function levelForCumulative(tiers,cumulative){let level=0;for(const t of tiers){if(cumulative>=t.threshold&&t.level>level)level=t.level}return level}
function bonusFor(packages,amount){const hit=packages.find(p=>Number(p.amount)===amount);return hit?Number(hit.bonus)||0:0}
function tierView(tiers,level){
  const t=tierForLevel(tiers,level)
  return t?{level:t.level,name:t.name,discountBps:t.discountBps,cardBg:t.cardBg,cardText:t.cardText}:{level:0,name:'普通顾客',discountBps:10000,cardBg:'',cardText:''}
}
module.exports={loadTiers,memberConfig,tierForLevel,discountBpsFor,levelForCumulative,bonusFor,tierView}
