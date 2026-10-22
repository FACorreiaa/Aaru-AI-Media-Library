// GAM-003 on the web: points and streak days are dated on the viewer's own calendar. The
// Worker runs in UTC and cannot know it, so the shell keeps the browser's zone in a cookie and
// `api()` forwards it to the server as `X-Timezone` on every signed-in call.

export const TIMEZONE_COOKIE = 'aaru_tz'

const ONE_YEAR = 60 * 60 * 24 * 365

/** An IANA zone the runtime knows (`Europe/Lisbon`), or null for anything else. */
export function validTimeZone(value: string | null | undefined): string | null {
  if (!value || value.length > 64 || !/^[A-Za-z0-9_+\-/]+$/.test(value))
    return null
  try {
    new Intl.DateTimeFormat('en', { timeZone: value })
    return value
  } catch {
    return null
  }
}

/** The browser's zone, UTC when it has none. */
export function viewerTimeZone(): string {
  return (
    validTimeZone(Intl.DateTimeFormat().resolvedOptions().timeZone) ?? 'UTC'
  )
}

/** Browser only: writes the zone cookie when it is missing or the viewer has travelled. */
export function rememberTimeZone(): void {
  if (typeof document === 'undefined') return
  const zone = viewerTimeZone()
  const current = document.cookie
    .split('; ')
    .find((part) => part.startsWith(`${TIMEZONE_COOKIE}=`))
  if (current === `${TIMEZONE_COOKIE}=${encodeURIComponent(zone)}`) return
  const secure = location.protocol === 'https:' ? '; Secure' : ''
  document.cookie = `${TIMEZONE_COOKIE}=${encodeURIComponent(zone)}; Path=/; Max-Age=${ONE_YEAR}; SameSite=Lax${secure}`
}
