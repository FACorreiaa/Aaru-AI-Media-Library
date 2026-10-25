import { queryOptions } from '@tanstack/solid-query'
import { PROGRESS_KEY } from './achievements/keys'
import { getBadges, getProgress } from './achievements/server'
import { getCalendar } from './calendar/server'
import { getConcertPlace } from './concerts/server'
import { getDiscover, getUpNext } from './home/server'
import { listImports } from './imports/server'
import { getLibrary, getWatching } from './library/server'
import { getList, getLists } from './lists/server'
import { listPendingPlans } from './plans/server'
import { getProfileStats } from './profile/server'
import { getStats } from './recap/server'
import { getTitlePage, resolveTitle } from './title/server'
import type { PreviewParams } from './title/preview'

// The reads the app's pages share, each under one cache key. A page's loader and its rows ask
// through these, so Home and Library share one library and Home and Discover one set of rows.
// After any write the cache counts as old (`start.ts`), so the next visit asks again.
// Live pages (an import's progress, a group's channels, Settings' connections) stay out: they
// change without a write from this tab.

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

export const watchingQuery = queryOptions({
  queryKey: ['watching'],
  queryFn: () => getWatching(),
})

export const titlePageQuery = (id: string) =>
  queryOptions({
    queryKey: ['title', id],
    queryFn: () => getTitlePage({ data: { id } }),
  })

export const titlePreviewQuery = (params: PreviewParams) =>
  queryOptions({
    queryKey: ['title-preview', params.type, params.provider, params.ref],
    queryFn: () => resolveTitle({ data: params }),
  })

export const listsQuery = queryOptions({
  queryKey: ['lists'],
  queryFn: () => getLists(),
})

export const listQuery = (id: string) =>
  queryOptions({
    queryKey: ['lists', id],
    queryFn: () => getList({ data: { id } }),
  })

export const pendingPlansQuery = queryOptions({
  queryKey: ['plans', 'pending'],
  queryFn: () => listPendingPlans(),
})

export const importsQuery = queryOptions({
  queryKey: ['imports'],
  queryFn: () => listImports(),
})

type StatsAsk = Parameters<typeof getStats>[0]['data']

/** `/v1/me/stats` for one period, in the viewer's time zone. */
export const myStatsQuery = (ask: StatsAsk) =>
  queryOptions({
    queryKey: ['stats', ask.span, ask.year, ask.month, ask.tz],
    queryFn: () => getStats({ data: ask }),
  })

/** GAM-001…004: level, streak and unseen badges. `UnlockWatcher` refetches it after a write. */
export const progressQuery = queryOptions({
  queryKey: PROGRESS_KEY,
  queryFn: () => getProgress(),
})

export const badgesQuery = queryOptions({
  queryKey: ['badges'],
  queryFn: () => getBadges(),
})

/** `/v1/me/profile/stats`: all time, no period, so one key. */
export const profileStatsQuery = queryOptions({
  queryKey: ['profile-stats'],
  queryFn: () => getProfileStats(),
})

export const calendarQuery = (range: { from: string; to: string }) =>
  queryOptions({
    queryKey: ['calendar', range.from, range.to],
    queryFn: () => getCalendar({ data: range }),
  })
