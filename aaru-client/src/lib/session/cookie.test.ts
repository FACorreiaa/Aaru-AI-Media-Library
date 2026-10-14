import { describe, expect, it } from 'vitest'
import { SESSION_COOKIE, sessionCookieOptions } from './cookie'

describe('session cookie', () => {
  it('can never be read by page scripts or sent cross-site', () => {
    expect(SESSION_COOKIE).toBe('aaru_session')
    expect(sessionCookieOptions.httpOnly).toBe(true)
    expect(sessionCookieOptions.secure).toBe(true)
    expect(sessionCookieOptions.sameSite).toBe('lax')
  })

  it('lives as long as the server session (90 days)', () => {
    expect(sessionCookieOptions.maxAge).toBe(90 * 24 * 60 * 60)
  })
})
