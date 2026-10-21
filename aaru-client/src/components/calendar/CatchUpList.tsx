import { For, Show } from 'solid-js'
import { agendaDayLabel, entryDay } from '../../lib/calendar/model'
import type { CalendarEntry } from '../../lib/calendar/model'
import { missedLine } from '../../lib/calendar/filters'
import type { MissedShow } from '../../lib/calendar/filters'
import { cn } from '../../lib/cn'
import { Poster } from '../Poster'
import { cardClass } from '../ui/card'
import { EpisodeRow } from './EpisodeRow'

/** Missed (CAL-002): what aired in the last four weeks and is not watched, one card per show,
 *  oldest miss first, so catching up starts where it should. */
export default function CatchUpList(props: {
  shows: MissedShow[]
  pending: Set<string>
  keyOf: (entry: CalendarEntry) => string
  onOpen: (entry: CalendarEntry) => void
  onToggle: (entry: CalendarEntry) => void
}) {
  return (
    <div class="grid gap-4 md:grid-cols-2 2xl:grid-cols-3">
      <For
        each={props.shows}
        fallback={
          <div class={cn(cardClass, 'p-6 md:col-span-2 2xl:col-span-3')}>
            <p class="font-display text-xl">You are all caught up.</p>
            <p class="mt-1 text-sm text-muted">
              Nothing from your shows aired in the last four weeks without a
              tick.
            </p>
          </div>
        }
      >
        {(show) => (
          <section
            class={cn(cardClass, 'flex flex-col p-4')}
            aria-label={show.title.title}
          >
            <header class="flex items-center gap-3">
              <Poster
                url={show.title.posterUrl}
                kind={show.title.isAnime ? 'anime' : 'show'}
                class="w-14 shrink-0"
              />
              <div class="min-w-0">
                <h2 class="truncate font-display text-xl font-medium">
                  {show.title.title}
                </h2>
                <p class="text-sm text-muted">{missedLine(show)}</p>
                <Show when={show.title.network}>
                  <p class="text-xs text-muted">{show.title.network}</p>
                </Show>
              </div>
            </header>
            <ul class="mt-3 divide-y divide-line">
              <For each={show.episodes}>
                {(entry) => (
                  <EpisodeRow
                    entry={entry}
                    when={`Aired ${agendaDayLabel(entryDay(entry))}`}
                    pending={props.pending.has(props.keyOf(entry))}
                    onOpen={props.onOpen}
                    onToggle={props.onToggle}
                  />
                )}
              </For>
            </ul>
          </section>
        )}
      </For>
    </div>
  )
}
