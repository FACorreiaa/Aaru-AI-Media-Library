// The shell's destinations (DESIGN.md §18, NAV-001): the pure part, with no icons, so which row
// is active and when More opens can be tested without a DOM.

export type NavPath =
  | '/app'
  | '/app/discover'
  | '/app/library'
  | '/app/calendar'
  | '/app/lists'
  | '/app/friends'
  | '/app/groups'
  | '/app/books'
  | '/app/manga'
  | '/app/music'
  | '/app/sports'
  | '/app/insights'
  | '/app/settings'

export type NavTarget = {
  to: NavPath
  label: string
  /** Other paths that belong to this destination. */
  also?: string[]
}

/** The six top rows, always shown. */
export const TOP: NavTarget[] = [
  { to: '/app', label: 'Home', also: ['/app/plans'] },
  { to: '/app/discover', label: 'Discover' },
  { to: '/app/library', label: 'Library', also: ['/app/title'] },
  { to: '/app/calendar', label: 'Calendar' },
  { to: '/app/lists', label: 'Lists' },
  // SOC-003 (owner, 2026-10-21): Friends is its own page, between Lists and Groups.
  { to: '/app/friends', label: 'Friends' },
]

// SPT-003 (owner, 2026-10-24): Sports is its own destination, listed only while the server has
// a sports provider (`/v1/me/sport-settings` says `available`).
const SPORTS: NavTarget = { to: '/app/sports', label: 'Sports' }

/** NAV-001 (owner, 2026-10-25): the collapsible More group, in this order. */
export const MORE: NavTarget[] = [
  { to: '/app/groups', label: 'Groups' },
  { to: '/app/books', label: 'Books' },
  { to: '/app/manga', label: 'Manga' },
  { to: '/app/music', label: 'Music' },
  SPORTS,
]

/** Set apart at the bottom. Music is its own row in More, so Insights no longer claims it. */
export const BOTTOM: NavTarget[] = [
  { to: '/app/insights', label: 'Insights', also: ['/app/recap'] },
  { to: '/app/settings', label: 'Settings', also: ['/app/imports'] },
]

/** More's rows: Sports only while the server has it on. */
export function moreRows(sportsOn: boolean): NavTarget[] {
  return sportsOn ? MORE : MORE.filter((d) => d !== SPORTS)
}

export function isAt(path: string, d: Pick<NavTarget, 'to' | 'also'>): boolean {
  const under = (base: string) => path === base || path.startsWith(`${base}/`)
  if (d.to === '/app')
    return path === '/app' || path === '/app/' || (d.also ?? []).some(under)
  return under(d.to) || (d.also ?? []).some(under)
}

/** Whether the page is one of More's rows: the group is then open whatever was remembered. */
export function inMore(path: string): boolean {
  return MORE.some((d) => isAt(path, d))
}

const MORE_KEY = 'nav.more.open'

/** The group's last open state. Closed when storage refuses (a private window) or is empty. */
export function readMoreOpen(): boolean {
  try {
    return localStorage.getItem(MORE_KEY) === 'true'
  } catch {
    return false
  }
}

export function writeMoreOpen(open: boolean): void {
  try {
    localStorage.setItem(MORE_KEY, String(open))
  } catch {
    // Storage refused: the group just does not remember.
  }
}
