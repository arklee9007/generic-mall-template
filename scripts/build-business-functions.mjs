import { cpSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs'
import { resolve, relative, isAbsolute } from 'node:path'
const domains = process.argv.slice(2)
if (!domains.length) throw new Error('Provide business function names')
for (const domain of domains) {
  if (!['shop', 'auth', 'customer', 'order', 'member', 'admin'].includes(domain)) throw new Error('Unknown business domain')
  const dir = `cloudfunctions/${domain}`; mkdirSync(dir, { recursive: true })
  for (const part of ['lib', 'modules']) {
    const target = resolve(dir, part), rel = relative(resolve(dir), target)
    if (!rel || rel.startsWith('..') || isAbsolute(rel)) throw new Error('Unsafe generated target')
    rmSync(target, { recursive: true, force: true })
  }
  cpSync('server', `${dir}/lib`, { recursive: true })
  writeFileSync(`${dir}/index.js`, "'use strict'\nexports.main = require('./lib/" + (domain === 'admin' ? 'admin-http' : domain) + "').main\n")
  const dependencies = { '@cloudbase/node-sdk': '3.18.7' }
  writeFileSync(`${dir}/package.json`, JSON.stringify({ name: `generic-mall-${domain}`, version: '1.0.0', private: true, main: 'index.js', dependencies }, null, 2) + '\n')
  const lock = JSON.parse(readFileSync('cloudfunctions/shop/package-lock.json', 'utf8'))
  lock.name = `generic-mall-${domain}`; lock.version = '1.0.0'
  lock.packages[''].name = lock.name; lock.packages[''].version = lock.version
  writeFileSync(`${dir}/package-lock.json`, JSON.stringify(lock, null, 2) + '\n')
}
console.log('Built:', domains.join(', '))
