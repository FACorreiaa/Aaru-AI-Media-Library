import { safeNext } from '../oauth/model'

// The email link opens `/auth/verify` in a fresh tab that has lost `?next=`, so the sign-in
// page remembers where it was headed (a friend invite, the extension's connect page) in this
// browser for as long as the emailed link lives.
const KEY = 'aaru.next'
const LIFETIME_MS = 15 * 60 * 1000

export function rememberNext(next: string | undefined, now = Date.now()) {
  try {
    if (next && safeNext(next) === next)
      localStorage.setItem(KEY, JSON.stringify({ next, at: now }))
    else localStorage.removeItem(KEY)
  } catch {
    // Storage blocked: the link falls back to /app.
  }
}

/** The remembered destination, once; `/app` when there is none or it went stale. */
export function takeNext(now = Date.now()): string {
  try {
    const raw = localStorage.getItem(KEY)
    localStorage.removeItem(KEY)
    if (!raw) return '/app'
    const saved = JSON.parse(raw) as { next?: unknown; at?: unknown }
    if (typeof saved.at !== 'number' || now - saved.at > LIFETIME_MS)
      return '/app'
    return safeNext(saved.next)
  } catch {
    return '/app'
  }
}
