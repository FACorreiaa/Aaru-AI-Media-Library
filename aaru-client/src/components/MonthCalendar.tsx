import { Link } from '@tanstack/solid-router'
import { For, Show, createEffect, createSignal, on } from 'solid-js'
import {
  addMonths,
  agendaDayLabel,
  agendaDays,
  airTime,
  badge,
  dayParts,
  entryKey,
  longWhen,
  monthLabel,
  monthOf,
  shortCode,
} from '../lib/calendar/model'
import type { CalendarEntry } from '../lib/calendar/model'
import { cn } from '../lib/cn'
import { WatchedCheckbox } from './WatchedCheckbox'
import { Button, buttonVariants } from './ui/button'
import { cardClass } from './ui/card'

// The month view, after Stremio's calendar: a month of your airings with posters in each day,
// the neighbouring months one click away, and an agenda from the selected day on. Posters from
// `md`; phones get coloured dots and the agenda under the grid.

export interface MonthCalendarProps {
  month: string
  grid: string[]
  today: string
  selected: string
  byDay: Map<string, CalendarEntry[]>
  onSelect: (day: string) => void
  onMonth: (delta: number) => void
  onToggle: (entry: CalendarEntry) => void
}

export function MonthCalendar(props: MonthCalendarProps) {
  return (
    <div class="lg:flex lg:items-start lg:gap-6">
      <section class="min-w-0 flex-1" aria-label={monthLabel(props.month)}>
        <MonthSwitcher month={props.month} onMonth={props.onMonth} />
        <div class="mt-4 grid grid-cols-7 gap-1 md:gap-1.5">
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
  const side = 'px-2 py-1 text-sm sm:text-base'
  return (
    <div class="flex items-baseline justify-center gap-2 sm:gap-6">
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
  // Three posters fit; a fourth becomes "+N" in the third slot.
  const shown = () =>
    props.entries.length <= 3 ? props.entries : props.entries.slice(0, 2)
  const more = () => props.entries.length - shown().length
  const count = () => props.entries.length
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
      class="flex min-h-14 min-w-0 flex-col gap-1 rounded-field p-1 text-left transition md:min-h-28 md:p-1.5"
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
      <span class="flex flex-wrap gap-0.5 md:hidden" aria-hidden="true">
        <For each={props.entries.slice(0, 3)}>
          {(entry) => (
            <span
              class="h-1.5 w-1.5 rounded-full"
              classList={{
                'bg-accent': entry.kind === 'premiere',
                'bg-ink': entry.kind === 'finale',
                'bg-muted': entry.kind === 'regular',
                'opacity-40': entry.watched,
              }}
            />
          )}
        </For>
      </span>
      <span class="hidden grid-cols-3 gap-1 md:grid" aria-hidden="true">
        <For each={shown()}>{(entry) => <Thumb entry={entry} />}</For>
        <Show when={more() > 0}>
          <span class="grid aspect-[2/3] place-items-center rounded-[4px] bg-ink/10 text-xs font-semibold text-muted">
            +{more()}
          </span>
        </Show>
      </span>
    </button>
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
      class="block aspect-[2/3] overflow-hidden rounded-[4px] bg-accent/20"
      classList={{ 'opacity-45': props.entry.watched }}
    >
      <Show
        when={props.entry.title.posterUrl && !broken()}
        fallback={
          <span class="grid h-full place-items-center text-[10px] font-semibold text-accent">
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
  onToggle: (entry: CalendarEntry) => void
}) {
  const [open, setOpen] = createSignal<string | null>(null)
  let list: HTMLDivElement | undefined
  const groups = () =>
    agendaDays(props.grid, props.selected)
      .map((day) => ({ day, entries: props.byDay.get(day) ?? [] }))
      .filter((group) => group.entries.length > 0)

  // A newly selected day starts the agenda from its top, collapsed.
  createEffect(
    on(
      () => props.selected,
      () => {
        setOpen(null)
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
        'mt-6 lg:sticky lg:top-4 lg:mt-0 lg:w-80 lg:shrink-0 xl:w-96',
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
                    <AgendaRow
                      entry={entry}
                      open={open() === entryKey(entry)}
                      onOpen={() =>
                        setOpen((key) =>
                          key === entryKey(entry) ? null : entryKey(entry),
                        )
                      }
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

function AgendaRow(props: {
  entry: CalendarEntry
  open: boolean
  onOpen: () => void
  onToggle: (entry: CalendarEntry) => void
}) {
  const e = () => props.entry
  const panel = () => `agenda-${entryKey(e()).replaceAll(':', '-')}`
  const label = () => badge(e())
  return (
    <li>
      <button
        type="button"
        aria-expanded={props.open}
        aria-controls={panel()}
        class="flex w-full items-baseline gap-2 py-2 text-left text-sm"
        classList={{ 'opacity-55': e().watched }}
        onClick={() => props.onOpen()}
      >
        <span class="min-w-0 flex-1 truncate font-medium">
          {e().title.title}
        </span>
        <span class="shrink-0 text-xs text-muted tabular-nums">
          {shortCode(e().season, e().number)}
        </span>
        {/* A fixed slot, so the codes line up whether or not a time is known. */}
        <span class="w-16 shrink-0 text-right text-xs text-muted tabular-nums">
          {airTime(e()) ?? ''}
        </span>
      </button>
      <Show when={props.open}>
        <div id={panel()} class="mb-3 rounded-panel bg-paper p-3 text-sm">
          <div class="flex items-start justify-between gap-2">
            <p class="font-semibold">
              {e().episodeName ?? shortCode(e().season, e().number)}
            </p>
            <Show when={label()}>
              {(text) => (
                <span
                  class="shrink-0 rounded-full px-2 py-0.5 text-[11px] font-semibold"
                  classList={{
                    'bg-accent text-on-accent': e().kind === 'premiere',
                    'bg-ink text-paper': e().kind === 'finale',
                  }}
                >
                  {text()}
                </span>
              )}
            </Show>
          </div>
          <Show when={e().episodeOverview}>
            <p class="mt-1 leading-relaxed text-muted">{e().episodeOverview}</p>
          </Show>
          <p class="mt-2 text-xs text-muted">{longWhen(e())}</p>
          <div class="mt-3 flex items-center justify-between gap-3">
            <label class="flex items-center gap-2 text-sm">
              <WatchedCheckbox entry={e()} onToggle={props.onToggle} />
              Watched
            </label>
            <Link
              to="/app/title/$id"
              params={{ id: e().libraryItemId }}
              class={buttonVariants({ variant: 'primary', size: 'xs' })}
            >
              Open show
            </Link>
          </div>
        </div>
      </Show>
    </li>
  )
}
