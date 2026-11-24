'use strict'
const r=require('./runtime'),c=require('./commerce'),money=require('./money'),mt=require('./member-tiers')
const TERMS_VERSION='recharge-20261115'
const TERMS='充值金额与赠送金额均进入店铺余额，仅限在本店消费使用；余额不足部分以下单时其他方式补足。会员等级按累计充值实付金额（不含赠送）定级，只升不降；等级折扣按下单时等级计算。退款时余额支付部分退回余额，其余按原路退回或依商家审核分路处理。'
async function accountView(db,user){
  const config=await c.settings(db),tiers=await mt.loadTiers(db),mc=mt.memberConfig(config.shopConfig)
  const view=mt.tierView(tiers,mc.enabled?user.level:0)
  return {account:{level:user.level,tierName:view.name,discountBps:mc.enabled?view.discountBps:10000,balance:user.balance,cumulativeRecharge:r.int(user.totalRecharge||0),isMember:mc.enabled&&user.level>0,cardBg:view.cardBg,cardText:view.cardText},memberEnabled:mc.enabled,rechargeEnabled:mc.rechargeEnabled,packages:mc.packages,terms:TERMS,termsVersion:TERMS_VERSION,simulated:true}
}
exports.main=r.handler(async(event,instance,db)=>{
  const user=await r.caller(db,r.identity(instance)),action=event.action||'account'
  if(action==='account')return accountView(db,user)
  if(action==='logs')return {records:await r.rows(db.from('recharge_records').select('amount,bonusAmount,level,requestKey,termsVersion,createdAt,simulated').eq('userId',user._id).order('createdAt',{ascending:false}).limit(100)),logs:await r.rows(db.from('balance_logs').select('type,amount,orderId,balanceAfter,remark,createdAt').eq('userId',user._id).order('createdAt',{ascending:false}).limit(100))}
  if(action==='recharge'){
    c.requestKey(event.requestKey)
    if(event.agreed!==true||event.termsVersion!==TERMS_VERSION)r.fail('RECHARGE_TERMS_REQUIRED','请阅读并同意充值条款')
    const old=(await r.rows(db.from('recharge_records').select('*').eq('userId',user._id).eq('requestKey',event.requestKey).limit(1)))[0]
    if(old)return {record:old,idempotent:true,simulated:true}
    const config=await c.settings(db);if(config.realPaymentEnabled)r.fail('UNSUPPORTED_LIVE_MODE')
    const mc=mt.memberConfig(config.shopConfig)
    if(!mc.enabled||!mc.rechargeEnabled)r.fail('RECHARGE_DISABLED','当前店铺未开通充值')
    const amount=money.amount(event.amount)
    if(amount<100||amount>100000000)r.fail('INVALID_RECHARGE_AMOUNT','单次充值须在 1 元到 100 万元之间')
    const bonus=mt.bonusFor(mc.packages,amount)
    if(user.balance+amount+bonus>9007199254740991)r.fail('BALANCE_OVERFLOW')
    const tiers=await mt.loadTiers(db)
    const cumulative=r.int(user.totalRecharge||0)+amount
    const newLevel=Math.max(user.level,mt.levelForCumulative(tiers,cumulative))
    const p=r.plan()
    r.lock(p,'users',user,['version','balance','level','totalRecharge'])
    const log=c.ledger(p,user,amount,'recharge','recharge:'+event.requestKey,null,user.balance+amount,'会员充值')
    if(bonus>0)c.ledger(p,user,bonus,'bonus','bonus:'+event.requestKey,null,user.balance+amount+bonus,'充值赠送')
    const record=r.insert(p,'recharge_records',{_id:r.uuid(),userId:user._id,tierId:null,amount,bonusAmount:bonus,level:newLevel,requestKey:event.requestKey,termsVersion:TERMS_VERSION,balanceLogId:log._id,simulated:true})
    r.update(p,'users',user._id,{balance:user.balance+amount+bonus,level:newLevel,totalRecharge:cumulative,version:r.int(user.version)+1})
    await r.commit(db,p)
    const fresh=await r.one(db,'users',user._id),view=await accountView(db,fresh)
    return {record,...view,simulated:true}
  }
  r.fail('UNKNOWN_ACTION')
})
