import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { readdirSync, statSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { createRequire } from 'node:module'
const read = async p => JSON.parse(await readFile(p, 'utf8'))
const project = await read('config/project.json')
const ide = await read('project.config.json')
const manifest = await read('apps/storefront/src/manifest.json')
// AppID 三处必须一致；占位空值允许（买家部署前填写），非空时须为微信 AppID 形态。
assert.equal(ide.appid, project.wechatAppId)
assert.equal(manifest['mp-weixin'].appid, project.wechatAppId)
if (project.wechatAppId) assert.match(project.wechatAppId, /^wx[0-9a-f]{16}$/)
assert.equal(typeof project.cloudbase.envId, 'string')
const require = createRequire(import.meta.url)
const health = require('../cloudfunctions/health/index.js')
const previousEnv = process.env.TCB_ENV
process.env.TCB_ENV = 'check-only-env'
try {
  const result = await health.main({ secret: 'must-not-echo' }, { token: 'must-not-echo' })
  assert.deepEqual(Object.keys(result).sort(), ['envId', 'ok', 'serverTime', 'service', 'version'])
  assert.equal(result.envId, 'check-only-env')
  assert.equal(result.ok, true)
  assert.ok(Number.isFinite(Date.parse(result.serverTime)))
} finally {
  if (previousEnv === undefined) delete process.env.TCB_ENV
  else process.env.TCB_ENV = previousEnv
}
// 服务端与配置层不得残留旧品牌、旧环境与真实 AppID（前端层由发布扫描与人工 grep 复核）。
const forbidden = /wx[0-9a-f]{16}|wonder-original|WANDER|WONDER|tcloudbaseapp\.com/
function walk(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap(item => {
    const p = join(dir, item.name)
    if (item.isDirectory()) return walk(p)
    return statSync(p).isFile() ? [p] : []
  })
}
const roots = ['server', 'config', 'cloudbase', 'scripts', 'cloudfunctions']
// 两个扫描器文件本身必须写出违禁词表，故排除在扫描之外；它们只做检测，不进入发布产物。
const scannerFiles = new Set(['scripts/build-release.mjs', 'scripts/check-foundation.mjs'])
for (const root of roots) {
  for (const file of walk(root)) {
    if (scannerFiles.has(file)) continue
    if (/\.(png|jpg|jpeg|svg|lock)$/.test(file)) continue
    const text = readFileSync(file, 'utf8')
    assert.ok(!forbidden.test(text), 'Forbidden string in ' + file)
  }
}
for (const file of ['project.config.json', 'package.json']) assert.ok(!forbidden.test(readFileSync(file, 'utf8')), 'Forbidden string in ' + file)
console.log('PASS: AppID consistency; health allowlisted response; no legacy brand/env/AppID in server, config, cloudbase, scripts')
