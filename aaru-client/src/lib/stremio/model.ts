import type { AgentToken } from './server'

/** "Used today", "Used 3 days ago", or "Not used yet". `lastUsedAt` is recorded hourly at most. */
export function lastUsedLabel(token: AgentToken, now = new Date()): string {
  if (!token.lastUsedAt) return 'Not used yet'
  const days = Math.floor(
    (now.getTime() - new Date(token.lastUsedAt).getTime()) / 86_400_000,
  )
  if (days <= 0) return 'Used today'
  if (days === 1) return 'Used yesterday'
  return `Used ${days} days ago`
}

/** Whether a link may change the library beyond ticking what was watched. */
export const canChangeLibrary = (token: AgentToken) =>
  token.scopes.includes('library:write')
