const endpoint = import.meta.env.VITE_ADMIN_API_URL
let token = ''
let remember = false
try { token = localStorage.getItem('admin-token') || sessionStorage.getItem('admin-token') || '' } catch { token = '' }
export interface Dashboard { todayOrders: number; todaySales: number; todayRefunds: number; monthSales: number; monthRefunds: number; pendingShip: number; checkedAt: string }
export interface AdminReply { ok: boolean; code?: string; message?: string; token?: string; username?: string; expiresIn?: number; dashboard?: Dashboard }
export function hasStoredSession() { return !!token }
export function setRemember(value: boolean) { remember = value }
function persist() { try { localStorage.removeItem('admin-token'); sessionStorage.removeItem('admin-token'); (remember ? localStorage : sessionStorage).setItem('admin-token', token) } catch { /* storage unavailable: keep in-memory token */ } }
function clear() { token = ''; try { localStorage.removeItem('admin-token'); sessionStorage.removeItem('admin-token') } catch { /* ignore */ } }
export async function callAdmin<T extends object = Record<string, never>>(action: string, data: Record<string, unknown> = {}): Promise<AdminReply & T> {
  if (!endpoint?.startsWith('https://')) throw new Error('后台访问配置缺失')
  const response = await fetch(endpoint, { method: 'POST', credentials: 'omit', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ...data, action, ...(token ? { token } : {}) }) })
  const reply: AdminReply & T = await response.json()
  if (!reply.ok) { if (reply.code?.startsWith('ADMIN_TOKEN')) { clear(); window.dispatchEvent(new Event('admin-session-expired')) } throw new Error(reply.message || '操作失败') }
  if (reply.token) { token = reply.token; persist() }
  if (action === 'logout' || action === 'changePassword') clear()
  return reply
}
export function readFileBase64(file: File): Promise<string> { return new Promise((resolve, reject) => { const reader = new FileReader(); reader.onload = () => resolve(String(reader.result).split(',')[1]); reader.onerror = reject; reader.readAsDataURL(file) }) }
// 分片上传：网关对单次请求体大小有上限，文件 base64 切成约 44KB 一片逐片发送，
// 服务端在 upload.finish 里拼装后存为图片（只支持图片上传）。
export async function uploadAdminFile<T extends object = Record<string, never>>(file: File, fields: Record<string, unknown>, onProgress?: (done: number, total: number) => void): Promise<AdminReply & T> {
  const base64 = await readFileBase64(file)
  const SLICE = 43692, total = Math.max(1, Math.ceil(base64.length / SLICE))
  const uploadId = typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : 'up-' + Date.now() + '-' + Math.random().toString(36).slice(2, 10)
  try {
    for (let i = 0; i < total; i++) { await callAdmin('upload.chunk', { uploadId, index: i, data: base64.slice(i * SLICE, (i + 1) * SLICE) }); onProgress?.(i + 1, total) }
  } catch (error) { try { await callAdmin('upload.abort', { uploadId }) } catch { /* 清理失败不掩盖原始错误 */ } throw error }
  return callAdmin<T>('upload.finish', { uploadId, chunks: total, size: file.size, ...fields })
}
