'use strict'
function amount(value){const n=Number(value);if(!Number.isSafeInteger(n)||n<0)throw new Error('INVALID_MONEY');return n}
function safe(value){const n=Number(value);return amount(n)}
function add(...values){return safe(values.reduce((sum,value)=>sum+BigInt(amount(value)),0n))}
function multiply(value,qty){if(!Number.isInteger(qty)||qty<1||qty>99)throw new Error('INVALID_QUANTITY');return safe(BigInt(amount(value))*BigInt(qty))}
// 折扣一律按基点整数运算（10000=不打折），避免浮点误差；余额拆分：勾选余额支付时先扣余额，不足部分走其他方式。
function totalsBps(goodsAmount,freightAmount,bps,opts={}){
  goodsAmount=amount(goodsAmount);freightAmount=amount(freightAmount)
  if(!Number.isSafeInteger(bps)||bps<0||bps>10000)throw new Error('INVALID_DISCOUNT_CONFIG')
  const discountAmount=safe((BigInt(goodsAmount)*BigInt(10000-bps)+5000n)/10000n)
  const payAmount=add(goodsAmount-discountAmount,freightAmount)
  const balance=opts.useBalance===true?amount(opts.balance||0):0
  const balancePaid=Math.min(balance,payAmount)
  return {goodsAmount,discountAmount,freightAmount,payAmount,balancePaid,wxPaid:payAmount-balancePaid}
}
function totals(goodsAmount,freightAmount,discountRate,opts={}){
  const discount=Number(discountRate==null?1:discountRate)
  if(!Number.isFinite(discount))throw new Error('INVALID_DISCOUNT_CONFIG')
  return totalsBps(goodsAmount,freightAmount,Math.round(discount*10000),opts)
}
module.exports={amount,add,multiply,totals,totalsBps}
