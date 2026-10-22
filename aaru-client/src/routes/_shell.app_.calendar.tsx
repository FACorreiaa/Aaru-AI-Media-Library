import { createFileRoute, useNavigate } from '@tanstack/solid-router'
import { lastShown } from '../lib/presence'
import { useAppShell } from '../components/shell/context'
import {
  Show,
  batch,
  createEffect,
  createMemo,
  createSignal,
  lazy,
  on,
  onCleanup,
  onMount,
} from 'solid-js'
import { optionalEnum } from '../lib/search-params'
import { MonthCalendar } from '../components/MonthCalendar'
import { WeekGrid } from '../components/WeekGrid'
import {
  CalendarToolbar,
  FilterChips,
} from '../components/calendar/CalendarToolbar'
import { Alert, AlertDescription, Button, cardClass } from '~/components/ui'
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
import { MISSED_DAYS, applyFilter, catchUp } from '../lib/calendar/filters'
import type {
  CalendarFilter,
  CalendarView,
  KindFilter,
  OnlyFilter,
} from '../lib/calendar/filters'
import { getCalendar } from '../lib/calendar/server'
import { setEpisode } from '../lib/title/server'
import { cn } from '~/lib/utils'
import { slideIn } from '../lib/motion'

// APP-010, CAL-002 on the web: what airs from the user's own shows, as CAT's dense week,
// Stremio's month with an agenda, or what was missed. Rendered in the browser: "today" and
// every day boundary are the viewer's, not the Worker's (UTC). Filters and the view live in the
// URL; the sheets and Missed load on first use, so the page stays inside its size budget.

const CalendarEpisodeSheet = lazy(
  () => import('../components/calendar/CalendarEpisodeSheet'),
)
const DaySheet = lazy(() => import('../components/calendar/DaySheet'))
const CatchUpList = lazy(() => import('../components/calendar/CatchUpList'))

interface Search {
  view?: CalendarView
  hide?: 'watched'
  only?: OnlyFilter
  kind?: KindFilter
}

export const Route = createFileRoute('/_shell/app_/calendar')({
  head: () => ({ meta: [{ title: 'Calendar · Aaru' }] }),
  validateSearch: (search): Search => ({
    view: optionalEnum(search.view, ['week', 'month', 'missed']),
    hide: optionalEnum(search.hide, ['watched']),
    only: optionalEnum(search.only, ['premieres', 'finales']),
    kind: optionalEnum(search.kind, ['show', 'anime']),
  }),
  component: Calendar,
})

/** Days fetched around the visible week, so stepping a day rarely waits on the network. */
const LOOK_BEHIND = 7
const LOOK_AHEAD = 13
const VIEW_KEY = 'calendar.view'

function savedView(): CalendarView | null {
  try {
    const value = localStorage.getItem(VIEW_KEY)
    return value === 'week' || value === 'month' || value === 'missed'
      ? value
      : null
  } catch {
    return null // storage blocked: the default view it is
  }
}

function saveView(view: CalendarView) {
  try {
    localStorage.setItem(VIEW_KEY, view)
  } catch {
    // storage blocked: the choice lasts this visit only
  }
}

/** Below `lg` the month's agenda sits under the grid, so a tapped day opens as a sheet. */
const wide = () =>
  typeof window !== 'undefined' &&
  window.matchMedia('(min-width: 64rem)').matches

function Calendar() {
  const shell = useAppShell()
  const search = Route.useSearch()
  const navigate = useNavigate({ from: Route.fullPath })
  const [view, setView] = createSignal<CalendarView>(search().view ?? 'week')
  const [today, setToday] = createSignal<string | null>(null)
  const [start, setStart] = createSignal('')
  const [month, setMonth] = createSignal('')
  const [selected, setSelected] = createSignal('')
  const [entries, setEntries] = createSignal<CalendarEntry[]>([])
  const [loaded, setLoaded] = createSignal<{ first: string; last: string }>()
  const [loading, setLoading] = createSignal(true)
  const [problem, setProblem] = createSignal<string | null>(null)
  const [pending, setPending] = createSignal<ReadonlySet<string>>(new Set())
  const [openKey, setOpenKey] = createSignal<string | null>(null)
  const [dayOpen, setDayOpen] = createSignal<string | null>(null)
  let opened: CalendarEntry | undefined
  let request = 0
  let content: HTMLDivElement | undefined

  const filter = createMemo<CalendarFilter>(() => ({
    hideWatched: search().hide === 'watched',
    only: search().only,
    kind: search().kind,
  }))

  /** Week view paging: the moved week slides in from the side it came from. */
  function slide(direction: number) {
    if (content && direction !== 0 && view() === 'week')
      void slideIn(content, direction > 0 ? 1 : -1)
  }

  const weekDays = createMemo(() => (start() ? daysFrom(start()) : []))
  const grid = createMemo(() => (month() ? monthGrid(month()) : []))
  const visible = () => (view() === 'week' ? weekDays() : grid())
  const shown = createMemo(() => applyFilter(entries(), filter()))
  const byDay = createMemo(() => groupByDay(shown(), visible()))
  const missed = createMemo(() =>
    view() === 'missed'
      ? catchUp(
          applyFilter(entries(), { ...filter(), hideWatched: false }),
          new Date(),
        )
      : [],
  )
  const missedCount = () =>
    missed().reduce((sum, show) => sum + show.episodes.length, 0)
  const empty = createMemo(
    () =>
      !loading() &&
      view() !== 'missed' &&
      [...byDay().values()].every((list) => list.length === 0),
  )
  /** The open sheet's entry, live: a tick in the sheet shows at once. */
  const openEntry = createMemo(() => {
    const key = openKey()
    if (!key) return undefined
    return entries().find((entry) => entryKey(entry) === key) ?? opened
  })
  // WEB-011: the sheets stay mounted on their last value while their exit plays.
  const shownDay = lastShown(dayOpen)
  const shownEntry = lastShown(openEntry)

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
      if (event.defaultPrevented || openKey() || dayOpen()) return
      const target = event.target as HTMLElement | null
      // Fields keep their keys, the view switch's radios included; the day tabs move their
      // own selection with the arrows.
      if (
        target?.closest(
          'input:not([type=checkbox]), textarea, select, [role=tablist], [role=radiogroup]',
        )
      )
        return
      if (target?.isContentEditable) return
      const key = event.key
      if (view() === 'week') {
        if (key === 'ArrowLeft') step(-1)
        else if (key === 'ArrowRight') step(1)
        else if (key === 'PageUp') step(-7)
        else if (key === 'PageDown') step(7)
        else return
      } else if (view() === 'month') {
        if (key === 'ArrowLeft') moveDay(-1)
        else if (key === 'ArrowRight') moveDay(1)
        else if (key === 'PageUp') changeMonth(-1)
        else if (key === 'PageDown') changeMonth(1)
        else return
      } else return
      event.preventDefault()
    }
    window.addEventListener('keydown', onKey)
    onCleanup(() => window.removeEventListener('keydown', onKey))
  })

  // What the current view needs loaded: the week with margin, the month grid, or the weeks
  // just past for Missed.
  const wanted = createMemo(
    () => {
      if (view() === 'missed') {
        const now = today()
        if (!now) return null
        const first = addDays(now, -MISSED_DAYS)
        return { first, last: now, fetchFirst: first, fetchLast: now }
      }
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

  function switchView(next: CalendarView) {
    if (next === view()) return
    batch(() => {
      // Week and month open on the selected day.
      if (next === 'week') setStart(mondayOf(selected()))
      if (next === 'month') setMonth(monthOf(selected()))
      setView(next)
    })
    saveView(next)
    void navigate({
      search: (prev) => ({ ...prev, view: next }),
      replace: true,
    })
  }

  function setFilter(next: CalendarFilter) {
    void navigate({
      search: (prev) => ({
        ...prev,
        hide: next.hideWatched ? 'watched' : undefined,
        only: next.only,
        kind: next.kind,
      }),
      replace: true,
    })
  }

  /** Week view: by a day or a week; the selected day moves with it. */
  function step(delta: number) {
    if (!start()) return
    batch(() => {
      setStart((s) => addDays(s, delta))
      setSelected((s) => addDays(s, delta))
    })
    slide(delta)
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

  /** A tapped month day: selected everywhere, and opened as a sheet on phones. */
  function tapDay(day: string) {
    selectDay(day)
    if (!wide()) setDayOpen(day)
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

  function goTo(day: string) {
    const from = start()
    const to = mondayOf(day)
    batch(() => {
      setStart(to)
      setMonth(monthOf(day))
      setSelected(day)
    })
    slide(to === from ? 0 : to > from ? 1 : -1)
  }

  function goToday() {
    const now = today()
    if (now) goTo(now)
  }

  function openEpisode(entry: CalendarEntry) {
    opened = entry
    setOpenKey(entryKey(entry))
  }

  async function toggle(entry: CalendarEntry) {
    const key = entryKey(entry)
    if (pending().has(key)) return
    const watched = !entry.watched
    setProblem(null)
    setPending((set) => new Set(set).add(key))
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
    } finally {
      setPending((set) => {
        const next = new Set(set)
        next.delete(key)
        return next
      })
    }
  }

  const pendingSet = () => pending() as Set<string>

  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <div class="flex flex-wrap items-end justify-between gap-x-6 gap-y-3">
          <div>
            <h1 class="font-display text-4xl font-medium tracking-tight">
              Calendar
            </h1>
            <p class="mt-1 text-sm text-muted" aria-live="polite">
              <Show
                when={view() === 'week' && weekDays().length}
                fallback={
                  view() === 'missed'
                    ? 'Aired in the last four weeks, not watched yet'
                    : 'Your shows, by the day they air'
                }
              >
                {rangeLabel(weekDays()[0], weekDays()[6])}
              </Show>
            </p>
          </div>
          <CalendarToolbar
            view={view()}
            ready={!!today()}
            selected={selected()}
            filter={filter()}
            missedCount={missedCount()}
            onView={switchView}
            onStep={step}
            onToday={goToday}
            onGoTo={goTo}
            onFilter={setFilter}
          />
        </div>
        <FilterChips filter={filter()} onFilter={setFilter} />

        <Show when={problem()}>
          {(message) => (
            <Alert variant="destructive" class="mt-4">
              <AlertDescription>{message()}</AlertDescription>
            </Alert>
          )}
        </Show>

        <Show when={empty() && !problem()}>
          <div class={cn(cardClass, 'mt-6 p-6')}>
            <p class="font-display text-xl">
              Nothing from your shows airs this{' '}
              {view() === 'week' ? 'week' : 'month'}
              {entries().length > 0 ? ' with these filters' : ''}.
            </p>
            <p class="mt-1 text-sm text-muted">
              Shows you add, or mark as watching, appear here as their episodes
              air.
            </p>
            {/* UX-087: Search opens in place, on Shows. */}
            <Button
              variant="default"
              size="sm"
              class="mt-4"
              onClick={() => shell.openSearch('show')}
            >
              Find shows to add
            </Button>
          </div>
        </Show>

        <div ref={content} class="mt-6" aria-busy={loading()}>
          <Show
            when={today()}
            fallback={<p class="text-sm text-muted">Loading the calendar…</p>}
          >
            {(now) => (
              <Show
                when={view() !== 'missed'}
                fallback={
                  <Show
                    when={!loading()}
                    fallback={
                      <p class="text-sm text-muted">Looking back four weeks…</p>
                    }
                  >
                    <CatchUpList
                      shows={missed()}
                      pending={pendingSet()}
                      keyOf={entryKey}
                      onOpen={openEpisode}
                      onToggle={(entry) => void toggle(entry)}
                    />
                  </Show>
                }
              >
                <Show
                  when={view() === 'month'}
                  fallback={
                    <WeekGrid
                      days={weekDays()}
                      today={now()}
                      selected={selected()}
                      byDay={byDay()}
                      pending={pendingSet()}
                      keyOf={entryKey}
                      onSelect={setSelected}
                      onOpen={openEpisode}
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
                    pending={pendingSet()}
                    keyOf={entryKey}
                    onSelect={tapDay}
                    onMonth={changeMonth}
                    onOpen={openEpisode}
                    onToggle={(entry) => void toggle(entry)}
                  />
                </Show>
              </Show>
            )}
          </Show>
        </div>
      </div>

      <Show when={shownDay()}>
        {(day) => (
          <DaySheet
            open={dayOpen() !== null}
            day={day()}
            entries={byDay().get(day()) ?? []}
            pending={pendingSet()}
            keyOf={entryKey}
            onOpen={(entry) => {
              setDayOpen(null)
              openEpisode(entry)
            }}
            onToggle={(entry) => void toggle(entry)}
            onClose={() => setDayOpen(null)}
          />
        )}
      </Show>
      <Show when={shownEntry()}>
        {(entry) => (
          <CalendarEpisodeSheet
            open={openEntry() !== undefined}
            entry={entry()}
            pending={pending().has(entryKey(entry()))}
            onToggle={(next) => void toggle(next)}
            onClose={() => setOpenKey(null)}
          />
        )}
      </Show>
    </div>
  )
}
