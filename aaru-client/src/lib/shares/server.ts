import { createServerFn } from '@tanstack/solid-start'
import { getCookie } from '@tanstack/solid-start/server'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { MEDIA_TYPES } from '../media'
import { SESSION_COOKIE } from '../session/cookie'
import { sessionRejected, sessionToken } from '../session/guard'
import {
  DEFAULT_DESCRIPTION,
  shareDescription,
  shareImage,
  shareName,
} from './model'
import type { ShareLink, SharePreview } from './model'

// SHR-002 on the web, over `/v1/shares`: the public page's load, and making a link.

/**
 * A share link's page: what it shows (null for an unknown code), whether anyone is signed in,
 * and its link preview. The preview's lines are made here, on the server, so the helpers they
 * need never ride in the bundle every page loads.
 */
export type SharePage = {
  preview: SharePreview | null
  signedIn: boolean
  head: { title: string; description: string; image: string }
}

function headOf(preview: SharePreview | null): SharePage['head'] {
  if (!preview)
    return {
      title: 'Aaru',
      description: DEFAULT_DESCRIPTION,
      image: shareImage({ kind: 'title', unavailable: true }),
    }
  return {
    title: shareName(preview) ?? 'Shared on Aaru',
    description: shareDescription(preview),
    image: shareImage(preview),
  }
}

export const loadShare = createServerFn({ method: 'GET' })
  .validator(z.object({ code: z.string().min(1).max(32) }))
  .handler(async ({ data }): Promise<SharePage> => {
    const token = getCookie(SESSION_COOKIE)
    const client = api(token)
    const [preview, me] = await Promise.all([
      client.GET('/v1/shares/{code}', {
        params: { path: { code: data.code } },
      }),
      // A stale cookie only means signed out here, never an error on a public page.
      token ? client.GET('/v1/me').catch(() => null) : Promise.resolve(null),
    ])
    if (preview.response.status !== 404 && preview.data === undefined)
      throw new Error(
        errorMessage(preview.error, 'This link could not be opened.'),
      )
    const shown = preview.data ?? null
    return { preview: shown, signedIn: !!me?.data, head: headOf(shown) }
  })

const mediaRef = z.object({
  titleId: z.string().uuid().optional(),
  type: z.enum(MEDIA_TYPES),
  ids: z.record(z.string(), z.string()).optional(),
  title: z.string().optional(),
  year: z.number().int().optional(),
})

export const createShare = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      target: z.object({
        kind: z.enum(['title', 'sport_event', 'concert']),
        ref: mediaRef.optional(),
        id: z.string().min(1).max(64).optional(),
      }),
      // The server holds the real limit (140 characters); this only bounds the request.
      note: z.string().max(560).optional(),
    }),
  )
  .handler(async ({ data }): Promise<ShareLink> => {
    const result = await api(sessionToken()).POST('/v1/shares', {
      body: { target: data.target, note: data.note?.trim() || undefined },
    })
    if (result.response.status === 401) sessionRejected()
    if (!result.data)
      throw new Error(errorMessage(result.error, 'The link was not made.'))
    return result.data
  })
