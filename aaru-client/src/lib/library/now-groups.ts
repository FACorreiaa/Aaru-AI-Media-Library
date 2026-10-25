import type { MediaKind } from './model'

// APP-018: the Now groups by name, apart from the rest of `now.ts` so a route's options (which ship
// in the entry chunk every page loads) can check a group without the labels and models.

export type NowGroup = 'watching' | 'reading' | 'listening'

export const NOW_GROUPS = ['watching', 'reading', 'listening'] as const

export function isNowGroup(value: string): value is NowGroup {
  return (NOW_GROUPS as readonly string[]).includes(value)
}

export function groupTitle(group: NowGroup): string {
  return TITLES[group]
}

const TITLES: Record<NowGroup, string> = {
  watching: 'Watching',
  reading: 'Reading',
  listening: 'Listening',
}

/** The kinds a group holds, so a kind chip narrows Now to its own group. */
export const GROUP_KINDS: Record<NowGroup, MediaKind[]> = {
  watching: ['film', 'show', 'anime'],
  reading: ['book', 'manga'],
  listening: ['album'],
}
