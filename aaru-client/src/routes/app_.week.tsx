import {
  Link,
  createFileRoute,
  redirect,
  useNavigate,
} from '@tanstack/solid-router'
import {
  For,
  Show,
  batch,
  createEffect,
  createMemo,
  createSignal,
  on,
  onCleanup,
  onMount,
} from 'solid-js'
import { z } from 'zod'
import { Wordmark } from '../components/Brand'
import { MonthCalendar } from '../components/MonthCalendar'
import { WeekGrid } from '../components/WeekGrid'
import {
  addDays,
  addMonths,
  daysFrom,
  entryKey,
  fetchWindows,
  groupByDay,
  localDayKey,
  mondayOf,
  monthGrid,
  monthOf,
  rangeLabel,
  withWatched,
} from '../lib/calendar/model'
import type { CalendarEntry } from '../lib/calendar/model'
import { getCalendar } from '../lib/calendar/server'
import { getSession } from '../lib/session/session'
import { setEpisode } from '../lib/title/server'

// APP-010 on the web: what airs from the user's own shows, as CAT's dense week or Stremio's
// month with an agenda. Rendered in the browser: "today" and every day boundary are the
// viewer's, not the Worker's (UTC).
type View = 'week' | 'month'

export const Route = createFileRoute('/app_/week')({
  head: () => ({ meta: [{ title: 'Calendar · Aaru' }] }),
  validateSearch: z.object({ view: z.enum(['week', 'month']).optional() }),
  beforeLoad: async () => {
    const session = await getSession()
    if (!session.signedIn) throw redirect({ to: '/sign-in' })
  },
  component: Calendar,
})

/** Days fetched around the visible week, so stepping a day rarely waits on the network. */
const LOOK_BEHIND = 7
const LOOK_AHEAD = 13
const VIEW_KEY = 'calendar.view'

function savedView(): View | null {
  try {
    const value = localStorage.getItem(VIEW_KEY)
    return value === 'week' || value === 'month' ? value : null
  } catch {
    return null // storage blocked: the default view it is
  }
}

function saveView(view: View) {
  try {
    localStorage.setItem(VIEW_KEY, view)
  } catch {
    // storage blocked: the choice lasts this visit only
  }
}

function Calendar() {
  const search = Route.useSearch()
  const navigate = useNavigate({ from: Route.fullPath })
  const [view, setView] = createSignal<View>(search().view ?? 'week')
  const [today, setToday] = createSignal<string | null>(null)
  const [start, setStart] = createSignal('')
  const [month, setMonth] = createSignal('')
  const [selected, setSelected] = createSignal('')
  const [entries, setEntries] = createSignal<CalendarEntry[]>([])
  const [loaded, setLoaded] = createSignal<{ first: string; last: string }>()
  const [loading, setLoading] = createSignal(true)
  const [problem, setProblem] = createSignal<string | null>(null)
  let request = 0

  const weekDays = createMemo(() => (start() ? daysFrom(start()) : []))
  const grid = createMemo(() => (month() ? monthGrid(month()) : []))
  const visible = () => (view() === 'week' ? weekDays() : grid())
  const byDay = createMemo(() => groupByDay(entries(), visible()))
  const empty = createMemo(
    () =>
      !loading() && [...byDay().values()].every((list) => list.length === 0),
  )

  onMount(() => {
    const now = localDayKey(new Date())
    // Together: the views render once `today` is set and need the rest with it.
    batch(() => {
      setToday(now)
      setStart(mondayOf(now))
      setMonth(monthOf(now))
      setSelected(now)
      if (!search().view) setView(savedView() ?? 'week')
    })

    const onKey = (event: KeyboardEvent) => {
      if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey)
        return
      const target = event.target as HTMLElement | null
      if (target?.closest('input:not([type=checkbox]), textarea, select'))
        return
      if (target?.isContentEditable) return
      const key = event.key
      if (view() === 'week') {
        if (key === 'ArrowLeft') step(-1)
        else if (key === 'ArrowRight') step(1)
        else return
      } else if (key === 'ArrowLeft') moveDay(-1)
      else if (key === 'ArrowRight') moveDay(1)
      else if (key === 'PageUp') changeMonth(-1)
      else if (key === 'PageDown') changeMonth(1)
      else return
      event.preventDefault()
    }
    window.addEventListener('keydown', onKey)
    onCleanup(() => window.removeEventListener('keydown', onKey))
  })

  // What the current view needs loaded: the week with margin, or the whole month grid.
  const wanted = createMemo(
    () => {
      if (view() === 'week') {
        const first = start()
        if (!first) return null
        return {
          first,
          last: addDays(first, 6),
          fetchFirst: addDays(first, -LOOK_BEHIND),
          fetchLast: addDays(first, LOOK_AHEAD),
        }
      }
      const days = grid()
      if (!days.length) return null
      const first = days[0]
      const last = days[days.length - 1]
      return { first, last, fetchFirst: first, fetchLast: last }
    },
    null,
    {
      equals: (a, b) =>
        a?.fetchFirst === b?.fetchFirst && a?.fetchLast === b?.fetchLast,
    },
  )

  createEffect(
    on(wanted, (want) => {
      if (!want) return
      const have = loaded()
      if (have && have.first <= want.first && want.last <= have.last) return
      void load(want.fetchFirst, want.fetchLast)
    }),
  )

  async function load(first: string, last: string) {
    const mine = ++request
    setLoading(true)
    setProblem(null)
    try {
      // A six-row month is more than one request may cover.
      const pages = await Promise.all(
        fetchWindows(first, last).map((window) =>
          getCalendar({ data: window }),
        ),
      )
      if (mine !== request) return
      const seen = new Set<string>()
      setEntries(
        pages.flat().filter((entry) => {
          const key = entryKey(entry)
          if (seen.has(key)) return false
          seen.add(key)
          return true
        }),
      )
      setLoaded({ first, last })
    } catch (err) {
      if (mine !== request) return
      setProblem(
        err instanceof Error
          ? err.message
          : 'The calendar could not be loaded.',
      )
    } finally {
      if (mine === request) setLoading(false)
    }
  }

  function switchView(next: View) {
    if (next === view()) return
    batch(() => {
      // Both views open on the selected day.
      if (next === 'week') setStart(mondayOf(selected()))
      else setMonth(monthOf(selected()))
      setView(next)
    })
    saveView(next)
    void navigate({ search: { view: next }, replace: true })
  }

  function step(delta: number) {
    if (!start()) return
    batch(() => {
      setStart((s) => addDays(s, delta))
      setSelected((s) => addDays(s, delta))
    })
  }

  /** Month view: the selected day moves, and the month follows it across an edge. */
  function moveDay(delta: number) {
    if (!selected()) return
    selectDay(addDays(selected(), delta))
  }

  function selectDay(day: string) {
    batch(() => {
      setSelected(day)
      if (view() === 'month') setMonth(monthOf(day))
    })
  }

  function changeMonth(delta: number) {
    if (!month()) return
    const next = addMonths(month(), delta)
    const now = today()
    batch(() => {
      setMonth(next)
      setSelected(now && monthOf(now) === next ? now : `${next}-01`)
    })
  }

  function goToday() {
    const now = today()
    if (!now) return
    batch(() => {
      setStart(mondayOf(now))
      setMonth(monthOf(now))
      setSelected(now)
    })
  }

  async function toggle(entry: CalendarEntry) {
    const watched = !entry.watched
    setProblem(null)
    setEntries((list) => withWatched(list, entry, watched))
    try {
      await setEpisode({
        data: {
          id: entry.libraryItemId,
          season: entry.season,
          episode: entry.number,
          watched,
        },
      })
    } catch (err) {
      setEntries((list) => withWatched(list, entry, entry.watched))
      setProblem(
        err instanceof Error ? err.message : 'That episode was not saved.',
      )
    }
  }

  const button =
    'rounded-full border border-line px-3 py-1.5 text-sm font-medium text-ink hover:bg-surface disabled:opacity-40'

  return (
    <div class="min-h-[100dvh]">
      <header class="mx-auto flex h-18 max-w-[1600px] items-center justify-between px-4 md:px-8">
        <Wordmark />
        <Link to="/app" class="text-sm font-medium text-muted hover:text-ink">
          Library
        </Link>
      </header>

      <main class="mx-auto max-w-[1600px] px-4 pb-16 md:px-8">
        <div class="flex flex-wrap items-end justify-between gap-x-6 gap-y-3">
          <div>
            <h1 class="font-display text-4xl font-medium tracking-tight">
              Calendar
            </h1>
            <p class="mt-1 text-sm text-muted" aria-live="polite">
              <Show
                when={view() === 'week' && weekDays().length}
                fallback="Your shows, by the day they air"
              >
                {rangeLabel(weekDays()[0], weekDays()[6])}
              </Show>
            </p>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <div
              class="flex rounded-full border border-line p-0.5"
              role="group"
              aria-label="Calendar view"
            >
              <For each={['week', 'month'] as const}>
                {(option) => (
                  <button
                    type="button"
                    aria-pressed={view() === option}
                    class="rounded-full px-3 py-1 text-sm font-medium"
                    classList={{
                      'bg-ink text-paper': view() === option,
                      'text-muted hover:text-ink': view() !== option,
                    }}
                    onClick={() => switchView(option)}
                  >
                    {option === 'week' ? 'Week' : 'Month'}
                  </button>
                )}
              </For>
            </div>
            <nav class="flex items-center gap-2" aria-label="Days">
              <Show when={view() === 'week'}>
                <button
                  type="button"
                  class={button}
                  disabled={!today()}
                  onClick={() => step(-1)}
                  aria-keyshortcuts="ArrowLeft"
                >
                  <span aria-hidden="true">‹</span>
                  <span class="sr-only sm:not-sr-only"> Previous day</span>
                </button>
              </Show>
              <button
                type="button"
                class={button}
                disabled={!today()}
                onClick={goToday}
              >
                Today
              </button>
              <Show when={view() === 'week'}>
                <button
                  type="button"
                  class={button}
                  disabled={!today()}
                  onClick={() => step(1)}
                  aria-keyshortcuts="ArrowRight"
                >
                  <span class="sr-only sm:not-sr-only">Next day </span>
                  <span aria-hidden="true">›</span>
                </button>
              </Show>
            </nav>
          </div>
        </div>

        <Show when={problem()}>
          {(message) => (
            <p
              role="alert"
              class="mt-4 rounded-[14px] bg-danger/10 px-4 py-3 text-sm text-danger"
            >
              {message()}
            </p>
          )}
        </Show>

        <Show when={empty() && !problem()}>
          <div class="mt-6 rounded-[20px] bg-surface p-6">
            <p class="font-display text-xl">
              Nothing from your shows airs this{' '}
              {view() === 'week' ? 'week' : 'month'}.
            </p>
            <p class="mt-1 text-sm text-muted">
              Shows you add, or mark as watching, appear here as their episodes
              air.
            </p>
            <Link
              to="/app"
              class="mt-4 inline-block rounded-full bg-accent px-4 py-2 text-sm font-semibold text-on-accent"
            >
              Find shows to add
            </Link>
          </div>
        </Show>

        <div class="mt-6" aria-busy={loading()}>
          <Show
            when={today()}
            fallback={<p class="text-sm text-muted">Loading the calendar…</p>}
          >
            {(now) => (
              <Show
                when={view() === 'month'}
                fallback={
                  <WeekGrid
                    days={weekDays()}
                    today={now()}
                    selected={selected()}
                    byDay={byDay()}
                    onSelect={setSelected}
                    onToggle={(entry) => void toggle(entry)}
                  />
                }
              >
                <MonthCalendar
                  month={month()}
                  grid={grid()}
                  today={now()}
                  selected={selected()}
                  byDay={byDay()}
                  onSelect={selectDay}
                  onMonth={changeMonth}
                  onToggle={(entry) => void toggle(entry)}
                />
              </Show>
            )}
          </Show>
        </div>
      </main>
    </div>
  )
}
