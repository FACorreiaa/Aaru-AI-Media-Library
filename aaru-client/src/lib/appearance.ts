import { PAPER } from './tokens.gen'

// Light, dark, or the system's choice. Kept on this device in a plain cookie (not the account:
// the Apple apps keep theirs per device too), so the Worker renders `<html data-theme>` on the
// first byte and the page never flashes the wrong paper.

export type Appearance = 'system' | 'light' | 'dark'

export const APPEARANCE_COOKIE = 'aaru_appearance'

const ONE_YEAR = 365 * 24 * 60 * 60

export const APPEARANCES: ReadonlyArray<{ value: Appearance; label: string }> =
  [
    { value: 'system', label: 'System' },
    { value: 'light', label: 'Light' },
    { value: 'dark', label: 'Dark' },
  ]

/** Anything but a pinned scheme follows the system. */
export function parseAppearance(value: string | null | undefined): Appearance {
  return value === 'light' || value === 'dark' ? value : 'system'
}

/** The cookie's value out of a `document.cookie` string. */
export function appearanceFromCookieHeader(header: string): Appearance {
  for (const part of header.split(';')) {
    const [name, ...rest] = part.trim().split('=')
    if (name === APPEARANCE_COOKIE) return parseAppearance(rest.join('='))
  }
  return 'system'
}

/** A `document.cookie` assignment. "System" clears the cookie rather than storing it. */
export function appearanceCookie(appearance: Appearance): string {
  const base = `${APPEARANCE_COOKIE}=${appearance === 'system' ? '' : appearance}; Path=/; SameSite=Lax`
  return appearance === 'system'
    ? `${base}; Max-Age=0`
    : `${base}; Max-Age=${ONE_YEAR}`
}

/** `<meta name="theme-color">` tags: one pinned colour, or one per system scheme. */
export function themeColorMeta(
  appearance: Appearance,
): Array<{ name: string; content: string; media?: string }> {
  if (appearance !== 'system') {
    return [{ name: 'theme-color', content: PAPER[appearance] }]
  }
  return [
    {
      name: 'theme-color',
      content: PAPER.light,
      media: '(prefers-color-scheme: light)',
    },
    {
      name: 'theme-color',
      content: PAPER.dark,
      media: '(prefers-color-scheme: dark)',
    },
  ]
}

/** The scheme the page is drawn in right now. "light" on the server. */
export function resolvedScheme(): 'light' | 'dark' {
  if (typeof document === 'undefined') return 'light'
  const pinned = document.documentElement.dataset.theme
  if (pinned === 'light' || pinned === 'dark') return pinned
  return window.matchMedia('(prefers-color-scheme: dark)').matches
    ? 'dark'
    : 'light'
}

/** Pins (or unpins) the scheme on this device at once; the caller re-runs the root loader. */
export function applyAppearance(appearance: Appearance) {
  document.cookie = appearanceCookie(appearance)
  const root = document.documentElement
  if (appearance === 'system') delete root.dataset.theme
  else root.dataset.theme = appearance
}

// The Field's light follows the viewer's clock: the page tints a little warmer at dusk and
// cooler at night. Only the browser knows the local hour, so a few bytes of inline script set
// `<html data-daypart>` before the first paint; nothing changes after that.

export type Daypart = 'dawn' | 'day' | 'dusk' | 'night'

/** Start hours, in order through the day; night runs past midnight to dawn. */
const DAYPART_STARTS: ReadonlyArray<[Daypart, number]> = [
  ['dawn', 5],
  ['day', 8],
  ['dusk', 17],
  ['night', 21],
]

export function daypart(hour: number): Daypart {
  let part: Daypart = 'night'
  for (const [name, start] of DAYPART_STARTS) if (hour >= start) part = name
  return part
}

/** The same rule as `daypart`, as inline script for `<head>`. */
export const DAYPART_SCRIPT = `(function(){var h=new Date().getHours(),p='night';${DAYPART_STARTS.map(
  ([name, start]) => `if(h>=${start})p='${name}';`,
).join('')}document.documentElement.dataset.daypart=p})()`
