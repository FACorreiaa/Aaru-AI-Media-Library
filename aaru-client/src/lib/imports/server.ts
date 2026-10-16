import { createServerFn } from '@tanstack/solid-start'
import { deleteCookie } from '@tanstack/solid-start/server'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { SESSION_COOKIE } from '../session/cookie'
import { sessionRejected, sessionToken } from '../session/guard'
import type { components } from '../api/schema'

// APP-007 on the web: account and imports, over the same `/v1` routes as the Apple apps.

export type ImportJob = components['schemas']['ImportJob']
export type ImportDetail = components['schemas']['ImportDetail']
export type Account = components['schemas']['Me']

const MAX_BYTES = 5 * 1024 * 1024
const id = z.string().uuid()

function check<T>(
  result: { data?: T; error?: unknown; response: Response },
  fallback: string,
): T {
  if (result.response.status === 401) sessionRejected()
  if (result.data === undefined)
    throw new Error(errorMessage(result.error, fallback))
  return result.data
}

export const getAccount = createServerFn({ method: 'GET' }).handler(
  async (): Promise<Account> =>
    check(
      await api(sessionToken()).GET('/v1/me'),
      'Your account could not be loaded.',
    ),
)

/** Deletes the account on the server, then the session cookie here. */
export const deleteAccount = createServerFn({ method: 'POST' }).handler(
  async () => {
    const result = await api(sessionToken()).DELETE('/v1/me')
    if (result.response.status === 401) sessionRejected()
    if (!result.response.ok) {
      throw new Error(
        errorMessage(result.error, 'The account was not deleted.'),
      )
    }
    deleteCookie(SESSION_COOKIE, { path: '/' })
  },
)

export const listImports = createServerFn({ method: 'GET' }).handler(
  async (): Promise<ImportJob[]> =>
    check(
      await api(sessionToken()).GET('/v1/imports'),
      'Your imports could not be loaded.',
    ).items,
)

export const uploadImport = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      source: z.enum(['imdb', 'letterboxd', 'goodreads', 'mal']),
      filename: z.string().max(255),
      text: z.string().max(MAX_BYTES, 'That file is larger than 5 MB.'),
    }),
  )
  .handler(async ({ data }): Promise<ImportJob> =>
    check(
      await api(sessionToken()).POST('/v1/imports/csv', {
        params: { query: { source: data.source, filename: data.filename } },
        body: data.text as never,
        bodySerializer: (body: unknown) => body as string,
        headers: {
          'Content-Type':
            data.source === 'mal' ? 'application/xml' : 'text/csv',
        },
      }),
      'That file could not be imported.',
    ),
  )

/** IMP-014: a public AniList anime list, read by the server in the background. */
export const startAniListImport = createServerFn({ method: 'POST' })
  .validator(z.object({ username: z.string().trim().min(1).max(40) }))
  .handler(async ({ data }): Promise<ImportJob> =>
    check(
      await api(sessionToken()).POST('/v1/imports/anilist', {
        body: { username: data.username },
      }),
      'That AniList import could not be started.',
    ),
  )

export const getImport = createServerFn({ method: 'GET' })
  .validator(z.object({ id }))
  .handler(async ({ data }): Promise<ImportDetail> =>
    check(
      await api(sessionToken()).GET('/v1/imports/{id}', {
        params: { path: { id: data.id } },
      }),
      'The import could not be loaded.',
    ),
  )

export const applyImport = createServerFn({ method: 'POST' })
  .validator(z.object({ id }))
  .handler(async ({ data }): Promise<ImportJob> =>
    check(
      await api(sessionToken()).POST('/v1/imports/{id}/apply', {
        params: { path: { id: data.id } },
      }),
      'The import was not applied.',
    ),
  )

export const discardImport = createServerFn({ method: 'POST' })
  .validator(z.object({ id }))
  .handler(async ({ data }) => {
    const result = await api(sessionToken()).DELETE('/v1/imports/{id}', {
      params: { path: { id: data.id } },
    })
    if (result.response.status === 401) sessionRejected()
    if (!result.response.ok) {
      throw new Error(
        errorMessage(result.error, 'The import was not discarded.'),
      )
    }
  })
