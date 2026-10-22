/** The cookie the API sets when an app starts OAuth: only this browser may answer. */
export const BINDING_COOKIE = 'aaru_oauth'

/**
 * Where to go after signing in. Only Aaru's own app pages, the OAuth consent page, the
 * extension's connect page and a friend invite link, never another origin (`//host`,
 * `https://…`) and never a protocol trick.
 */
export function safeNext(next: unknown): string {
  if (typeof next !== 'string') return '/app'
  if (!next.startsWith('/') || next.startsWith('//') || next.includes('\\'))
    return '/app'
  const allowed =
    next === '/app' ||
    next.startsWith('/app/') ||
    next.startsWith('/oauth/consent?') ||
    next === '/connect/extension' ||
    next.startsWith('/connect/extension?') ||
    /^\/i\/[A-Za-z0-9]{1,32}$/.test(next)
  return allowed ? next : '/app'
}
