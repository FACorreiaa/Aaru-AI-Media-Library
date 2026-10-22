import { safeNext } from '../oauth/model'

// UX-011: the sign-in email's link opens /auth/verify in a fresh tab, and the server builds that
// link without the page the user was headed to. Sign-in leaves the destination here when it
// sends the email; the link's page reads it once. Same browser only, and it expires with the
// link (15 minutes), so an old one never redirects a later sign-in.

const KEY = 'aaru.sign-in.next'
const LIFETIME_MS = 15 * 60 * 1000

export function rememberNext(next: string | undefined, now = Date.now()) {
  try {
    if (!next || safeNext(next) === '/app') localStorage.removeItem(KEY)
    else localStorage.setItem(KEY, JSON.stringify({ next, at: now }))
  } catch {
    // Storage refused (a private window): the link lands on Home instead.
  }
}

/** The remembered destination, at most once, else Home. */
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
