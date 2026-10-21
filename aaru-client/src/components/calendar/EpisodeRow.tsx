import { Show } from 'solid-js'
import { badge, metaLine, shortCode } from '../../lib/calendar/model'
import type { CalendarEntry } from '../../lib/calendar/model'
import { Poster } from '../Poster'
import { Badge } from '../ui/badge'
import { WatchButton } from './WatchButton'

/** One episode as a row: poster, show, code and name, network and time, and the tick. The row
 *  opens the episode sheet; the tick works on its own. Agenda, phone day list, day sheet and
 *  Missed all use it. */
export function EpisodeRow(props: {
  entry: CalendarEntry
  pending?: boolean
  /** Hide the time, e.g. in Missed where the date is shown instead. */
  when?: string
  onOpen: (entry: CalendarEntry) => void
  onToggle: (entry: CalendarEntry) => void
}) {
  const e = () => props.entry
  const label = () => badge(e())
  const meta = () => props.when ?? metaLine(e())
  return (
    <li class="flex items-center gap-1">
      <button
        type="button"
        class="flex min-w-0 flex-1 items-center gap-3 rounded-field py-2 pr-1 text-left transition-colors hover:bg-ink/5"
        classList={{ 'opacity-55': e().watched }}
        onClick={() => props.onOpen(e())}
      >
        <Poster
          url={e().title.posterUrl}
          kind={e().title.isAnime ? 'anime' : 'show'}
          radius="thumb"
          class="w-11 shrink-0"
        />
        <span class="min-w-0 flex-1">
          <span class="flex items-center gap-2">
            <span class="truncate font-semibold">{e().title.title}</span>
            <Show when={label()}>
              {(text) => (
                <Badge
                  size="xs"
                  tone={e().kind === 'finale' ? 'ink' : 'accent'}
                  class="shrink-0"
                >
                  {text()}
                </Badge>
              )}
            </Show>
          </span>
          <span class="block truncate text-sm">
            <span class="tabular-nums">
              {shortCode(e().season, e().number)}
            </span>
            <Show when={e().episodeName}> · {e().episodeName}</Show>
          </span>
          <Show when={meta()}>
            <span class="block truncate text-xs text-muted">{meta()}</span>
          </Show>
        </span>
      </button>
      <WatchButton
        entry={e()}
        pending={props.pending}
        onToggle={props.onToggle}
      />
    </li>
  )
}
