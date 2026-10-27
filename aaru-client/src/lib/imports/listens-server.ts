import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import { check } from './server'
import type { ImportJob } from './server'

// MUS-004 on the web: listening history imports, over the same `/v1` routes as the Apple apps.
// Apart from `server.ts` so only the import pages carry them.

const MAX_LISTEN_BYTES = 24 * 1024 * 1024
const id = z.string().uuid()

/** MUS-004: a Spotify or YouTube listening history file, sent to the server as its bytes. */
export const uploadListenHistory = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      source: z.enum(['spotify', 'youtube']),
      filename: z.string().max(255),
      text: z.string().max(MAX_LISTEN_BYTES, 'That file is larger than 24 MB.'),
    }),
  )
  .handler(async ({ data }): Promise<ImportJob> =>
    check(
      await api(sessionToken()).POST('/v1/imports/csv', {
        params: { query: { source: data.source, filename: data.filename } },
        body: data.text as never,
        bodySerializer: (body: unknown) => body as string,
        headers: { 'Content-Type': 'application/octet-stream' },
      }),
      'That file could not be imported.',
    ),
  )

/** MUS-004: a Last.fm or ListenBrainz account's listens, read by the server in the background. */
export const startListenAccountImport = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      service: z.enum(['lastfm', 'listenbrainz']),
      username: z.string().trim().min(1).max(64),
    }),
  )
  .handler(async ({ data }): Promise<ImportJob> => {
    const body = { username: data.username }
    const result =
      data.service === 'lastfm'
        ? await api(sessionToken()).POST('/v1/imports/lastfm', { body })
        : await api(sessionToken()).POST('/v1/imports/listenbrainz', { body })
    return check(result, 'That import could not be started.')
  })

/** MUS-004: undoes an applied listening import: its listens go, and so does the import. */
export const undoListenImport = createServerFn({ method: 'POST' })
  .validator(z.object({ id }))
  .handler(async ({ data }) => {
    const result = await api(sessionToken()).POST('/v1/imports/{id}/undo', {
      params: { path: { id: data.id } },
    })
    if (result.response.status === 401) sessionRejected()
    if (!result.response.ok) {
      throw new Error(errorMessage(result.error, 'The import was not undone.'))
    }
  })
