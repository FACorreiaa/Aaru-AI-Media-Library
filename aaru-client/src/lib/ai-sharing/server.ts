import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { AiSharingState } from './model'

/** Stores the user's answer to AI sharing (PRV-002); the latest one holds. */
export const setAiSharing = createServerFn({ method: 'POST' })
  .validator(z.object({ allowed: z.boolean() }))
  .handler(async ({ data }): Promise<AiSharingState> => {
    const {
      data: answer,
      error,
      response,
    } = await api(sessionToken()).PUT('/v1/me/ai-sharing', {
      body: { allowed: data.allowed },
    })
    if (response.status === 401) sessionRejected()
    if (!answer)
      throw new Error(errorMessage(error, 'Your answer was not saved.'))
    return answer.state
  })
