import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { CalendarEntry } from './model'

// APP-010 on the web: the airing episodes of the caller's shows, as `/v1/calendar` returns
// them (UTC). Grouping into days happens in the browser, which knows the viewer's timezone.

export const getCalendar = createServerFn({ method: 'GET' })
  .validator(
    z.object({ from: z.string().datetime(), to: z.string().datetime() }),
  )
  .handler(async ({ data }): Promise<CalendarEntry[]> => {
    const {
      data: calendar,
      error,
      response,
    } = await api(sessionToken()).GET('/v1/calendar', {
      params: { query: { from: data.from, to: data.to } },
    })
    if (response.status === 401) sessionRejected()
    if (!calendar)
      throw new Error(errorMessage(error, 'The week could not be loaded.'))
    return calendar.items
  })
