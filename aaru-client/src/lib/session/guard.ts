import { redirect } from '@tanstack/solid-router'
import { deleteCookie, getCookie } from '@tanstack/solid-start/server'
import { SESSION_COOKIE } from './cookie'

/** The session token for a server function, or a redirect to sign-in. Server-only. */
export function sessionToken(): string {
  const token = getCookie(SESSION_COOKIE)
  if (!token) throw redirect({ to: '/sign-in' })
  return token
}

/** The server refused the session (a 401): clear it once and go to sign-in. */
export function sessionRejected(): never {
  deleteCookie(SESSION_COOKIE, { path: '/' })
  throw redirect({ to: '/sign-in' })
}
