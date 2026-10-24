import { For, Show } from 'solid-js'
import type { JSX } from 'solid-js'
import { dayAndTime } from '../../lib/calendar/channels'
import type { AiringChannel } from '../../lib/calendar/channels'
import type { CalendarEntry } from '../../lib/calendar/model'
import { Skeleton } from '~/components/ui'
import { cn } from '~/lib/utils'
import { EpisodeRow } from './EpisodeRow'

/** CAL-005, "Group by: Channel": one section per channel or streamer, its episodes as rows with
 * the day and time where the network would be. `cards` lays the sections out as panels side by
 * side (the wide week); otherwise they stack under eyebrow headings (agenda, phone day). */
export function AiringChannels(props: {
  groups: AiringChannel[]
  cards?: boolean
  /** Still loading: placeholders, not the fallback. */
  waiting?: boolean
  fallback?: JSX.Element
  pending: Set<string>
  keyOf: (entry: CalendarEntry) => string
  onOpen: (entry: CalendarEntry) => void
  onToggle: (entry: CalendarEntry) => void
}) {
  const count = (group: AiringChannel) =>
    `${group.entries.length} ${group.entries.length === 1 ? 'episode' : 'episodes'}`
  return (
    <div
      class={cn(
        props.cards
          ? 'grid items-start gap-3 sm:grid-cols-2 xl:grid-cols-3'
          : 'flex flex-col gap-4',
      )}
    >
      <For
        each={props.groups}
        fallback={
          <Show when={!props.waiting} fallback={<Placeholders />}>
            {props.fallback}
          </Show>
        }
      >
        {(group) => (
          <section
            aria-label={`${group.channel}, ${count(group)}`}
            class={cn(props.cards && 'rounded-panel bg-surface px-3 pt-2 pb-1')}
          >
            <Show
              when={props.cards}
              fallback={
                <h3 class="eyebrow flex items-baseline gap-2 text-muted">
                  {group.channel}
                  <span class="tabular-nums">{group.entries.length}</span>
                </h3>
              }
            >
              <h2 class="flex items-baseline gap-2">
                <span class="font-display text-xl font-medium">
                  {group.channel}
                </span>
                <span class="text-sm text-muted tabular-nums">
                  {count(group)}
                </span>
              </h2>
            </Show>
            <ul class="mt-1 divide-y divide-line">
              <For each={group.entries}>
                {(entry) => (
                  <EpisodeRow
                    entry={entry}
                    when={dayAndTime(entry)}
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

function Placeholders() {
  return (
    <For each={[0, 1, 2]}>{() => <Skeleton class="h-16 rounded-field" />}</For>
  )
}
