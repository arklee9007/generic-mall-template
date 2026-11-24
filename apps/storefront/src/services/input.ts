export function confirmedValue(event: unknown, fallback: string): string {
  if (event && typeof event === 'object' && 'detail' in event && event.detail && typeof event.detail === 'object' && 'value' in event.detail && typeof event.detail.value === 'string') return event.detail.value
  return fallback
}
