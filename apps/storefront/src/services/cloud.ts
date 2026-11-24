import project from '../../../../config/project.json'
// #ifdef H5
import cloudbase from '@cloudbase/js-sdk'
let webApp: ReturnType<typeof cloudbase.init> | undefined
// #endif
interface Reply { ok: boolean; code?: string; message?: string }
export async function callCloud<T>(name: string, data: Record<string, unknown> = {}): Promise<T> {
  let payload: unknown
  // #ifdef MP-WEIXIN
  if (!wx.cloud) throw new Error('当前微信版本不支持云开发')
  payload = (await wx.cloud.callFunction({ name, data, config: { env: project.cloudbase.envId } })).result
  // #endif
  // #ifdef H5
  const key = import.meta.env.VITE_CLOUDBASE_PUBLISHABLE_KEY
  if (!key) throw new Error('H5 CloudBase 公开访问配置缺失')
  webApp ||= cloudbase.init({ env: project.cloudbase.envId, accessKey: key })
  payload = (await webApp.callFunction({ name, data })).result
  // #endif
  if (typeof payload === 'string') payload = JSON.parse(payload)
  if (!payload || typeof payload !== 'object' || !('ok' in payload)) throw new Error('云服务返回格式不正确')
  const reply = payload as Reply
  if (!reply.ok) {
    // 服务端内部异常码（如 INVALID_WRITE_TABLE）不直达顾客：换成人话，已知业务错误（中文说明）原样透传。
    const FRIENDLY: Record<string, string> = { INVALID_WRITE_TABLE: '提交没有成功，请稍后重试', INVALID_UPDATE_TABLE: '提交没有成功，请稍后重试', INVALID_LOCK_TABLE: '提交没有成功，请稍后重试', UPDATE_WITHOUT_LOCK: '提交没有成功，请稍后重试', STALE_ROW: '数据刚刚有更新，请刷新后重试' }
    const raw = reply.message || ''
    const message = FRIENDLY[raw] || (/^[A-Z][A-Z0-9_]{2,}$/.test(raw) ? '服务暂时不可用，请稍后重试' : raw || '云服务暂时不可用')
    const error = new Error(message); Object.assign(error, { code: reply.code }); throw error
  }
  return payload as T
}
