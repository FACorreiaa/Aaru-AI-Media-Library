import { episodeCode } from '../lib/calendar/model'
import type { CalendarEntry } from '../lib/calendar/model'
import { pop } from '../lib/motion'

/** The calendar's tick, in the week grid and the month agenda alike. The page owns the state
 * and the optimistic write; the box keeps showing that state until the write lands. */
export function WatchedCheckbox(props: {
  entry: CalendarEntry
  onToggle: (entry: CalendarEntry) => void
  class?: string
}) {
  return (
    <input
      type="checkbox"
      class={`h-4 w-4 shrink-0 accent-accent ${props.class ?? ''}`}
      checked={props.entry.watched}
      aria-label={`${props.entry.title.title} ${episodeCode(props.entry.season, props.entry.number)} watched`}
      onChange={(event) => {
        // A tick pops once; clearing one does not.
        if (!props.entry.watched) void pop(event.currentTarget)
        event.currentTarget.checked = props.entry.watched
        props.onToggle(props.entry)
      }}
    />
  )
}
