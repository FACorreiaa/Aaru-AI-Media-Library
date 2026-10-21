import { episodeCode } from '../../lib/calendar/model'
import type { CalendarEntry } from '../../lib/calendar/model'
import { cn } from '../../lib/cn'
import { pop } from '../../lib/motion'

/** The calendar's tick: a 44px round toggle, filled once watched. The page owns the state and
 *  the optimistic write; a pending write disables it so a double tap never sends two. */
export function WatchButton(props: {
  entry: CalendarEntry
  pending?: boolean
  onToggle: (entry: CalendarEntry) => void
  class?: string
}) {
  const label = () =>
    `${props.entry.title.title} ${episodeCode(props.entry.season, props.entry.number)} watched`
  return (
    <button
      type="button"
      aria-pressed={props.entry.watched}
      aria-label={label()}
      disabled={props.pending}
      class={cn(
        'grid size-11 shrink-0 place-items-center rounded-full disabled:opacity-50',
        props.class,
      )}
      onClick={(event) => {
        event.stopPropagation()
        // A tick pops once; clearing one does not.
        const ring = event.currentTarget.firstElementChild
        if (!props.entry.watched && ring) void pop(ring)
        props.onToggle(props.entry)
      }}
    >
      <span
        class="grid size-7 place-items-center rounded-full border-2 transition-colors"
        classList={{
          'border-accent bg-accent text-on-accent': props.entry.watched,
          'border-ink/30 text-transparent hover:border-accent':
            !props.entry.watched,
        }}
        aria-hidden="true"
      >
        <svg viewBox="0 0 16 16" class="size-4" fill="none">
          <path
            d="M3.5 8.5l3 3 6-7"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
      </span>
    </button>
  )
}
