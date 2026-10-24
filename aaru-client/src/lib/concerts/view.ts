// Discover's `?view=` (DISC-002, DISC-003, MUS-003). Its own module because route options are not
// code-split: whatever `validateSearch` imports ships on every page.

export const DISCOVER_VIEWS = [
  'today',
  'on-air',
  'seasons',
  'concerts',
] as const
export type DiscoverView = (typeof DISCOVER_VIEWS)[number]

/** `?view=` as Discover reads it: one of its views, else absent (Today). */
export function parseView(value: unknown): DiscoverView | undefined {
  return DISCOVER_VIEWS.includes(value as DiscoverView)
    ? (value as DiscoverView)
    : undefined
}

/** The view to draw. Concerts falls back to Today where the server has them off. */
export function shownView(
  view: DiscoverView | undefined,
  concertsAvailable: boolean,
): DiscoverView {
  if (view === 'concerts' && !concertsAvailable) return 'today'
  return view ?? 'today'
}
