import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'

// Airing alerts on the web: the account's "New episodes" switch (shared with the Apple apps) and
// this browser's push subscription, over `/v1/me/notifications` and `/v1/web-push/*`.

function check<T>(
  result: { data?: T; error?: unknown; response: Response },
  fallback: string,
): T {
  if (result.response.status === 401) sessionRejected()
  if (result.data === undefined)
    throw new Error(errorMessage(result.error, fallback))
  return result.data
}

export type PushSetup = {
  airing: boolean
  /** The VAPID key browsers subscribe with; null when the server has no web push. */
  publicKey: string | null
}

export const getPushSetup = createServerFn({ method: 'GET' }).handler(
  async (): Promise<PushSetup> => {
    const client = api(sessionToken())
    const [settings, key] = await Promise.all([
      client.GET('/v1/me/notifications'),
      client.GET('/v1/web-push/key'),
    ])
    const airing = check(
      settings,
      'Your notification settings could not be loaded.',
    ).airing
    if (key.response.status === 401) sessionRejected()
    return { airing, publicKey: key.data?.publicKey ?? null }
  },
)

export const setAiring = createServerFn({ method: 'POST' })
  .validator(z.object({ airing: z.boolean() }))
  .handler(
    async ({ data }): Promise<boolean> =>
      check(
        await api(sessionToken()).PUT('/v1/me/notifications', {
          body: { airing: data.airing },
        }),
        'That was not saved.',
      ).airing,
  )

const subscription = z.object({
  endpoint: z.string().url().max(2048),
  keys: z.object({ p256dh: z.string().max(200), auth: z.string().max(200) }),
})

export const saveSubscription = createServerFn({ method: 'POST' })
  .validator(subscription)
  .handler(async ({ data }) => {
    const result = await api(sessionToken()).PUT('/v1/web-push/subscriptions', {
      body: data,
    })
    if (result.response.status === 401) sessionRejected()
    if (!result.response.ok)
      throw new Error(
        errorMessage(result.error, 'This browser could not be signed up.'),
      )
  })

export const deleteSubscription = createServerFn({ method: 'POST' })
  .validator(z.object({ endpoint: z.string().url().max(2048) }))
  .handler(async ({ data }) => {
    const result = await api(sessionToken()).DELETE(
      '/v1/web-push/subscriptions',
      { params: { query: { endpoint: data.endpoint } } },
    )
    if (result.response.status === 401) sessionRejected()
  })
