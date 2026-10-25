import { OwlEmpty } from '../components/Brand'
import { createFileRoute } from '@tanstack/solid-router'
import { Index, Match, Show, Switch, createSignal, onMount } from 'solid-js'
import { Alert, AlertDescription, Button, Skeleton } from '~/components/ui'
import { Segmented } from '../components/Segmented'
import { EventSheet } from '../components/sports/EventSheet'
import { FavoritesView } from '../components/sports/FavoritesView'
import { FollowDialog } from '../components/sports/FollowDialog'
import { ScheduleView } from '../components/sports/ScheduleView'
import { localDayKey } from '../lib/calendar/model'
import { lastShown } from '../lib/presence'
import { optionalEnum, optionalString } from '../lib/search-params'
import { followKey, inStrip } from '../lib/sports/model'
import type {
  SportEntity,
  SportEvent,
  SportSettings,
} from '../lib/sports/model'
import { sportSettingsQuery } from '../lib/sports/query'
import { followSport, unfollowSport } from '../lib/sports/server'
import { viewerTimeZone } from '../lib/timezone'

const SPORTS_DB = 'https://www.thesportsdb.com'

// SPT-003: Sports on the web, a destination of its own and the only place sports appear
// (DESIGN.md §13a). Favorites and Schedule (`?view=schedule&date=`), an event sheet with
// "Where to watch", search to follow and the first-run picks. Scores and times depend on the
// viewer's clock and zone, so everything below the heading loads in the browser.
export const Route = createFileRoute('/_shell/app_/sports')({
  head: () => ({ meta: [{ title: 'Sports · Aaru' }] }),
  validateSearch: (search): { view?: 'schedule'; date?: string } => {
    const date = optionalString(search.date)
    return {
      view: optionalEnum(search.view, ['schedule']),
      date: date && /^\d{4}-\d{2}-\d{2}$/.test(date) ? date : undefined,
    }
  },
  loader: async ({ context: { queryClient } }) => ({
    // Without an answer the page says Sports are off, as the nav hides the tab.
    settings: await queryClient
      .query(sportSettingsQuery)
      .catch((): SportSettings | null => null),
  }),
  component: SportsPage,
})

type View = 'favorites' | 'schedule'

function SportsPage() {
  const loaded = Route.useLoaderData()
  const search = Route.useSearch()
  const navigate = Route.useNavigate()
  const [today, setToday] = createSignal<string | null>(null)
  const [timeZone, setTimeZone] = createSignal('UTC')
  const [searching, setSearching] = createSignal(false)
  const searched = lastShown(() => (searching() ? true : null))
  const [event, setEvent] = createSignal<SportEvent | null>(null)
  const shownEvent = lastShown(event)
  const [overrides, setOverrides] = createSignal(new Map<string, boolean>())
  const [busy, setBusy] = createSignal(new Set<string>())
  const [version, setVersion] = createSignal(0)
  const [problem, setProblem] = createSignal<string | null>(null)

  onMount(() => {
    setTimeZone(viewerTimeZone())
    setToday(localDayKey(new Date()))
  })

  const available = () => loaded().settings?.available === true
  const view = (): View => search().view ?? 'favorites'
  const date = (day: string) => {
    const chosen = search().date
    return chosen && inStrip(chosen, day) ? chosen : day
  }

  const isFollowing = (entity: SportEntity) =>
    overrides().get(followKey(entity)) ?? entity.following
  const isBusy = (entity: SportEntity) => busy().has(followKey(entity))

  async function toggle(entity: SportEntity) {
    const key = followKey(entity)
    if (busy().has(key)) return
    const follow = !isFollowing(entity)
    setBusy((set) => new Set(set).add(key))
    setProblem(null)
    try {
      if (follow)
        await followSport({ data: { kind: entity.kind, id: entity.id } })
      else await unfollowSport({ data: { kind: entity.kind, id: entity.id } })
      setOverrides((map) => new Map(map).set(key, follow))
      setVersion((v) => v + 1)
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : follow
            ? 'That was not followed.'
            : 'That was not unfollowed.',
      )
    } finally {
      setBusy((set) => {
        const next = new Set(set)
        next.delete(key)
        return next
      })
    }
  }

  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <div class="mt-6 flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 class="font-display text-4xl font-medium tracking-tight">
              Sports
            </h1>
            <p class="mt-2 text-muted">
              Live scores, fixtures and results for what you follow.
            </p>
          </div>
          <Show when={available()}>
            <Button variant="outline" onClick={() => setSearching(true)}>
              Follow
            </Button>
          </Show>
        </div>

        <Show
          when={available()}
          fallback={
            <OwlEmpty
              class="mt-12"
              pose="sleeping"
              title="Sports are off right now"
              body="Scores and fixtures are not available on this server."
            />
          }
        >
          <Segmented
            label="Sports view"
            class="mt-6"
            itemClass="px-4 py-1.5 text-sm"
            options={[
              { value: 'favorites', label: 'Favorites' },
              { value: 'schedule', label: 'Schedule' },
            ]}
            value={view()}
            onChange={(next) =>
              void navigate({
                search: next === 'schedule' ? { view: 'schedule' } : {},
                replace: true,
              })
            }
          />

          <Show when={problem()}>
            {(message) => (
              <Alert variant="destructive" class="mt-4">
                <AlertDescription>{message()}</AlertDescription>
              </Alert>
            )}
          </Show>

          <Show
            when={today()}
            fallback={
              <div class="mt-6 grid gap-4 md:grid-cols-2" aria-hidden="true">
                <Index each={[0, 1]}>
                  {() => <Skeleton class="h-44 rounded-card" />}
                </Index>
              </div>
            }
          >
            {(day) => (
              <Switch>
                <Match when={view() === 'favorites'}>
                  <FavoritesView
                    timeZone={timeZone()}
                    today={day()}
                    version={version()}
                    isFollowing={isFollowing}
                    isBusy={isBusy}
                    onToggle={(entity) => void toggle(entity)}
                    onOpenEvent={setEvent}
                    onSearch={() => setSearching(true)}
                  />
                </Match>
                <Match when={view() === 'schedule'}>
                  <ScheduleView
                    date={date(day())}
                    today={day()}
                    timeZone={timeZone()}
                    version={version()}
                    onDateChange={(next) =>
                      void navigate({
                        search: {
                          view: 'schedule',
                          date: next === day() ? undefined : next,
                        },
                        replace: true,
                        resetScroll: false,
                      })
                    }
                    onOpenEvent={setEvent}
                    onSearch={() => setSearching(true)}
                  />
                </Match>
              </Switch>
            )}
          </Show>
        </Show>

        <footer class="mt-16 border-t border-line pt-6 text-xs text-muted">
          Data:{' '}
          <a href={SPORTS_DB} rel="noopener" class="hover:underline">
            TheSportsDB
          </a>
        </footer>
      </div>

      {/* Mounted from the first open on, so closing plays the exit (WEB-011). */}
      <Show when={searched()}>
        <FollowDialog
          open={searching()}
          isFollowing={isFollowing}
          isBusy={isBusy}
          onToggle={(entity) => void toggle(entity)}
          toggleProblem={problem()}
          onClose={() => setSearching(false)}
        />
      </Show>
      <Show when={shownEvent()}>
        {(shown) => (
          <EventSheet
            event={shown()}
            open={event() !== null}
            timeZone={timeZone()}
            today={today() ?? localDayKey(new Date())}
            onClose={() => setEvent(null)}
          />
        )}
      </Show>
    </div>
  )
}
