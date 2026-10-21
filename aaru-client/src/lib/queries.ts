import { queryOptions } from '@tanstack/solid-query'
import { getCalendar } from './calendar/server'
import { getConcertPlace } from './concerts/server'
import { getDiscover, getUpNext } from './home/server'
import { listImports } from './imports/server'
import { getLibrary } from './library/server'
import { getLists } from './lists/server'
import { listPendingPlans } from './plans/server'
import { getStats } from './recap/server'

// The reads the app's pages share, each under one cache key. A page's loader and its rows ask
// through these, so Home and Library share one library and Home and Discover one set of rows.
// After any write the cache counts as old (`start.ts`), so the next visit asks again.

export const upNextQuery = queryOptions({
  queryKey: ['up-next'],
  queryFn: () => getUpNext(),
})

export const discoverQuery = queryOptions({
  queryKey: ['discover'],
  queryFn: () => getDiscover(),
})

export const concertPlaceQuery = queryOptions({
  queryKey: ['concert-place'],
  queryFn: () => getConcertPlace(),
})

export const libraryQuery = queryOptions({
  queryKey: ['library'],
  queryFn: () => getLibrary(),
})

export const listsQuery = queryOptions({
  queryKey: ['lists'],
  queryFn: () => getLists(),
})

export const pendingPlansQuery = queryOptions({
  queryKey: ['plans', 'pending'],
  queryFn: () => listPendingPlans(),
})

export const importsQuery = queryOptions({
  queryKey: ['imports'],
  queryFn: () => listImports(),
})

/** The last 7 days in numbers, in the viewer's time zone. */
export const lastWeekStatsQuery = (tz: string) =>
  queryOptions({
    queryKey: ['stats', 'last7', tz],
    queryFn: () => getStats({ data: { span: 'last7', tz } }),
  })

export const calendarQuery = (range: { from: string; to: string }) =>
  queryOptions({
    queryKey: ['calendar', range.from, range.to],
    queryFn: () => getCalendar({ data: range }),
  })
