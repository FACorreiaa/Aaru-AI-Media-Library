import { Link, createFileRoute, redirect } from '@tanstack/solid-router'
import {
  Show,
  batch,
  createEffect,
  createMemo,
  createSignal,
  on,
  onCleanup,
  onMount,
} from 'solid-js'
import { Wordmark } from '../components/Brand'
import { WeekGrid } from '../components/WeekGrid'
import {
  addDays,
  daysFrom,
  fetchWindow,
  groupByDay,
  localDayKey,
  mondayOf,
  rangeLabel,
  withWatched,
} from '../lib/calendar/model'
import type { CalendarEntry } from '../lib/calendar/model'
import { getCalendar } from '../lib/calendar/server'
import { getSession } from '../lib/session/session'
import { setEpisode } from '../lib/title/server'

// APP-010 on the web: what airs this week from the user's own shows. Rendered in the browser:
// "today" and every day boundary are the viewer's, not the Worker's (UTC).
export const Route = createFileRoute('/app_/week')({
  head: () => ({ meta: [{ title: 'This week · Aaru' }] }),
  beforeLoad: async () => {
    const session = await getSession()
    if (!session.signedIn) throw redirect({ to: '/sign-in' })
  },
  component: Week,
})

/** Days fetched around the visible week, so stepping a day rarely waits on the network. */
const LOOK_BEHIND = 7
const LOOK_AHEAD = 13

function Week() {
  const [today, setToday] = createSignal<string | null>(null)
  const [start, setStart] = createSignal('')
  const [selected, setSelected] = createSignal('')
  const [entries, setEntries] = createSignal<CalendarEntry[]>([])
  const [loaded, setLoaded] = createSignal<{ first: string; last: string }>()
  const [loading, setLoading] = createSignal(true)
  const [problem, setProblem] = createSignal<string | null>(null)
  let request = 0

  const days = createMemo(() => (start() ? daysFrom(start()) : []))
  const byDay = createMemo(() => groupByDay(entries(), days()))
  const empty = createMemo(
    () =>
      !loading() && [...byDay().values()].every((list) => list.length === 0),
  )

  onMount(() => {
    const now = localDayKey(new Date())
    // Together: the grid renders once `today` is set and needs the other two with it.
    batch(() => {
      setToday(now)
      setStart(mondayOf(now))
      setSelected(now)
    })

    const onKey = (event: KeyboardEvent) => {
      if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey)
        return
      const target = event.target as HTMLElement | null
      if (target?.closest('input:not([type=checkbox]), textarea, select'))
        return
      if (target?.isContentEditable) return
      if (event.key === 'ArrowLeft') step(-1)
      else if (event.key === 'ArrowRight') step(1)
      else return
      event.preventDefault()
    }
    window.addEventListener('keydown', onKey)
    onCleanup(() => window.removeEventListener('keydown', onKey))
  })

  // Fetch when the visible week leaves the loaded range.
  createEffect(
    on(start, (first) => {
      if (!first) return
      const last = addDays(first, 6)
      const have = loaded()
      if (have && have.first <= first && last <= have.last) return
      void load(addDays(first, -LOOK_BEHIND), addDays(first, LOOK_AHEAD))
    }),
  )

  async function load(first: string, last: string) {
    const mine = ++request
    setLoading(true)
    setProblem(null)
    try {
      const items = await getCalendar({ data: fetchWindow(first, last) })
      if (mine !== request) return
      setEntries(items)
      setLoaded({ first, last })
    } catch (err) {
      if (mine !== request) return
      setProblem(
        err instanceof Error ? err.message : 'The week could not be loaded.',
      )
    } finally {
      if (mine === request) setLoading(false)
    }
  }

  function step(delta: number) {
    if (!start()) return
    batch(() => {
      setStart((s) => addDays(s, delta))
      setSelected((s) => addDays(s, delta))
    })
  }

  function goToday() {
    const now = today()
    if (!now) return
    batch(() => {
      setStart(mondayOf(now))
      setSelected(now)
    })
  }

  function select(day: string) {
    setSelected(day)
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
              This week
            </h1>
            <p class="mt-1 text-sm text-muted" aria-live="polite">
              <Show when={days().length}>
                {rangeLabel(days()[0], days()[6])}
              </Show>
            </p>
          </div>
          <nav class="flex items-center gap-2" aria-label="Week">
            <button
              type="button"
              class={button}
              disabled={!today()}
              onClick={() => step(-1)}
              aria-keyshortcuts="ArrowLeft"
            >
              <span aria-hidden="true">‹ </span>Previous day
            </button>
            <button
              type="button"
              class={button}
              disabled={!today()}
              onClick={goToday}
            >
              Today
            </button>
            <button
              type="button"
              class={button}
              disabled={!today()}
              onClick={() => step(1)}
              aria-keyshortcuts="ArrowRight"
            >
              Next day<span aria-hidden="true"> ›</span>
            </button>
          </nav>
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
              Nothing from your shows airs this week.
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
            fallback={<p class="text-sm text-muted">Loading the week…</p>}
          >
            {(now) => (
              <WeekGrid
                days={days()}
                today={now()}
                selected={selected()}
                byDay={byDay()}
                onSelect={select}
                onToggle={(entry) => void toggle(entry)}
              />
            )}
          </Show>
        </div>
      </main>
    </div>
  )
}
