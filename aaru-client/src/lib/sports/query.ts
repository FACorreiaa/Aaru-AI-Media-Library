import { queryOptions } from '@tanstack/solid-query'
import { getSportSettings } from './settings'

// Whether Sports are on and the "Where to watch" country, under one cache key for the shell's
// nav, the Sports page and Settings. Apart from `queries.ts`, so the shell loads only this.
export const sportSettingsQuery = queryOptions({
  queryKey: ['sport-settings'],
  queryFn: () => getSportSettings(),
})
