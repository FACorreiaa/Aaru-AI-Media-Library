// Discover's `?view=` (DISC-002, DISC-003). Its own module because route options are not
// code-split: whatever `validateSearch` imports ships on every page.
// NAV-001 (2026-10-25): Concerts (MUS-003) moved to the Music page, and an old
// `?view=concerts` link is sent there.

export const DISCOVER_VIEWS = ['today', 'on-air', 'seasons'] as const
export type DiscoverView = (typeof DISCOVER_VIEWS)[number]

/** `?view=` as Discover reads it: one of its views, else absent (Today). */
export function parseView(value: unknown): DiscoverView | undefined {
  return DISCOVER_VIEWS.includes(value as DiscoverView)
    ? (value as DiscoverView)
    : undefined
}

/** Whether a Discover `?view=` is the retired Concerts view, which now lives on Music. */
export function isRetiredConcertsView(value: unknown): boolean {
  return value === 'concerts'
}
