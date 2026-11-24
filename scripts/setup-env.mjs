// 一键填入买家自己的 AppID / 环境 ID / 后台域名（三处一致 + 策略占位替换）。
// 用法：node scripts/setup-env.mjs --appid wx<16位小写十六进制> --env-id my-env-xxxx --admin-host admin.example.com [--region ap-shanghai] [--check]
// --check 只打印将要改的内容，不写盘。重复运行结果相同（幂等）。
import { readFileSync, writeFileSync, readdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const args = process.argv.slice(2)
const flag = (n) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : null }
const dryRun = args.includes('--check')
const appid = flag('--appid'), envId = flag('--env-id'), adminHost = flag('--admin-host'), region = flag('--region') || 'ap-shanghai'
if (!appid || !/^wx[0-9a-f]{16}$/.test(appid)) { console.error('须提供 --appid，格式为 wx + 16 位小写十六进制'); process.exit(2) }
if (!envId) { console.error('须提供 --env-id（CloudBase 环境 ID）'); process.exit(2) }
if (!adminHost) { console.error('须提供 --admin-host（后台云函数域名，如 admin-xxx.example.com）'); process.exit(2) }
const changes = []
function editJson(rel, mutate) {
  const p = join(ROOT, rel)
  const data = JSON.parse(readFileSync(p, 'utf-8'))
  const before = JSON.stringify(data)
  mutate(data)
  if (JSON.stringify(data) !== before) { changes.push(rel); if (!dryRun) writeFileSync(p, JSON.stringify(data, null, 2) + '\n', 'utf-8') }
}
editJson('config/project.json', d => { d.wechatAppId = appid; d.cloudbase.envId = envId; d.cloudbase.region = region })
editJson('project.config.json', d => { d.appid = appid })
editJson('apps/storefront/src/manifest.json', d => { d.appid = appid; d['mp-weixin'].appid = appid })
for (const f of readdirSync(join(ROOT, 'cloudbase/policies')).filter(f => f.endsWith('.rego'))) {
  const p = join(ROOT, 'cloudbase/policies', f)
  const text = readFileSync(p, 'utf-8')
  const next = text.replaceAll('{{ENV_ID}}', envId).replaceAll('{{ADMIN_FUNCTION_HOST}}', adminHost)
  if (next !== text) { changes.push('cloudbase/policies/' + f); if (!dryRun) writeFileSync(p, next, 'utf-8') }
}
console.log((dryRun ? '[试看] 将改动 ' : '已改动 ') + changes.length + ' 个文件：')
changes.forEach(c => console.log(' - ' + c))
if (!changes.length) console.log('无改动（已是目标值或占位已替换）。')
console.log('另须手动在云函数环境变量中设置：WECHAT_APP_ID=' + appid + '，ADMIN_ORIGIN=https://你的后台域名，TCB_REGION=' + region)
