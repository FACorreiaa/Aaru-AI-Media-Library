import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import type { components } from '../api/schema'
import { mediaRef } from '../groups/media-ref'
import { sessionRejected, sessionToken } from '../session/guard'
import { ONBOARDING_KINDS, PICKS_LIMIT, RELATED_LIMIT } from './model'
import type { OnboardingPicked } from './model'

// ONB-001 on the web: the first run's four calls, the same `/v1` routes the Apple apps use.

type DiscoverRow = components['schemas']['DiscoverRow']
type OnboardingRelated = components['schemas']['OnboardingRelated']

/** Rows of well-known titles of one kind: Popular, then by genre. Empty rows are left out. */
export const getOnboardingRows = createServerFn({ method: 'GET' })
  .validator(z.object({ kind: z.enum(ONBOARDING_KINDS) }))
  .handler(async ({ data }): Promise<DiscoverRow[]> => {
    const {
      data: rows,
      error,
      response,
    } = await api(sessionToken()).GET('/v1/onboarding/rows', {
      params: { query: { kind: data.kind } },
    })
    if (response.status === 401) sessionRejected()
    if (!rows)
      throw new Error(errorMessage(error, 'These titles could not be loaded.'))
    return rows.rows
  })

/** One screen's picks as one journaled action. */
export const addOnboardingPicks = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      items: z
        .array(
          z.object({
            mediaRef,
            status: z.enum([
              'wishlist',
              'in_progress',
              'on_hold',
              'finished',
              'dropped',
            ]),
          }),
        )
        .min(1)
        .max(PICKS_LIMIT),
    }),
  )
  .handler(async ({ data }): Promise<OnboardingPicked> => {
    const {
      data: picked,
      error,
      response,
    } = await api(sessionToken()).POST('/v1/onboarding/picks', {
      body: { items: data.items },
    })
    if (response.status === 401) sessionRejected()
    if (!picked)
      throw new Error(errorMessage(error, 'Your picks were not saved.'))
    return picked
  })

/** Sequels, prequels, spin-offs and adaptations of the saved picks, from the relation graph. */
export const getOnboardingRelated = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      titleIds: z.array(z.string().uuid()).min(1).max(RELATED_LIMIT),
    }),
  )
  .handler(async ({ data }): Promise<OnboardingRelated> => {
    const {
      data: related,
      error,
      response,
    } = await api(sessionToken()).POST('/v1/onboarding/related', {
      body: { titleIds: data.titleIds },
    })
    if (response.status === 401) sessionRejected()
    if (!related)
      throw new Error(
        errorMessage(error, 'Related titles could not be loaded.'),
      )
    return related
  })

/** Ends the first run, finished or skipped. The first call wins; what was saved stays. */
export const finishOnboarding = createServerFn({ method: 'POST' })
  .validator(z.object({ skipped: z.boolean() }))
  .handler(async ({ data }) => {
    const { error, response } = await api(sessionToken()).PUT(
      '/v1/me/onboarding',
      { body: { skipped: data.skipped } },
    )
    if (response.status === 401) sessionRejected()
    if (!response.ok)
      throw new Error(errorMessage(error, 'That did not go through.'))
  })
