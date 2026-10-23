import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { components } from '../api/schema'

// AG-006 on the web: one capture, as text, a link or a picture. The page then follows it as an
// import. Past the free month's captures the server answers 402; that is an answer, not a fault.

type ImportJob = components['schemas']['ImportJob']

export type CaptureResult = { job: ImportJob } | { quota: string }

const IMAGE_TYPES = [
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
] as const
/** 5 MB of image, as base64. */
const MAX_BASE64 = Math.ceil((5 * 1024 * 1024 * 4) / 3) + 4

export const startCapture = createServerFn({ method: 'POST' })
  .validator(
    z.union([
      z.object({ text: z.string().trim().min(1).max(20000) }),
      z.object({ url: z.string().trim().url().max(2048) }),
      z.object({
        image: z
          .string()
          .min(1)
          .max(MAX_BASE64, 'That image is larger than 5 MB.'),
        mediaType: z.enum(IMAGE_TYPES),
      }),
    ]),
  )
  .handler(async ({ data }): Promise<CaptureResult> => {
    const client = api(sessionToken())
    const result =
      'image' in data
        ? await client.POST('/v1/imports/capture', {
            body: Uint8Array.from(atob(data.image), (c) =>
              c.charCodeAt(0),
            ) as never,
            bodySerializer: (body: unknown) => body as Uint8Array,
            headers: { 'Content-Type': data.mediaType },
          })
        : await client.POST('/v1/imports/capture', { body: data })
    if (result.response.status === 401) sessionRejected()
    if (result.response.status === 402)
      return {
        quota: errorMessage(result.error, 'This month’s captures are used.'),
      }
    if (!result.data)
      throw new Error(
        errorMessage(result.error, 'Aaru could not take that capture.'),
      )
    return { job: result.data }
  })
