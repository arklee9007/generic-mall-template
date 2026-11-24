'use strict'
// Only allowlisted diagnostics; never echo request/context or credential env vars.
exports.main = async () => {
  const envId = process.env.TCB_ENV || process.env.SCF_NAMESPACE
  if (!envId) throw new Error('HEALTH_ENV_ID_UNAVAILABLE')
  return { ok: true, service: 'generic-mall', version: '1.0.0', envId, serverTime: new Date().toISOString() }
}
