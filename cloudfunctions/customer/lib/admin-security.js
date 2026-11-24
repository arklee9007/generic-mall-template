'use strict'
const {randomBytes,scryptSync,timingSafeEqual,createHash}=require('node:crypto')
const tokenHash=token=>createHash('sha256').update(token).digest('hex')
function strong(password){return typeof password==='string'&&password.length>=16&&password.length<=128&&/[a-z]/.test(password)&&/[A-Z]/.test(password)&&/[0-9]/.test(password)&&/[^A-Za-z0-9]/.test(password)}
function hashPassword(password){const salt=randomBytes(32).toString('hex');return 'scrypt:'+salt+':'+scryptSync(password,salt,64).toString('hex')}
const dummyHash='scrypt:'+ '0'.repeat(64)+':'+ '0'.repeat(128)
function verifyPassword(password,stored){
  const parts=(stored||dummyHash).split(':')
  if(typeof password!=='string'||password.length>128||parts.length!==3||parts[0]!=='scrypt'||!/^[0-9a-f]{128}$/.test(parts[2]))return false
  return timingSafeEqual(scryptSync(password,parts[1],64),Buffer.from(parts[2],'hex'))
}
module.exports={strong,hashPassword,verifyPassword,tokenHash,newToken:()=>randomBytes(32).toString('hex')}
