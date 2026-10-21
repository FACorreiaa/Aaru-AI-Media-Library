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
      source: z.enum([
        'auto',
        'imdb',
        'letterboxd',
        'netflix',
        'goodreads',
        'mal',
      ]),
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
          // `auto` is sniffed by the server; the type only says which body this is.
          'Content-Type':
            data.source === 'mal' || data.text.trimStart().startsWith('<')
              ? 'application/xml'
              : 'text/csv',
        },
      }),
      'That file could not be imported.',
    ),
  )

/** IMP-009/010: Pogdesign CAT, as a pasted show list or the exported iCal file's text. */
export const uploadCatImport = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      text: z
        .string()
        .trim()
        .min(1, 'Paste your shows, one per line.')
        .max(MAX_BYTES, 'That file is larger than 5 MB.'),
    }),
  )
  .handler(async ({ data }): Promise<ImportJob> =>
    check(
      await api(sessionToken()).POST('/v1/imports/cat', {
        body: data.text as never,
        bodySerializer: (body: unknown) => body as string,
        headers: {
          'Content-Type': /^\uFEFF?\s*BEGIN:VCALENDAR/i.test(data.text)
            ? 'text/calendar'
            : 'text/plain',
        },
      }),
      'Those shows could not be imported.',
    ),
  )

/** IMP-010: the user's CAT iCal link. The server reads it once; the link is not kept. */
export const startCatFeedImport = createServerFn({ method: 'POST' })
  .validator(z.object({ url: z.string().trim().min(1).max(512) }))
  .handler(async ({ data }): Promise<ImportJob> =>
    check(
      await api(sessionToken()).POST('/v1/imports/cat/feed', {
        body: { url: data.url },
      }),
      'That CAT link could not be imported.',
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

export type TraktConnection = components['schemas']['TraktConnection']

/** IMP-002: whether this account has connected Trakt, and as whom. */
export const getTraktConnection = createServerFn({ method: 'GET' }).handler(
  async (): Promise<TraktConnection> =>
    check(
      await api(sessionToken()).GET('/v1/imports/trakt/connection'),
      'Your Trakt connection could not be loaded.',
    ),
)

/**
 * Starts a Trakt sign-in (PKCE, held by the server) and returns Trakt's page to open. Trakt
 * sends the browser back to `returnTo` with `?trakt=connected|denied|failed`; the server only
 * accepts Aaru's own origins.
 */
export const connectTrakt = createServerFn({ method: 'POST' })
  .validator(z.object({ returnTo: z.string().url().max(500) }))
  .handler(
    async ({ data }): Promise<string> =>
      check(
        await api(sessionToken()).POST('/v1/imports/trakt/connect', {
          body: { returnTo: data.returnTo },
        }),
        'Trakt could not be reached. Try again in a minute.',
      ).authorizeUrl,
  )

/** IMP-003: the server reads the connected Trakt account in the background, then plans. */
export const startTraktImport = createServerFn({ method: 'POST' }).handler(
  async (): Promise<ImportJob> =>
    check(
      await api(sessionToken()).POST('/v1/imports/trakt'),
      'That Trakt import could not be started.',
    ),
)

/** Revokes Aaru on Trakt (freeing one of the user's app slots) and forgets the tokens. */
export const disconnectTrakt = createServerFn({ method: 'POST' }).handler(
  async () => {
    const result = await api(sessionToken()).DELETE(
      '/v1/imports/trakt/connection',
    )
    if (result.response.status === 401) sessionRejected()
    if (!result.response.ok) {
      throw new Error(
        errorMessage(result.error, 'Trakt was not disconnected. Try again.'),
      )
    }
  },
)

export type StremioLink = components['schemas']['StremioLink']
export type StremioPoll =
  { state: 'pending' } | { state: 'imported'; job: ImportJob }

/** IMP-016: a link code the user approves on stremio.com. No Stremio password reaches Aaru. */
export const startStremioImport = createServerFn({ method: 'POST' }).handler(
  async (): Promise<StremioLink> =>
    check(
      await api(sessionToken()).POST('/v1/imports/stremio/link'),
      'Stremio could not be reached. Try again in a minute.',
    ),
)

/** Pending until the code is approved; then the server reads the library once and queues it. */
export const pollStremioImport = createServerFn({ method: 'POST' })
  .validator(z.object({ code: z.string().min(1).max(64) }))
  .handler(async ({ data }): Promise<StremioPoll> => {
    const result = await api(sessionToken()).POST(
      '/v1/imports/stremio/link/{code}',
      { params: { path: { code: data.code } } },
    )
    if (result.response.status === 204) return { state: 'pending' }
    return {
      state: 'imported',
      job: check(result, 'Your Stremio history could not be imported.'),
    }
  })

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
