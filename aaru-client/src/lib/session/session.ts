import { createServerFn } from '@tanstack/solid-start'
import {
  deleteCookie,
  getCookie,
  setCookie,
} from '@tanstack/solid-start/server'
import { env } from 'cloudflare:workers'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { SESSION_COOKIE, sessionCookieOptions } from './cookie'

// WEB-001: the Worker holds the session cookie and forwards `/v1` calls with it. No logic of
// its own: every rule lives in aaru-server, exactly as for the Apple apps.

export type Session =
  { signedIn: false } | { signedIn: true; displayName: string | null }

export const getSession = createServerFn({ method: 'GET' }).handler(
  async (): Promise<Session> => {
    const token = getCookie(SESSION_COOKIE)
    if (!token) return { signedIn: false }
    try {
      const { data, response } = await api(token).GET('/v1/me')
      if (response.status === 401) {
        // The server refused the session: back to signed out, once.
        deleteCookie(SESSION_COOKIE, { path: '/' })
        return { signedIn: false }
      }
      return { signedIn: true, displayName: data?.displayName ?? null }
    } catch {
      // An unreachable API keeps the session; only a 401 ends it (as in the Apple apps).
      return { signedIn: true, displayName: null }
    }
  },
)

export const getSignInConfig = createServerFn({ method: 'GET' }).handler(
  async () => ({ appleServicesId: env.APPLE_SERVICES_ID || null }),
)

export const sendCode = createServerFn({ method: 'POST' })
  .validator(z.object({ email: z.string().trim().min(3) }))
  .handler(async ({ data }) => {
    const { error } = await api().POST('/v1/auth/email/link', {
      body: { email: data.email },
    })
    if (error)
      throw new Error(errorMessage(error, 'The code could not be sent.'))
  })

export const signInWithCode = createServerFn({ method: 'POST' })
  .validator(z.object({ email: z.string().trim(), code: z.string().trim() }))
  .handler(async ({ data }) => {
    const { data: session, error } = await api().POST('/v1/auth/email/verify', {
      body: { email: data.email, code: data.code },
    })
    if (!session)
      throw new Error(errorMessage(error, 'That code did not work.'))
    setCookie(SESSION_COOKIE, session.token, sessionCookieOptions)
  })

export const signInWithApple = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      identityToken: z.string().min(1),
      nonce: z.string().min(1),
      displayName: z.string().optional(),
    }),
  )
  .handler(async ({ data }) => {
    const { data: session, error } = await api().POST('/v1/auth/apple', {
      body: data,
    })
    if (!session) {
      throw new Error(
        errorMessage(error, 'The Apple sign-in could not be verified.'),
      )
    }
    setCookie(SESSION_COOKIE, session.token, sessionCookieOptions)
  })

/** Ends the session on the server when it can, and always in this browser. */
export const signOut = createServerFn({ method: 'POST' }).handler(async () => {
  const token = getCookie(SESSION_COOKIE)
  if (token)
    await api(token)
      .DELETE('/v1/auth/session')
      .catch(() => undefined)
  deleteCookie(SESSION_COOKIE, { path: '/' })
})
