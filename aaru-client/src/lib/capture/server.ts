import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import { MAX_CAPTURE_PICTURES } from './model'
import type { components } from '../api/schema'

// AG-006 on the web: one capture, as text, a link or up to five pictures. The page then follows
// it as an import. The Books page reads books only (BOOK-001).

type ImportJob = components['schemas']['ImportJob']

export type CaptureResult = { job: ImportJob }

const IMAGE_TYPES = [
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
] as const
/** 5 MB of image, as base64. */
const MAX_BASE64 = Math.ceil((5 * 1024 * 1024 * 4) / 3) + 4

const kind = { kind: z.literal('book').optional() }

const bytesOf = (base64: string) =>
  Uint8Array.from(atob(base64), (c) => c.charCodeAt(0))

export const startCapture = createServerFn({ method: 'POST' })
  .validator(
    z.union([
      z.object({ text: z.string().trim().min(1).max(100000), ...kind }),
      z.object({ url: z.string().trim().url().max(2048), ...kind }),
      z.object({
        images: z
          .array(
            z.object({
              image: z
                .string()
                .min(1)
                .max(MAX_BASE64, 'That image is larger than 5 MB.'),
              mediaType: z.enum(IMAGE_TYPES),
            }),
          )
          .min(1)
          .max(MAX_CAPTURE_PICTURES),
        ...kind,
      }),
    ]),
  )
  .handler(async ({ data }): Promise<CaptureResult> => {
    const client = api(sessionToken())
    const params = { query: { kind: data.kind } }
    let result
    if (!('images' in data)) {
      const { kind: _kind, ...body } = data
      result = await client.POST('/v1/imports/capture', { params, body })
    } else if (data.images.length === 1) {
      const [only] = data.images
      result = await client.POST('/v1/imports/capture', {
        params,
        body: bytesOf(only.image) as never,
        bodySerializer: (body: unknown) => body as Uint8Array,
        headers: { 'Content-Type': only.mediaType },
      })
    } else {
      const form = new FormData()
      for (const { image, mediaType } of data.images)
        form.append(
          'image',
          new Blob([bytesOf(image)], { type: mediaType }),
          'capture.jpg',
        )
      result = await client.POST('/v1/imports/capture', {
        params,
        body: form as never,
        bodySerializer: (body: unknown) => body as FormData,
      })
    }
    if (result.response.status === 401) sessionRejected()
    if (!result.data)
      throw new Error(
        errorMessage(result.error, 'Aaru could not take that capture.'),
      )
    return { job: result.data }
  })
