import { For, Show, createEffect, createSignal, on } from 'solid-js'
import {
  addMonths,
  agendaDayLabel,
  agendaDays,
  dayParts,
  monthLabel,
  monthOf,
} from '../lib/calendar/model'
import type { CalendarEntry } from '../lib/calendar/model'
import { cn } from '../lib/cn'
import { slideIn } from '../lib/motion'
import { EpisodeRow } from './calendar/EpisodeRow'
import { Badge } from './ui/badge'
import { Button } from './ui/button'
import { cardClass } from './ui/card'

// The month view, after Stremio's calendar (CAL-002): a month of your airings with posters in
// each day, the neighbouring months one click away, and an agenda from the selected day on.
// Phones get two small posters per day and open the day as a sheet (the route decides); wider
// screens keep the agenda beside the grid.

export interface MonthCalendarProps {
  month: string
  grid: string[]
  today: string
  selected: string
  byDay: Map<string, CalendarEntry[]>
  pending: Set<string>
  keyOf: (entry: CalendarEntry) => string
  onSelect: (day: string) => void
  onMonth: (delta: number) => void
  onOpen: (entry: CalendarEntry) => void
  onToggle: (entry: CalendarEntry) => void
}

export function MonthCalendar(props: MonthCalendarProps) {
  let grid: HTMLDivElement | undefined
  // Paging months slides the new one in from the side it lies on. Not on first render.
  createEffect(
    on(
      () => props.month,
      (month, previous) => {
        if (grid && previous && month !== previous)
          void slideIn(grid, month > previous ? 1 : -1)
      },
      { defer: true },
    ),
  )
  return (
    <div class="lg:flex lg:items-start lg:gap-6">
      <section class="min-w-0 flex-1" aria-label={monthLabel(props.month)}>
        <MonthSwitcher month={props.month} onMonth={props.onMonth} />
        <div ref={grid} class="mt-4 grid grid-cols-7 gap-1 md:gap-1.5">
          <For each={props.grid.slice(0, 7)}>
            {(day) => (
              <span
                class="pb-1 text-center text-xs font-medium text-muted"
                aria-hidden="true"
              >
                {dayParts(day).short}
              </span>
            )}
          </For>
          <For each={props.grid}>
            {(day) => (
              <MonthDay
                day={day}
                month={props.month}
                today={props.today}
                selected={day === props.selected}
                entries={props.byDay.get(day) ?? []}
                onSelect={props.onSelect}
              />
            )}
          </For>
        </div>
      </section>
      <Agenda
        grid={props.grid}
        today={props.today}
        selected={props.selected}
        byDay={props.byDay}
        pending={props.pending}
        keyOf={props.keyOf}
        onOpen={props.onOpen}
        onToggle={props.onToggle}
      />
    </div>
  )
}

/** "September  October 2026  November": the neighbours are the month buttons. */
function MonthSwitcher(props: {
  month: string
  onMonth: (delta: number) => void
}) {
  const neighbour = (delta: number) => {
    const m = addMonths(props.month, delta)
    return monthLabel(m, undefined, m.slice(0, 4) !== props.month.slice(0, 4))
  }
  const side = 'min-h-11 px-2 text-sm sm:text-base'
  return (
    <div class="flex items-center justify-center gap-2 sm:gap-6">
      <Button
        variant="ghost"
        size="bare"
        class={side}
        onClick={() => props.onMonth(-1)}
        aria-keyshortcuts="PageUp"
      >
        <span aria-hidden="true">‹ </span>
        <span class="sr-only">Previous month, </span>
        {neighbour(-1)}
      </Button>
      <h2
        class="font-display text-2xl font-medium tracking-tight sm:text-3xl"
        aria-live="polite"
      >
        {monthLabel(props.month)}
      </h2>
      <Button
        variant="ghost"
        size="bare"
        class={side}
        onClick={() => props.onMonth(1)}
        aria-keyshortcuts="PageDown"
      >
        <span class="sr-only">Next month, </span>
        {neighbour(1)}
        <span aria-hidden="true"> ›</span>
      </Button>
    </div>
  )
}

function MonthDay(props: {
  day: string
  month: string
  today: string
  selected: boolean
  entries: CalendarEntry[]
  onSelect: (day: string) => void
}) {
  const parts = dayParts(props.day)
  const isToday = () => props.day === props.today
  const outside = () => monthOf(props.day) !== props.month
  const past = () => props.day < props.today
  const count = () => props.entries.length
  // Phones fit two posters, wider screens three; past that the last slot says "+N".
  const phone = () => (count() <= 2 ? props.entries : props.entries.slice(0, 1))
  const wide = () => (count() <= 3 ? props.entries : props.entries.slice(0, 2))
  return (
    <button
      type="button"
      aria-pressed={props.selected}
      aria-label={`${parts.weekday} ${parts.day}${isToday() ? ', today' : ''}, ${
        count() === 0
          ? 'nothing airs'
          : count() === 1
            ? '1 episode'
            : `${count()} episodes`
      }`}
      class="flex min-h-20 min-w-0 flex-col gap-1 rounded-field p-1 text-left transition md:min-h-28 md:p-1.5"
      classList={{
        'bg-surface hover:ring-1 hover:ring-line': !props.selected,
        'bg-accent/15 ring-2 ring-accent': props.selected,
        'opacity-40': outside(),
        'opacity-70': !outside() && past() && !isToday(),
      }}
      onClick={() => props.onSelect(props.day)}
    >
      <span
        class="flex h-6 min-w-6 items-center justify-center self-start rounded-full px-1 text-sm tabular-nums"
        classList={{
          'bg-accent font-semibold text-on-accent': isToday(),
          'text-muted': !isToday() && past(),
        }}
      >
        {parts.day}
      </span>
      <span class="grid grid-cols-2 gap-0.5 md:hidden" aria-hidden="true">
        <For each={phone()}>{(entry) => <Thumb entry={entry} />}</For>
        <Show when={count() > phone().length}>
          <More count={count() - phone().length} />
        </Show>
      </span>
      <span class="hidden grid-cols-3 gap-1 md:grid" aria-hidden="true">
        <For each={wide()}>{(entry) => <Thumb entry={entry} />}</For>
        <Show when={count() > wide().length}>
          <More count={count() - wide().length} />
        </Show>
      </span>
    </button>
  )
}

function More(props: { count: number }) {
  return (
    <span class="grid aspect-[2/3] place-items-center rounded-thumb bg-ink/10">
      <Badge size="xs" tone="soft">
        +{props.count}
      </Badge>
    </span>
  )
}

/** A poster thumbnail, or the show's initials on a tint when there is none. */
function Thumb(props: { entry: CalendarEntry }) {
  const [broken, setBroken] = createSignal(false)
  const initials = () =>
    props.entry.title.title
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((word) => word[0])
      .join('')
      .toUpperCase()
  return (
    <span
      class="block aspect-[2/3] overflow-hidden rounded-thumb bg-accent/20"
      classList={{
        'opacity-45': props.entry.watched,
        'ring-2 ring-accent': props.entry.kind === 'premiere',
        'ring-2 ring-ink': props.entry.kind === 'finale',
      }}
    >
      <Show
        when={props.entry.title.posterUrl && !broken()}
        fallback={
          <span class="grid h-full place-items-center text-xs font-semibold text-accent">
            {initials()}
          </span>
        }
      >
        <img
          src={props.entry.title.posterUrl}
          alt=""
          loading="lazy"
          decoding="async"
          class="h-full w-full object-cover"
          onError={() => setBroken(true)}
        />
      </Show>
    </span>
  )
}

function Agenda(props: {
  grid: string[]
  today: string
  selected: string
  byDay: Map<string, CalendarEntry[]>
  pending: Set<string>
  keyOf: (entry: CalendarEntry) => string
  onOpen: (entry: CalendarEntry) => void
  onToggle: (entry: CalendarEntry) => void
}) {
  let list: HTMLDivElement | undefined
  const groups = () =>
    agendaDays(props.grid, props.selected)
      .map((day) => ({ day, entries: props.byDay.get(day) ?? [] }))
      .filter((group) => group.entries.length > 0)

  // A newly selected day starts the agenda from its top.
  createEffect(
    on(
      () => props.selected,
      () => {
        if (list) list.scrollTop = 0
      },
      { defer: true },
    ),
  )

  return (
    <aside
      aria-label="Agenda"
      class={cn(
        cardClass,
        'mt-6 lg:sticky lg:top-4 lg:mt-0 lg:w-96 lg:shrink-0',
      )}
    >
      <div
        ref={list}
        class="p-4 lg:max-h-[calc(100dvh-2rem)] lg:overflow-y-auto"
      >
        <For
          each={groups()}
          fallback={
            <p class="py-4 text-sm text-muted">
              Nothing from your shows airs from{' '}
              {props.selected ? agendaDayLabel(props.selected) : 'here'} to the
              end of this view.
            </p>
          }
        >
          {(group) => (
            <section class="mb-4 last:mb-0">
              <h3
                class="text-xs font-semibold tracking-wide uppercase"
                classList={{
                  'text-accent': group.day === props.today,
                  'text-muted': group.day !== props.today,
                }}
              >
                {group.day === props.today ? 'Today · ' : ''}
                {agendaDayLabel(group.day)}
              </h3>
              <ul class="mt-1 divide-y divide-line">
                <For each={group.entries}>
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
            </section>
          )}
        </For>
      </div>
    </aside>
  )
}
