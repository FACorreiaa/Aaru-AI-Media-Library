import { Link, createFileRoute, redirect } from '@tanstack/solid-router'
import { For, Show, createMemo, createSignal, onMount } from 'solid-js'
import { AppHeader } from '../components/AppHeader'
import { DiscoverRows } from '../components/DiscoverRows'
import { SearchPanel } from '../components/SearchPanel'
import { PlanCard } from '../components/PlanCard'
import { Alert } from '../components/ui/alert'
import { Button, buttonVariants } from '../components/ui/button'
import { cardClass } from '../components/ui/card'
import { Dialog } from '../components/ui/dialog'
import { cn } from '../lib/cn'
import {
  AiringCard,
  ContinueCard,
  Row,
  StartCard,
  UnfinishedCard,
} from '../components/HomeRows'
import {
  addDays,
  fetchWindow,
  localDayKey,
  withWatched,
} from '../lib/calendar/model'
import type { CalendarEntry } from '../lib/calendar/model'
import { getCalendar } from '../lib/calendar/server'
import {
  AIRING_DAYS,
  advance,
  airingBadge,
  countChips,
  markOnShelf,
  monthStrip,
  upcoming,
} from '../lib/home/model'
import type { ContinueEntry, DiscoverRow, UpNext } from '../lib/home/model'
import { getDiscover, getUpNext } from '../lib/home/server'
import { upsert } from '../lib/library/model'
import type { LibraryEntry } from '../lib/library/model'
import { getLibrary } from '../lib/library/server'
import { getLists } from '../lib/lists/server'
import type { ListSummary } from '../lib/lists/server'
import { getStats } from '../lib/recap/server'
import { offeredRecap, periodLabel } from '../lib/recap/model'
import { getSession } from '../lib/session/session'
import { listPendingPlans } from '../lib/plans/server'
import type { AgentPlan } from '../lib/plans/server'
import { setEpisode } from '../lib/title/server'

// APP-009 on the web: Home, the twin of the Apple apps' first tab. Continue watching and Start
// watching come with the page; the calendar row loads in the browser, which knows the
// viewer's "today", as do this month's stats, Discover's public rows (DISC-001) and the list
// chips, so a cold provider cache never holds the page. Each of those hides itself if it
// fails. Search opens in place and shares the library for its "On your shelf" marks.
export const Route = createFileRoute('/app')({
  head: () => ({ meta: [{ title: 'Home · Aaru' }] }),
  beforeLoad: async () => {
    const session = await getSession()
    if (!session.signedIn) throw redirect({ to: '/sign-in' })
    return { session }
  },
  loader: () => getUpNext(),
  component: Home,
})

function Home() {
  const loaded = Route.useLoaderData()
  const [continuing, setContinuing] = createSignal(loaded().continueWatching)
  const [starting, setStarting] = createSignal(loaded().startWatching)
  const [unfinished, setUnfinished] = createSignal(loaded().unfinished ?? [])
  const [counts, setCounts] = createSignal(loaded().counts)
  const [strip, setStrip] = createSignal<string[]>([])
  const [lists, setLists] = createSignal<ListSummary[] | null>(null)
  const [airings, setAirings] = createSignal<CalendarEntry[]>([])
  const [now, setNow] = createSignal<Date | null>(null)
  const [airingsReady, setAiringsReady] = createSignal(false)
  const [busy, setBusy] = createSignal<ReadonlySet<string>>(new Set())
  const [problem, setProblem] = createSignal<string | null>(null)
  const [discover, setDiscover] = createSignal<DiscoverRow[]>([])
  const [discoverReady, setDiscoverReady] = createSignal(false)
  const [searchOpened, setSearchOpened] = createSignal(false)
  const [entries, setEntries] = createSignal<LibraryEntry[]>([])
  const [plans, setPlans] = createSignal<AgentPlan[]>([])
  let dialog: HTMLDialogElement | undefined
  let libraryRequested = false

  function openSearch() {
    setSearchOpened(true)
    dialog?.showModal()
    loadLibrary()
  }

  function loadLibrary() {
    if (libraryRequested) return
    libraryRequested = true
    getLibrary()
      .then((library) => {
        // Anything added while it loaded is already on the server's answer, or kept here.
        setEntries((recent) => recent.reduce(upsert, library))
      })
      .catch(() => {
        // Adding still works; titles just lack their "On your shelf" mark. Try again later.
        libraryRequested = false
      })
  }

  function showUpNext(fresh: UpNext) {
    setContinuing(fresh.continueWatching)
    setStarting(fresh.startWatching)
    setUnfinished(fresh.unfinished ?? [])
    setCounts(fresh.counts)
  }

  /** A title added from Search or a Discover row: mark it on the shelf and refresh the rows. */
  async function added(entry: LibraryEntry) {
    setProblem(null)
    setEntries((current) => upsert(current, entry))
    setDiscover((rows) => markOnShelf(rows, entry))
    try {
      showUpNext(await getUpNext())
    } catch {
      // The add landed; the rows catch up on the next visit.
    }
  }

  /** This month in numbers, in the viewer's time zone. A failure just leaves the strip out. */
  async function loadStrip(current: Date) {
    try {
      const stats = await getStats({
        data: {
          year: current.getFullYear(),
          month: current.getMonth() + 1,
          tz: Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
        },
      })
      setStrip(monthStrip(stats))
    } catch {
      setStrip([])
    }
  }

  /** Agent requests waiting for the user (OUT-004), pinned above everything else. */
  async function loadPlans() {
    try {
      setPlans(await listPendingPlans())
    } catch {
      // The requests stay on the server; the next visit shows them.
    }
  }

  async function loadDiscover() {
    try {
      setDiscover(await getDiscover())
    } catch {
      // Discover is extra: the user's own rows stand without it.
    } finally {
      setDiscoverReady(true)
    }
  }

  async function loadLists() {
    try {
      setLists(await getLists())
    } catch {
      setLists(null)
    }
  }

  onMount(async () => {
    const current = new Date()
    setNow(current)
    const today = localDayKey(current)
    void loadStrip(current)
    void loadDiscover()
    void loadPlans()
    void loadLists()
    loadLibrary()
    try {
      setAirings(
        await getCalendar({
          data: fetchWindow(today, addDays(today, AIRING_DAYS - 1)),
        }),
      )
    } catch (err) {
      setProblem(
        err instanceof Error
          ? err.message
          : 'The calendar could not be loaded.',
      )
    } finally {
      setAiringsReady(true)
    }
  })

  const nextAirings = createMemo(() => {
    const current = now()
    return current ? upcoming(airings(), current) : []
  })

  const recap = createMemo(() => {
    const current = now()
    return current ? offeredRecap(current) : null
  })

  const badgeFor = (entry: CalendarEntry) => {
    const current = now()
    return current ? airingBadge(entry, current) : null
  }

  const chips = createMemo(() => countChips(counts()))

  const empty = () =>
    continuing().length === 0 &&
    starting().length === 0 &&
    unfinished().length === 0 &&
    airingsReady() &&
    nextAirings().length === 0

  function setBusyFor(id: string, on: boolean) {
    setBusy((current) => {
      const next = new Set(current)
      if (on) next.add(id)
      else next.delete(id)
      return next
    })
  }

  /** Marks the card's next episode watched: the card advances at once, the server's answer
   * then replaces the guess, and a failed write puts the card back where it was. */
  async function markWatched(entry: ContinueEntry) {
    const id = entry.libraryItemId
    if (busy().has(id)) return
    const index = continuing().findIndex((r) => r.libraryItemId === id)
    setBusyFor(id, true)
    setProblem(null)
    setContinuing((rows) => advance(rows, entry))
    try {
      await setEpisode({
        data: {
          id,
          season: entry.next.season,
          episode: entry.next.number,
          watched: true,
        },
      })
    } catch (err) {
      setContinuing((rows) => {
        const rest = rows.filter((r) => r.libraryItemId !== id)
        rest.splice(Math.max(0, index), 0, entry)
        return rest
      })
      setProblem(
        err instanceof Error ? err.message : 'The episode was not marked.',
      )
      setBusyFor(id, false)
      return
    }
    const match = airings().find(
      (a) =>
        a.libraryItemId === id &&
        a.season === entry.next.season &&
        a.number === entry.next.number,
    )
    if (match) setAirings((rows) => withWatched(rows, match, true))
    try {
      showUpNext(await getUpNext())
    } catch {
      // The write landed; the optimistic card stands until the next visit.
    } finally {
      setBusyFor(id, false)
    }
  }

  return (
    <div class="min-h-[100dvh]">
      <AppHeader onSearch={openSearch} />
      <main class="mx-auto max-w-6xl px-4 pb-16 md:px-8">
        <h1 class="mt-6 font-display text-4xl font-medium tracking-tight">
          Home
        </h1>

        <Show when={problem()}>
          {(message) => <Alert class="mt-4">{message()}</Alert>}
        </Show>

        <Show when={plans().length > 0}>
          <section class="mt-6" aria-label="Waiting for you">
            <h2 class="font-display text-2xl font-medium">Waiting for you</h2>
            <div class="mt-3 grid gap-3 md:grid-cols-2">
              <For each={plans()}>
                {(plan) => (
                  <PlanCard
                    plan={plan}
                    onDecided={(decided) => {
                      if (decided.status === 'applied')
                        void getUpNext().then(showUpNext, () => {})
                    }}
                  />
                )}
              </For>
            </div>
          </section>
        </Show>

        <Show when={strip().length > 0}>
          <Link
            to="/app/insights"
            class={cn(
              cardClass,
              'mt-6 flex items-center justify-between gap-4 px-5 py-4 hover:text-accent',
            )}
          >
            <span class="min-w-0">
              <span class="block text-sm text-muted">This month</span>
              <span class="font-medium">{strip().join(' · ')}</span>
            </span>
            <span class="shrink-0 text-sm font-semibold text-accent">
              Insights
            </span>
          </Link>
        </Show>

        <Show when={chips().length > 0}>
          <nav
            aria-label="Your shelf by status"
            class="mt-4 flex flex-wrap gap-2"
          >
            <For each={chips()}>
              {(chip) => (
                <Link
                  to="/app/library"
                  search={{ status: chip.status }}
                  class="rounded-full border border-line px-4 py-1.5 text-sm font-medium hover:bg-surface"
                >
                  {chip.label}{' '}
                  <span class="text-muted tabular-nums">{chip.count}</span>
                </Link>
              )}
            </For>
          </nav>
        </Show>

        <Show when={recap()}>
          {(period) => (
            <Link
              to="/app/recap"
              search={period()}
              class="rise mt-6 flex items-center justify-between gap-4 rounded-card bg-ink p-5 text-paper"
            >
              <span>
                <span class="block text-sm opacity-80">
                  Your recap is ready
                </span>
                <span class="font-display text-2xl font-medium">
                  {period().month
                    ? periodLabel(period())
                    : `${period().year} in Aaru`}
                </span>
              </span>
              <span class="shrink-0 rounded-full bg-paper px-4 py-2 text-sm font-semibold text-ink">
                Play
              </span>
            </Link>
          )}
        </Show>

        <Show when={continuing().length > 0}>
          <Row title="Continue watching">
            <For each={continuing()}>
              {(entry) => (
                <ContinueCard
                  entry={entry}
                  busy={busy().has(entry.libraryItemId)}
                  onWatched={markWatched}
                />
              )}
            </For>
          </Row>
        </Show>

        <Show when={nextAirings().length > 0}>
          <Row
            title="Coming up"
            action={
              <Link
                to="/app/week"
                class="text-sm font-medium text-accent hover:underline"
              >
                See calendar
              </Link>
            }
          >
            <For each={nextAirings()}>
              {(entry) => <AiringCard entry={entry} when={badgeFor(entry)} />}
            </For>
          </Row>
        </Show>

        <Show when={starting().length > 0}>
          <Row title="Start watching">
            <For each={starting()}>
              {(entry) => <StartCard entry={entry} />}
            </For>
          </Row>
        </Show>

        <Show when={unfinished().length > 0}>
          <Row title="Unfinished business">
            <For each={unfinished()}>
              {(entry) => <UnfinishedCard entry={entry} now={now()} />}
            </For>
          </Row>
        </Show>

        <Show when={lists()}>
          {(all) => (
            <section class="mt-10" aria-labelledby="home-lists">
              <h2
                id="home-lists"
                class="font-display text-2xl font-medium tracking-tight"
              >
                Lists
              </h2>
              <div class="mt-4 flex flex-wrap gap-2">
                <For each={all()}>
                  {(list) => (
                    <Link
                      to="/app/lists/$id"
                      params={{ id: list.id }}
                      class="rounded-full bg-surface px-4 py-2 text-sm font-medium hover:text-accent"
                    >
                      {list.name}{' '}
                      <span class="text-muted tabular-nums">
                        {list.itemCount}
                      </span>
                    </Link>
                  )}
                </For>
                <Link
                  to="/app/lists"
                  class="rounded-full border border-dashed border-line px-4 py-2 text-sm font-medium text-accent hover:bg-surface"
                >
                  New list
                </Link>
              </div>
            </section>
          )}
        </Show>

        <Show when={empty() && (!discoverReady() || discover().length > 0)}>
          <div
            class={cn(
              cardClass,
              'mt-8 flex flex-wrap items-center justify-between gap-4 p-5',
            )}
          >
            <div>
              <h2 class="font-display text-xl font-medium">
                Add a show to see what’s next
              </h2>
              <p class="mt-1 text-sm text-muted">
                Pick from the rows below, browse Discover, or search. What you
                watch and what airs next land here.
              </p>
            </div>
            <div class="flex items-center gap-2">
              <Link
                to="/app/discover"
                class="rounded-full border border-line px-5 py-2 text-sm font-semibold hover:bg-paper"
              >
                Discover
              </Link>
              <button
                type="button"
                onClick={openSearch}
                class="rounded-full bg-accent px-5 py-2 text-sm font-semibold text-on-accent"
              >
                Search
              </button>
            </div>
          </div>
        </Show>

        <DiscoverRows
          rows={discover()}
          onRowsChange={setDiscover}
          today={now() ? localDayKey(now() as Date) : null}
          onAdded={(entry) => void added(entry)}
          onProblem={setProblem}
        />

        <Show when={empty() && discoverReady() && discover().length === 0}>
          <div class="mx-auto mt-16 max-w-sm text-center">
            <h2 class="font-display text-2xl font-medium">
              Add a show to see what’s next
            </h2>
            <p class="mt-2 text-muted">
              Shows you are watching, what you want to start, and what airs this
              week land here.
            </p>
            <div class="mt-6 flex items-center justify-center gap-3">
              <Link
                to="/app/discover"
                class={buttonVariants({ variant: 'primary', size: 'lg' })}
              >
                Discover
              </Link>
              <Button variant="quiet" size="lg" onClick={openSearch}>
                Search
              </Button>
            </div>
          </div>
        </Show>
      </main>

      <Dialog
        ref={dialog}
        aria-label="Search"
        class="w-[min(40rem,calc(100vw-2rem))]"
      >
        <Show when={searchOpened()}>
          <SearchPanel
            entries={entries()}
            onAdded={(entry) => void added(entry)}
            onClose={() => dialog?.close()}
          />
        </Show>
      </Dialog>
    </div>
  )
}
