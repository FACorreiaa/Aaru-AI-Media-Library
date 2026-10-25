import {
  For,
  Index,
  Match,
  Show,
  Switch,
  createEffect,
  createSignal,
  on,
  onMount,
} from 'solid-js'
import {
  Alert,
  AlertDescription,
  Button,
  Card,
  Skeleton,
} from '~/components/ui'
import { cn } from '~/lib/utils'
import {
  KIND_LABEL,
  clockLabel,
  entityLine,
  favoritesState,
  followKey,
  isCard,
} from '../../lib/sports/model'
import type {
  LiveState,
  SportEntity,
  SportEvent,
  SportFavorite,
  SportFavorites,
  SportSide,
} from '../../lib/sports/model'
import { createNearLive } from '../../lib/sports/near-live'
import { getSportFavorites } from '../../lib/sports/server'
import { EventRow } from './EventRow'
import { SportBadge } from './SportBadge'
import { SuggestedPicks } from './SuggestedPicks'

const UNAVAILABLE = 'Sports aren’t answering right now.'

/**
 * SPT-003's Favorites: one card per follow, in follow order. A live game first (both sides, the
 * score large, the clock beside a live dot), else the next fixture in the viewer's day and
 * time, then the last result in muted. A follow still being fetched holds its place with a
 * placeholder and fills in on its own. With nothing followed, the first-run picks.
 */
export function FavoritesView(props: {
  timeZone: string
  today: string
  /** Bumped by the page after a follow or unfollow: Favorites asks again. */
  version: number
  isFollowing: (entity: SportEntity) => boolean
  isBusy: (entity: SportEntity) => boolean
  onToggle: (entity: SportEntity) => void
  onOpenEvent: (event: SportEvent) => void
  onSearch: () => void
}) {
  const [favorites, setFavorites] = createSignal<SportFavorites | null>(null)
  const [problem, setProblem] = createSignal<string | null>(null)
  let latest = 0

  async function load(quiet: boolean): Promise<LiveState | null> {
    const request = ++latest
    if (!quiet) setProblem(null)
    try {
      const found = await getSportFavorites()
      if (request !== latest) return null
      setFavorites(found)
      setProblem(found.unavailable ? UNAVAILABLE : null)
      return favoritesState(found)
    } catch (error) {
      if (request !== latest) return null
      // A quiet refresh that fails keeps what is on screen and its rhythm.
      const shown = favorites()
      if (!quiet || !shown)
        setProblem(
          error instanceof Error
            ? error.message
            : 'Your favorites could not be loaded.',
        )
      return shown ? favoritesState(shown) : null
    }
  }

  const nearLive = createNearLive(() => load(true))
  onMount(() => void load(false).then(nearLive.plan))
  createEffect(
    on(
      () => props.version,
      () => {
        nearLive.reset()
        void load(true).then(nearLive.plan)
      },
      { defer: true },
    ),
  )

  // An unfollow leaves at once; the next answer agrees.
  const shown = () =>
    (favorites()?.items ?? []).filter((f) => props.isFollowing(f.entity))

  return (
    <div class="mt-6">
      <Show when={problem()}>
        {(message) => (
          <Alert variant="destructive" class="mb-4">
            <AlertDescription>{message()}</AlertDescription>
          </Alert>
        )}
      </Show>
      <Switch>
        <Match when={favorites() === null && !problem()}>
          <div class="grid gap-4 md:grid-cols-2 2xl:grid-cols-3">
            <Index each={[0, 1, 2]}>
              {() => <Skeleton class="h-44 rounded-card" />}
            </Index>
          </div>
        </Match>
        <Match when={favorites() && shown().length === 0}>
          <SuggestedPicks
            isFollowing={props.isFollowing}
            isBusy={props.isBusy}
            onToggle={props.onToggle}
            onSearch={props.onSearch}
          />
        </Match>
        <Match when={shown().length > 0}>
          <ul class="grid gap-4 md:grid-cols-2 2xl:grid-cols-3">
            <For each={shown()}>
              {(favorite) => (
                <li>
                  <FavoriteCard
                    favorite={favorite}
                    timeZone={props.timeZone}
                    today={props.today}
                    busy={props.isBusy(favorite.entity)}
                    onUnfollow={() => props.onToggle(favorite.entity)}
                    onOpenEvent={props.onOpenEvent}
                  />
                </li>
              )}
            </For>
          </ul>
        </Match>
      </Switch>
    </div>
  )
}

function FavoriteCard(props: {
  favorite: SportFavorite
  timeZone: string
  today: string
  busy: boolean
  onUnfollow: () => void
  onOpenEvent: (event: SportEvent) => void
}) {
  const entity = () => props.favorite.entity
  const empty = () =>
    props.favorite.live.length === 0 &&
    !props.favorite.next &&
    !props.favorite.last
  return (
    <Card
      class="h-full gap-0 py-4"
      aria-labelledby={`sport-${followKey(entity()).replace(':', '-')}`}
    >
      <div class="flex items-center gap-3 px-4">
        <SportBadge
          url={entity().badgeUrl}
          name={entity().name}
          class="size-9"
        />
        <div class="min-w-0 flex-1">
          <h2
            id={`sport-${followKey(entity()).replace(':', '-')}`}
            class="truncate font-display text-lg leading-tight font-medium"
          >
            {entity().name}
          </h2>
          <p class="truncate text-xs text-muted">
            {KIND_LABEL[entity().kind]} · {entityLine(entity())}
          </p>
        </div>
        <Button
          variant="ghost"
          size="xs"
          disabled={props.busy}
          aria-label={`Unfollow ${entity().name}`}
          onClick={() => props.onUnfollow()}
        >
          Unfollow
        </Button>
      </div>

      <div class="mt-3 flex flex-col gap-1 px-2">
        <Switch>
          <Match when={props.favorite.pending && empty()}>
            <div class="flex flex-col gap-2 px-2" aria-label="Loading">
              <Skeleton class="h-12 rounded-row" />
              <Skeleton class="h-12 rounded-row" />
            </div>
          </Match>
          <Match when={props.favorite.live.length > 0}>
            <For each={props.favorite.live}>
              {(event) => <LiveGame event={event} onOpen={props.onOpenEvent} />}
            </For>
          </Match>
          <Match when={props.favorite.next}>
            {(next) => (
              <>
                <p class="eyebrow px-2 pt-1">Next</p>
                <EventRow
                  event={next()}
                  timeZone={props.timeZone}
                  today={props.today}
                  showDay
                  onOpen={props.onOpenEvent}
                />
              </>
            )}
          </Match>
        </Switch>
        <Show when={props.favorite.last}>
          {(last) => (
            <>
              <p class="eyebrow px-2 pt-2">Last</p>
              <EventRow
                event={last()}
                timeZone={props.timeZone}
                today={props.today}
                showDay
                muted
                onOpen={props.onOpenEvent}
              />
            </>
          )}
        </Show>
        <Show when={!props.favorite.pending && empty()}>
          <p class="px-2 py-2 text-sm text-muted">Nothing scheduled.</p>
        </Show>
      </div>
    </Card>
  )
}

/** A game on now: both sides, the score large in the display face, the clock by a live dot. */
function LiveGame(props: {
  event: SportEvent
  onOpen: (event: SportEvent) => void
}) {
  const clock = () => clockLabel(props.event.progress)
  return (
    <Button
      variant="ghost"
      size="bare"
      onClick={() => props.onOpen(props.event)}
      aria-label={`${props.event.name}, live${clock() ? `, ${clock()}` : ''}${
        props.event.home?.score !== undefined &&
        props.event.away?.score !== undefined
          ? `, ${props.event.home.score}–${props.event.away.score}`
          : ''
      }`}
      class={cn(
        'flex w-full flex-col gap-2 rounded-panel border-l-2 px-3 py-2 text-left font-normal text-ink hover:bg-surface hover:text-ink',
        props.event.isFavorite ? 'border-gold' : 'border-transparent',
      )}
    >
      <span class="flex items-center gap-1.5 text-xs font-semibold text-accent tabular-nums">
        <span aria-hidden="true" class="size-1.5 rounded-full bg-accent" />
        Live
        <Show when={clock()}>{(c) => <span>· {c()}</span>}</Show>
      </span>
      <Show
        when={!isCard(props.event)}
        fallback={<span class="text-sm font-medium">{props.event.name}</span>}
      >
        <span class="grid w-full grid-cols-[1fr_auto_1fr] items-center gap-3">
          <LiveSide side={props.event.home} />
          <span class="font-display text-3xl font-medium tabular-nums">
            {props.event.home?.score ?? '–'}
            <span class="px-1 text-muted">:</span>
            {props.event.away?.score ?? '–'}
          </span>
          <LiveSide side={props.event.away} end />
        </span>
      </Show>
    </Button>
  )
}

function LiveSide(props: { side?: SportSide; end?: boolean }) {
  return (
    <span
      class={cn(
        'flex min-w-0 items-center gap-2 text-sm font-medium',
        props.end && 'flex-row-reverse text-right',
      )}
    >
      <SportBadge
        url={props.side?.badgeUrl}
        name={props.side?.name ?? '?'}
        class="size-7"
      />
      <span class="truncate">{props.side?.name ?? 'To be decided'}</span>
    </span>
  )
}
