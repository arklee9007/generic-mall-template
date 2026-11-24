import { cpSync, mkdirSync, readFileSync, writeFileSync, existsSync, readdirSync, statSync, rmSync } from 'node:fs'
import { resolve, relative, dirname, extname, isAbsolute, join } from 'node:path'
import { spawnSync, execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
const root = process.cwd(), releaseRoot = resolve('dist/releases'), out = resolve(releaseRoot, 'generic'), evidence = resolve('docs/evidence/build/generic')
const rel = relative(releaseRoot, out)
if (!rel || rel.startsWith('..') || isAbsolute(rel)) throw Error('Unsafe release directory')
rmSync(out, { recursive: true, force: true }); mkdirSync(out, { recursive: true }); mkdirSync(evidence, { recursive: true })
const log = []
function command(name, args, env = {}) {
  const started = new Date().toISOString(), r = spawnSync(name, args, { encoding: 'utf8', windowsHide: true, env: { ...process.env, ...env }, maxBuffer: 20 * 1024 * 1024 })
  log.push({ command: [name, ...args], started, exitCode: r.status, stdout: r.stdout, stderr: r.stderr })
  writeFileSync(evidence + '/build-log.json', JSON.stringify(log, null, 2) + '\n')
  if (r.status !== 0) throw Error('Release command failed: ' + args.join(' '))
}
// npm 不一定装在 node 旁边（如本机 npm 在 /opt/hatch-image/bin），直接走 PATH 上的 npm；Windows 上用 npm.cmd。
const npmBin = process.platform === 'win32' ? 'npm.cmd' : 'npm'
function npm(args, env) { command(npmBin, args, env) }
const domains = ['shop', 'auth', 'customer', 'order', 'member', 'admin']
command(process.execPath, ['scripts/build-business-functions.mjs', ...domains])
npm(['run', 'type-check', '-w', '@generic-mall/admin'])
npm(['run', 'build', '-w', '@generic-mall/admin'], { GENERIC_ADMIN_OUT_DIR: out + '/admin' })
npm(['run', 'build:mp-weixin', '-w', '@generic-mall/storefront'])
cpSync('apps/storefront/dist/build/mp-weixin', out + '/miniapp', { recursive: true })
cpSync('config/project.json', out + '/project.json')
const functions = [...domains, 'health']
for (const name of functions) {
  const source = resolve('cloudfunctions', name), target = join(out, 'cloudfunctions', name)
  mkdirSync(target, { recursive: true })
  const visited = new Set()
  function collect(file) {
    const absolute = resolve(file)
    if (visited.has(absolute)) return
    visited.add(absolute)
    const local = relative(source, absolute)
    if (local.startsWith('..') || isAbsolute(local)) throw Error('Dependency escapes function root')
    mkdirSync(dirname(join(target, local)), { recursive: true })
    cpSync(absolute, join(target, local))
    if (!['.js', '.cjs'].includes(extname(absolute))) return
    for (const match of readFileSync(absolute, 'utf8').matchAll(/require\(\s*['"](\.[^'"]+)['"]\s*\)/g)) {
      const base = resolve(dirname(absolute), match[1])
      const dependency = [base, base + '.js', base + '.cjs', base + '.json', join(base, 'index.js')].find(p => existsSync(p) && statSync(p).isFile())
      if (!dependency) throw Error('Missing dependency ' + match[1])
      collect(dependency)
    }
  }
  collect(source + '/index.js')
  for (const file of ['package.json', 'package-lock.json']) if (existsSync(source + '/' + file)) cpSync(source + '/' + file, target + '/' + file)
}
function files(dir) { return readdirSync(dir, { withFileTypes: true }).flatMap(item => item.isDirectory() ? files(join(dir, item.name)) : [join(dir, item.name)]) }
const hash = file => createHash('sha256').update(readFileSync(file)).digest('hex')
const database = files(resolve('cloudbase/migrations')).sort().map(path => ({ path: relative(root, path).replaceAll('\\', '/'), sha256: hash(path) }))
const databaseSha256 = createHash('sha256').update(JSON.stringify(database)).digest('hex')
mkdirSync(releaseRoot + '/database', { recursive: true })
cpSync('cloudbase/migrations', releaseRoot + '/database/migrations', { recursive: true })
writeFileSync(out + '/database-reference.json', JSON.stringify({ path: '../database/migrations', sha256: databaseSha256, count: database.length }, null, 2) + '\n')
const deploy = { edition: 'generic', functions: functions.map(name => ({ name, path: 'cloudfunctions/' + name })), admin: 'admin', miniapp: 'miniapp' }
writeFileSync(out + '/deploy.json', JSON.stringify(deploy, null, 2) + '\n')
const manifest = files(out).sort().map(file => ({ path: relative(out, file).replaceAll('\\', '/'), bytes: statSync(file).size, sha256: hash(file) }))
const prohibited = /material-import|material\.|MaterialImporter|ProductRuleEditor|license_disabled|checkLicense|runLicensed|coupon-issue|mail-notify|product-schedule|mall_run_product_schedule|mall_admin_product_rule|emailjs|WANDER|WONDER|wonder-original|wx[0-9a-f]{16}|tcloudbaseapp\.com/
for (const item of manifest) { if (prohibited.test(item.path) || prohibited.test(readFileSync(join(out, item.path), 'utf8'))) throw Error('Release artifact contains forbidden content: ' + item.path) }
const result = { result: 'PASS', edition: 'generic', functions, databaseSha256, database, files: manifest, totalBytes: manifest.reduce((sum, file) => sum + file.bytes, 0), prohibitedFeatureScan: 'PASS', miniappBuild: 'actual build:mp-weixin; H5 not built', sourceCommit: execFileSync('git', ['rev-parse', 'HEAD']).toString().trim() }
writeFileSync(evidence + '/manifest.json', JSON.stringify(result, null, 2) + '\n')
console.log(JSON.stringify({ result: 'PASS', edition: 'generic', files: manifest.length, bytes: result.totalBytes, functions, databaseSha256 }))
