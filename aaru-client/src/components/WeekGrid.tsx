import { Link } from '@tanstack/solid-router'
import {
  For,
  Index,
  Show,
  createSignal,
  createUniqueId,
  onCleanup,
  onMount,
} from 'solid-js'
import {
  badge,
  dayParts,
  episodeCode,
  longWhen,
  metaLine,
} from '../lib/calendar/model'
import type { CalendarEntry } from '../lib/calendar/model'
import { WatchedCheckbox } from './WatchedCheckbox'
import { Tabs, TabsContent, TabsList, TabsTrigger } from './ui/tabs'

// APP-010 · `WeekGrid` (DESIGN.md §14, VIEWS.md): Pogdesign CAT's dense week, in Aaru's palette.
// Seven columns from 1280px, scroll-snapping columns below that, and a day pager on phones.

export interface WeekGridProps {
  days: string[]
  today: string
  /** The phone pager's day. */
  selected: string
  byDay: Map<string, CalendarEntry[]>
  onSelect: (day: string) => void
  onToggle: (entry: CalendarEntry) => void
}

export function WeekGrid(props: WeekGridProps) {
  return (
    <>
      {/* Phones: a 7-day strip and the chosen day's cells. Tabs are keyed by position, not
          date, so paging the week relabels the same buttons and keyboard focus stays put. */}
      <Tabs
        class="sm:hidden"
        value={String(props.days.indexOf(props.selected))}
        onChange={(index) => {
          const day = props.days[Number(index)]
          if (day) props.onSelect(day)
        }}
      >
        <TabsList class="grid grid-cols-7 gap-1" aria-label="Day">
          <Index each={props.days}>
            {(day, index) => {
              const parts = () => dayParts(day())
              return (
                <TabsTrigger
                  value={String(index)}
                  variant="bare"
                  aria-label={`${parts().weekday} ${parts().day}`}
                  class="flex flex-col items-center rounded-field py-1.5 text-xs"
                  classList={{
                    'text-accent font-semibold':
                      day() !== props.selected && day() === props.today,
                    'text-muted':
                      day() !== props.selected && day() !== props.today,
                  }}
                >
                  <span>{parts().short}</span>
                  <span class="font-display text-lg leading-tight">
                    {parts().day}
                  </span>
                  <span
                    class="mt-0.5 h-1 w-1 rounded-full"
                    classList={{
                      'bg-current': (props.byDay.get(day())?.length ?? 0) > 0,
                    }}
                  />
                </TabsTrigger>
              )
            }}
          </Index>
        </TabsList>
        <TabsContent
          value={String(props.days.indexOf(props.selected))}
          class="mt-3 flex flex-col gap-2"
        >
          <For
            each={props.byDay.get(props.selected) ?? []}
            fallback={
              <p class="rounded-panel bg-surface px-4 py-6 text-center text-sm text-muted">
                Nothing airs on{' '}
                {props.selected ? dayParts(props.selected).weekday : 'this day'}
                .
              </p>
            }
          >
            {(entry, i) => (
              <EpisodeCell
                entry={entry}
                above={isLastOfMany(i(), props.byDay.get(props.selected))}
                onToggle={props.onToggle}
              />
            )}
          </For>
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
              onToggle={props.onToggle}
            />
          )}
        </For>
      </div>
    </>
  )
}

const isLastOfMany = (index: number, list: unknown[] | undefined) =>
  !!list && list.length > 1 && index === list.length - 1

function DayColumn(props: {
  day: string
  today: boolean
  entries: CalendarEntry[]
  onToggle: (entry: CalendarEntry) => void
}) {
  const parts = dayParts(props.day)
  return (
    <section
      aria-label={`${parts.weekday} ${parts.day}${props.today ? ', today' : ''}`}
      // The minimum height leaves room for a lone cell's tooltip inside the scroller, which
      // clips; from 1280px nothing scrolls or clips.
      class="flex min-h-100 w-64 shrink-0 snap-start flex-col rounded-panel bg-surface xl:min-h-0 xl:w-auto xl:min-w-0"
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
          fallback={<p class="px-1 py-3 text-xs text-muted/80">—</p>}
        >
          {(entry, i) => (
            <EpisodeCell
              entry={entry}
              above={isLastOfMany(i(), props.entries)}
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
  /** The tooltip opens above: the last cell of a column with more than one. */
  above?: boolean
  onToggle: (entry: CalendarEntry) => void
}) {
  const e = () => props.entry
  const code = () => episodeCode(e().season, e().number)
  const label = () => badge(e())
  const meta = () => metaLine(e())
  const tip = `tip-${createUniqueId()}`
  // Esc hides the tooltip until the pointer leaves the cell or focus moves out of it. While
  // only hovered, the key goes to the page, so a window listener is added for that time.
  const [dismissed, setDismissed] = createSignal(false)
  const onEscape = (event: KeyboardEvent) => {
    if (event.key === 'Escape') setDismissed(true)
  }
  // Inside onMount: the server has no window.
  onMount(() =>
    onCleanup(() => window.removeEventListener('keydown', onEscape)),
  )
  return (
    <article
      class="group relative rounded-field bg-paper ring-1 transition-opacity"
      onKeyDown={onEscape}
      onPointerEnter={() => window.addEventListener('keydown', onEscape)}
      onPointerLeave={() => {
        window.removeEventListener('keydown', onEscape)
        setDismissed(false)
      }}
      onFocusOut={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget as Node | null))
          setDismissed(false)
      }}
      classList={{
        'opacity-55': e().watched,
        'ring-accent': e().kind === 'premiere',
        'ring-ink/50': e().kind === 'finale',
        'ring-line': e().kind === 'regular',
      }}
    >
      <Banner entry={e()} />
      <Show when={label()}>
        {(text) => (
          <span
            class="absolute top-1.5 right-1.5 rounded-full px-2 py-0.5 text-[11px] font-semibold"
            classList={{
              'bg-accent text-on-accent': e().kind === 'premiere',
              'bg-ink text-paper': e().kind === 'finale',
            }}
          >
            {text()}
          </span>
        )}
      </Show>
      <div class="flex gap-2 p-2">
        <WatchedCheckbox entry={e()} onToggle={props.onToggle} class="mt-0.5" />
        <div class="min-w-0 text-xs leading-snug">
          <Link
            to="/app/title/$id"
            params={{ id: e().libraryItemId }}
            aria-describedby={tip}
            class="block truncate text-sm font-semibold text-accent hover:underline"
          >
            {e().title.title}
          </Link>
          <p class="font-medium tabular-nums">{code()}</p>
          <Show when={e().episodeName}>
            <p class="truncate">{e().episodeName}</p>
          </Show>
          <Show when={meta()}>
            <p class="truncate text-muted">{meta()}</p>
          </Show>
        </div>
      </div>
      {/* Shown on hover and focus within the cell (WCAG 1.4.13): the pointer can move onto it
          (its padding bridges the gap), Esc hides it until the pointer or focus leaves, and it
          opens below the cell, or above the last one, staying inside the column. */}
      <div
        id={tip}
        role="tooltip"
        class="invisible absolute inset-x-0 z-20 opacity-0 transition-opacity motion-reduce:transition-none"
        classList={{
          'top-full pt-1': !props.above,
          'bottom-full pb-1': props.above,
          'group-hover:visible group-hover:opacity-100 group-focus-within:visible group-focus-within:opacity-100':
            !dismissed(),
        }}
      >
        <div class="rounded-field bg-ink p-3 text-xs leading-relaxed text-paper shadow-lg">
          <p class="font-semibold">
            {e().title.title} · {code()}
          </p>
          <Show when={e().episodeName}>
            <p>{e().episodeName}</p>
          </Show>
          <Show when={e().episodeOverview}>
            <p class="mt-1 line-clamp-4 opacity-90">{e().episodeOverview}</p>
          </Show>
          <p class="mt-1 opacity-80">
            {longWhen(e())}
            <Show when={e().runtimeMinutes}> · {e().runtimeMinutes} min</Show>
          </p>
          <Show when={e().watched}>
            <p class="mt-1 opacity-80">Watched</p>
          </Show>
        </div>
      </div>
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
    <div
      class="aspect-[3/1] overflow-hidden rounded-t-field bg-accent/15"
      aria-hidden="true"
    >
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
