import {execFileSync} from 'node:child_process'
import {readFileSync,existsSync} from 'node:fs'
const files=execFileSync('git',['diff','--cached','--name-only','--diff-filter=ACMR','-z']).toString().split('\0').filter(Boolean),secrets=[]
for(const path of ['config/admin.local.json','config/mail.local.json'])if(existsSync(path)){const config=JSON.parse(readFileSync(path,'utf8').replace(/^\uFEFF/,''));for(const key of ['password','pass'])if(config[key])secrets.push(config[key])}
for(const file of files){
 if(/(?:\.env(?!\.example)|\.local(?:\.|$)|\.pem$|\.key$|private\.config|(?:^|\/)auth\.json$|node_modules)/i.test(file))throw Error('Forbidden staged filename')
 const bytes=execFileSync('git',['show',':'+file],{maxBuffer:64*1024*1024}),source=bytes.toString('utf8')
 if(secrets.some(secret=>source.includes(secret))||/-----BEGIN [A-Z ]*PRIVATE KEY-----|AKID[0-9A-Za-z]{20,}/.test(source))throw Error('Staged secret scan rejected content')
}
console.log('PASS staged filename/private-key/local-credential scan: '+files.length+' files')
