import { Link, createFileRoute, redirect } from '@tanstack/solid-router'
import { For, Show, createMemo, createSignal, onMount } from 'solid-js'
import { AddToListDialog } from '../components/AddToListDialog'
import { AppHeader } from '../components/AppHeader'
import {
  AiringCard,
  ContinueCard,
  DiscoverCard,
  Row,
  StartCard,
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
  markAdded,
  upcoming,
} from '../lib/home/model'
import type { ContinueEntry, DiscoverRow } from '../lib/home/model'
import { getDiscover, getUpNext } from '../lib/home/server'
import { hitKey } from '../lib/library/model'
import type { CatalogHit, LibraryStatus } from '../lib/library/model'
import { addToLibrary } from '../lib/library/server'
import { offeredRecap, periodLabel } from '../lib/recap/model'
import { getSession } from '../lib/session/session'
import { setEpisode } from '../lib/title/server'

// APP-009 on the web: Home, the twin of the Apple apps' first tab. Continue watching and Start
// watching come with the page; the calendar row loads in the browser, which knows the
// viewer's "today". Discover's public rows (DISC-001) load in the browser too, so a cold
// provider cache never holds the page.
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
  const [airings, setAirings] = createSignal<CalendarEntry[]>([])
  const [now, setNow] = createSignal<Date | null>(null)
  const [airingsReady, setAiringsReady] = createSignal(false)
  const [busy, setBusy] = createSignal<ReadonlySet<string>>(new Set())
  const [problem, setProblem] = createSignal<string | null>(null)
  const [discover, setDiscover] = createSignal<DiscoverRow[]>([])
  const [discoverReady, setDiscoverReady] = createSignal(false)
  const [adding, setAdding] = createSignal<ReadonlySet<string>>(new Set())
  const [listTarget, setListTarget] = createSignal<CatalogHit | null>(null)

  onMount(async () => {
    try {
      setDiscover(await getDiscover())
    } catch {
      // Discover is extra: the user's own rows stand without it.
    } finally {
      setDiscoverReady(true)
    }
  })

  onMount(async () => {
    const current = new Date()
    setNow(current)
    const today = localDayKey(current)
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

  const empty = () =>
    continuing().length === 0 &&
    starting().length === 0 &&
    airingsReady() &&
    nextAirings().length === 0

  /** Adds a Discover hit with a status; its cards then link to the new item. */
  async function add(hit: CatalogHit, status: LibraryStatus) {
    const key = hitKey(hit)
    if (adding().has(key)) return
    setAdding((current) => new Set([...current, key]))
    setProblem(null)
    try {
      const entry = await addToLibrary({
        data: {
          type: hit.type,
          ids: hit.ids,
          title: hit.title,
          year: hit.year,
          status,
        },
      })
      setDiscover((rows) => markAdded(rows, key, entry.id))
    } catch (err) {
      setProblem(
        err instanceof Error ? err.message : `${hit.title} could not be added.`,
      )
    } finally {
      setAdding((current) => {
        const next = new Set(current)
        next.delete(key)
        return next
      })
    }
  }

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
      const fresh = await getUpNext()
      setContinuing(fresh.continueWatching)
      setStarting(fresh.startWatching)
    } catch {
      // The write landed; the optimistic card stands until the next visit.
    } finally {
      setBusyFor(id, false)
    }
  }

  return (
    <div class="min-h-[100dvh]">
      <AppHeader />
      <main class="mx-auto max-w-6xl px-4 pb-16 md:px-8">
        <h1 class="mt-6 font-display text-4xl font-medium tracking-tight">
          Home
        </h1>

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

        <Show when={recap()}>
          {(period) => (
            <Link
              to="/app/recap"
              search={period()}
              class="rise mt-6 flex items-center justify-between gap-4 rounded-[20px] bg-ink p-5 text-paper"
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

        <Show when={empty() && (!discoverReady() || discover().length > 0)}>
          <div class="mt-8 flex flex-wrap items-center justify-between gap-4 rounded-[20px] bg-surface p-5">
            <div>
              <h2 class="font-display text-xl font-medium">
                Add a show to see what’s next
              </h2>
              <p class="mt-1 text-sm text-muted">
                Pick from the rows below or search. What you watch and what airs
                next land here.
              </p>
            </div>
            <Link
              to="/app/library"
              search={{ search: true }}
              class="rounded-full bg-accent px-5 py-2 text-sm font-semibold text-on-accent"
            >
              Search
            </Link>
          </div>
        </Show>

        <For each={discover()}>
          {(row) => (
            <Row title={row.title}>
              <For each={row.items}>
                {(hit) => (
                  <DiscoverCard
                    hit={hit}
                    rowId={row.id}
                    adding={adding().has(hitKey(hit))}
                    onAdd={(status) => void add(hit, status)}
                    onList={() => setListTarget(hit)}
                  />
                )}
              </For>
            </Row>
          )}
        </For>

        <Show when={empty() && discoverReady() && discover().length === 0}>
          <div class="mx-auto mt-24 max-w-sm text-center">
            <h2 class="font-display text-2xl font-medium">
              Add a show to see what’s next
            </h2>
            <p class="mt-2 text-muted">
              Shows you are watching, what you want to start, and what airs this
              week land here.
            </p>
            <Link
              to="/app/library"
              search={{ search: true }}
              class="mt-6 inline-block rounded-full bg-accent px-6 py-3 font-semibold text-on-accent"
            >
              Search
            </Link>
          </div>
        </Show>
      </main>
      <Show when={listTarget()}>
        {(hit) => (
          <AddToListDialog
            mediaRef={{
              type: hit().type,
              ids: hit().ids,
              title: hit().title,
              year: hit().year,
            }}
            titleName={hit().title}
            onClose={() => setListTarget(null)}
          />
        )}
      </Show>
    </div>
  )
}
