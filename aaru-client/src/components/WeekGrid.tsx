import { For, Index, Show, createSignal } from 'solid-js'
import { badge, dayParts, episodeCode, metaLine } from '../lib/calendar/model'
import type { CalendarEntry } from '../lib/calendar/model'
import { EpisodeRow } from './calendar/EpisodeRow'
import { WatchButton } from './calendar/WatchButton'
import { cn } from '~/lib/utils'
import {
  Badge,
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
  Button,
  Skeleton,
} from '~/components/ui'

// APP-010, CAL-002 · `WeekGrid` (DESIGN.md §14, VIEWS.md): Pogdesign CAT's dense week, in Aaru's
// palette. Seven columns from 1280px, scroll-snapping columns below that, and on phones a day
// strip over that day's episodes as poster rows. A cell or row opens the episode sheet; the
// tick works on its own.

export interface WeekGridProps {
  days: string[]
  today: string
  /** The phone pager's day. */
  selected: string
  byDay: Map<string, CalendarEntry[]>
  /** These days are still loading: placeholders, not "nothing airs". */
  waiting: boolean
  pending: Set<string>
  keyOf: (entry: CalendarEntry) => string
  onSelect: (day: string) => void
  onOpen: (entry: CalendarEntry) => void
  onToggle: (entry: CalendarEntry) => void
}

export function WeekGrid(props: WeekGridProps) {
  return (
    <>
      {/* Phones: a 7-day strip and the chosen day's rows. Tabs are keyed by position, not date,
 so paging the week relabels the same buttons and keyboard focus stays put. */}
      <Tabs
        class="block sm:hidden"
        value={String(props.days.indexOf(props.selected))}
        onChange={(index) => {
          const day = props.days[Number(index)]
          if (day) props.onSelect(day)
        }}
      >
        <TabsList
          class="grid h-auto w-full grid-cols-7 gap-1 rounded-none bg-transparent ring-0"
          aria-label="Day"
        >
          <Index each={props.days}>
            {(day, index) => {
              const parts = () => dayParts(day())
              const count = () => props.byDay.get(day())?.length ?? 0
              return (
                <TabsTrigger
                  value={String(index)}
                  aria-label={`${parts().weekday} ${parts().day}, ${count()} episodes`}
                  // `cn`, not classList: the trigger's own text colour must lose to these.
                  class={cn(
                    'flex h-auto min-h-16 flex-col items-center justify-center gap-0 rounded-field px-0 py-0 text-xs font-normal transition-colors',
                    day() === props.selected
                      ? 'bg-ink text-paper'
                      : day() === props.today
                        ? 'font-semibold text-accent'
                        : 'text-muted',
                  )}
                >
                  <span>{parts().short}</span>
                  <span class="font-display text-xl leading-tight">
                    {parts().day}
                  </span>
                  <span
                    class="mt-0.5 h-1.5 w-1.5 rounded-full"
                    classList={{ 'bg-current': count() > 0 }}
                  />
                </TabsTrigger>
              )
            }}
          </Index>
        </TabsList>
        <TabsContent value={String(props.days.indexOf(props.selected))}>
          <ul class="mt-3 divide-y divide-line">
            <For
              each={props.byDay.get(props.selected) ?? []}
              fallback={
                <Show
                  when={!props.waiting}
                  fallback={
                    <For each={[0, 1]}>
                      {() => (
                        <li class="py-2">
                          <Skeleton class="h-20 rounded-field" />
                        </li>
                      )}
                    </For>
                  }
                >
                  <li class="rounded-panel bg-surface px-4 py-8 text-center text-sm text-muted">
                    Nothing airs on{' '}
                    {props.selected
                      ? dayParts(props.selected).weekday
                      : 'this day'}
                    .
                  </li>
                </Show>
              }
            >
              {(entry) => (
                <EpisodeRow
                  entry={entry}
                  pending={props.pending.has(props.keyOf(entry))}
                  onOpen={props.onOpen}
                  onToggle={props.onToggle}
                />
              )}
            </For>
          </ul>
        </TabsContent>
      </Tabs>

      {/* Tablets scroll the columns; desktops see the whole week. */}
      <div class="hidden gap-3 sm:flex sm:snap-x sm:snap-mandatory sm:overflow-x-auto sm:pb-2 xl:grid xl:grid-cols-7 xl:overflow-visible">
        <For each={props.days}>
          {(day) => (
            <DayColumn
              day={day}
              today={day === props.today}
              entries={props.byDay.get(day) ?? []}
              waiting={props.waiting}
              pending={props.pending}
              keyOf={props.keyOf}
              onOpen={props.onOpen}
              onToggle={props.onToggle}
            />
          )}
        </For>
      </div>
    </>
  )
}

function DayColumn(props: {
  day: string
  today: boolean
  entries: CalendarEntry[]
  waiting: boolean
  pending: Set<string>
  keyOf: (entry: CalendarEntry) => string
  onOpen: (entry: CalendarEntry) => void
  onToggle: (entry: CalendarEntry) => void
}) {
  const parts = dayParts(props.day)
  return (
    <section
      aria-label={`${parts.weekday} ${parts.day}${props.today ? ', today' : ''}`}
      class="flex w-64 shrink-0 snap-start flex-col rounded-panel bg-surface xl:w-auto xl:min-w-0"
      classList={{ 'ring-2 ring-accent': props.today }}
    >
      <header
        class="flex items-baseline gap-2 rounded-t-panel px-3 py-2"
        classList={{ 'bg-accent text-on-accent': props.today }}
      >
        <span class="font-display text-3xl leading-none font-medium">
          {parts.day}
        </span>
        <span class="text-sm" classList={{ 'text-muted': !props.today }}>
          {parts.weekday}
        </span>
      </header>
      <div class="flex flex-col gap-2 p-2">
        <For
          each={props.entries}
          fallback={
            <Show
              when={!props.waiting}
              fallback={<Skeleton class="h-16 rounded-field" />}
            >
              <p class="px-1 py-3 text-xs text-muted/80">—</p>
            </Show>
          }
        >
          {(entry) => (
            <EpisodeCell
              entry={entry}
              pending={props.pending.has(props.keyOf(entry))}
              onOpen={props.onOpen}
              onToggle={props.onToggle}
            />
          )}
        </For>
      </div>
    </section>
  )
}

function EpisodeCell(props: {
  entry: CalendarEntry
  pending: boolean
  onOpen: (entry: CalendarEntry) => void
  onToggle: (entry: CalendarEntry) => void
}) {
  const e = () => props.entry
  const label = () => badge(e())
  const meta = () => metaLine(e())
  return (
    <article
      class="relative overflow-hidden rounded-field bg-paper ring-1 transition-[opacity,box-shadow]"
      classList={{
        'opacity-55': e().watched,
        'ring-accent': e().kind === 'premiere',
        'ring-ink/50': e().kind === 'finale',
        'ring-line': e().kind === 'regular',
      }}
    >
      <Button
        variant="soft"
        size="bare"
        class="block w-full text-left rounded-none font-normal hover:bg-transparent motion-safe:active:scale-100"
        aria-label={`${e().title.title}, ${episodeCode(e().season, e().number)}${
          e().episodeName ? `, ${e().episodeName}` : ''
        }. Details`}
        onClick={() => props.onOpen(e())}
      >
        <Banner entry={e()} />
        <div class="min-w-0 p-2 pr-12 text-xs leading-snug">
          <p class="truncate text-sm font-semibold text-accent">
            {e().title.title}
          </p>
          <p class="font-medium tabular-nums">
            {episodeCode(e().season, e().number)}
          </p>
          <Show when={e().episodeName}>
            <p class="truncate">{e().episodeName}</p>
          </Show>
          <Show when={meta()}>
            <p class="truncate text-muted">{meta()}</p>
          </Show>
        </div>
      </Button>
      <Show when={label()}>
        {(text) => (
          <Badge
            size="xs"
            variant={e().kind === 'finale' ? 'ink' : 'default'}
            class="absolute top-1.5 right-1.5"
          >
            {text()}
          </Badge>
        )}
      </Show>
      <WatchButton
        entry={e()}
        pending={props.pending}
        onToggle={props.onToggle}
        class="absolute right-0 bottom-0"
      />
    </article>
  )
}

/** Wide art: the backdrop, else the poster cropped, else a tinted block with the title. */
function Banner(props: { entry: CalendarEntry }) {
  const sources = () =>
    [props.entry.title.backdropUrl, props.entry.title.posterUrl].filter(
      (url): url is string => !!url,
    )
  const [failed, setFailed] = createSignal(0)
  const url = () => sources()[failed()]
  return (
    <div class="aspect-[3/1] overflow-hidden bg-accent/15" aria-hidden="true">
      <Show
        when={url()}
        keyed
        fallback={
          <div class="grid h-full place-items-center px-3 text-center font-display text-base leading-tight text-accent">
            {props.entry.title.title}
          </div>
        }
      >
        {(src) => (
          <img
            src={src}
            alt=""
            loading="lazy"
            decoding="async"
            class="h-full w-full object-cover"
            onError={() => setFailed((n) => n + 1)}
          />
        )}
      </Show>
    </div>
  )
}
