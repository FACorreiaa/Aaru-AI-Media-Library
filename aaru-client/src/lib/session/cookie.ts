/** The session lives in an HttpOnly cookie: page scripts can never read the token. */
export const SESSION_COOKIE = 'aaru_session'

/** Matches the server's 90-day session lifetime. */
const NINETY_DAYS = 90 * 24 * 60 * 60

export const sessionCookieOptions = {
  httpOnly: true,
  secure: true,
  sameSite: 'lax',
  path: '/',
  maxAge: NINETY_DAYS,
} as const
