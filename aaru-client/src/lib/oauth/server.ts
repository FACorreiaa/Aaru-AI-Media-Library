import { createServerFn } from '@tanstack/solid-start'
import { getCookie } from '@tanstack/solid-start/server'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { components } from '../api/schema'
import { BINDING_COOKIE } from './model'

// OUT-004 on the web: the consent page for Claude's custom connector (and any OAuth MCP
// client). The Worker only forwards: the session, and the binding cookie the API set when
// the app started, which proves this browser asked.

export type OAuthConsentRequest = components['schemas']['OAuthConsentRequest']

export const getOAuthRequest = createServerFn({ method: 'GET' })
  .validator(z.object({ id: z.string().uuid() }))
  .handler(async ({ data }): Promise<OAuthConsentRequest> => {
    const result = await api(sessionToken()).GET('/v1/oauth/requests/{id}', {
      params: { path: { id: data.id } },
    })
    if (result.response.status === 401) sessionRejected()
    if (!result.data)
      throw new Error(
        errorMessage(result.error, 'This connection request expired.'),
      )
    return result.data
  })

/**
 * The user's answer, once: the server spends the request, and the cookie lapses in ten minutes.
 * Returns where the browser goes next: back to the app that asked.
 */
export const answerOAuthRequest = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      id: z.string().uuid(),
      approve: z.boolean(),
      name: z.string().max(80).optional(),
      allowLibraryWrites: z.boolean().optional(),
    }),
  )
  .handler(async ({ data }): Promise<string> => {
    const binding = getCookie(BINDING_COOKIE)
    if (!binding)
      throw new Error(
        'Open this from the app you are connecting, in this browser.',
      )
    const client = api(sessionToken())
    const params = { path: { id: data.id } }
    const result = data.approve
      ? await client.POST('/v1/oauth/requests/{id}/approve', {
          params,
          body: {
            binding,
            name: data.name?.trim() || undefined,
            allowLibraryWrites: data.allowLibraryWrites ?? false,
          },
        })
      : await client.POST('/v1/oauth/requests/{id}/deny', {
          params,
          body: { binding },
        })
    if (result.response.status === 401) sessionRejected()
    if (!result.data)
      throw new Error(
        errorMessage(result.error, 'Your answer could not be sent.'),
      )
    return result.data.redirectTo
  })
