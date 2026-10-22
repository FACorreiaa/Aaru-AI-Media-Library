import { Show } from 'solid-js'
import { cn } from '~/lib/utils'
import type { BadgeFamily } from '../../lib/achievements/model'

// A badge as a round mark with its family's glyph (DESIGN.md §17 "Medallions"). The ring is
// the tier: Stone, then Ink, then a gold hairline, then a double gold hairline. Gold is edge
// light and never fills. Unearned is Stone at reduced contrast; a hidden one shows "?".

const SIZES = {
  sm: 'size-10 [&_svg]:size-5 text-base',
  md: 'size-16 [&_svg]:size-7 text-2xl',
  lg: 'size-28 [&_svg]:size-12 text-4xl',
} as const

const RINGS = [
  'bg-stone/50 text-muted ring-1 ring-line',
  'bg-medallion text-ink ring-2 ring-stone',
  'bg-medallion text-ink ring-2 ring-ink',
  'bg-medallion text-ink ring-1 ring-gold',
  'bg-medallion text-ink ring-1 ring-gold outline-1 outline-offset-2 outline-gold',
] as const

export function BadgeMedallion(props: {
  family: BadgeFamily
  /** 0 for not earned. */
  tier: number
  /** Hidden and not earned: a blank mark with "?". */
  secret?: boolean
  size?: keyof typeof SIZES
  class?: string
}) {
  return (
    <span
      aria-hidden="true"
      class={cn(
        'grid shrink-0 place-items-center rounded-full font-display',
        SIZES[props.size ?? 'md'],
        RINGS[Math.min(Math.max(props.tier, 0), RINGS.length - 1)],
        props.class,
      )}
    >
      <Show when={!props.secret} fallback="?">
        <FamilyGlyph family={props.family} />
      </Show>
    </span>
  )
}

const GLYPHS: Record<BadgeFamily, string> = {
  films: 'M4 5h16v14H4zM8 5v14M16 5v14M4 9.5h4M4 14.5h4M16 9.5h4M16 14.5h4',
  shows: 'M4 7h16v11H4zM9 3l3 4 3-4M9 21h6',
  anime: 'M12 3l2 6.2L20 12l-6 2.8L12 21l-2-6.2L4 12l6-2.8zM19 3v3M17.5 4.5h3',
  books:
    'M4 5h5a3 3 0 0 1 3 3v11a2.5 2.5 0 0 0-2.5-2.5H4zM20 5h-5a3 3 0 0 0-3 3v11a2.5 2.5 0 0 1 2.5-2.5H20z',
  music:
    'M9 17V6l10-2v11M9 17a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0zM19 15a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0z',
  ratings:
    'M12 4l2.4 4.9 5.4.8-3.9 3.8.9 5.4L12 16.4l-4.8 2.5.9-5.4-3.9-3.8 5.4-.8z',
  lists: 'M9 6h11M9 12h11M9 18h11M4.5 6h.01M4.5 12h.01M4.5 18h.01',
  imports: 'M12 4v11M7.5 10.5L12 15l4.5-4.5M4 19h16',
  discovery: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM15.5 8.5l-2 5-5 2 2-5z',
  streaks:
    'M12 21a6 6 0 0 0 6-6c0-4-3-6-4-10-2 2-3 4-3 6-1-1-1.5-2-1.5-3C7 10 6 12.5 6 15a6 6 0 0 0 6 6z',
  social:
    'M9 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM3.5 19a5.5 5.5 0 0 1 11 0M16 5.2a3 3 0 0 1 0 5.6M20.5 19a5.5 5.5 0 0 0-3.5-5.1',
}

export function FamilyGlyph(props: { family: BadgeFamily; class?: string }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.6"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={props.class}
    >
      <path d={GLYPHS[props.family]} />
    </svg>
  )
}
