import {
  Link,
  createFileRoute,
  redirect,
  useRouter,
} from '@tanstack/solid-router'
import {
  For,
  Show,
  createEffect,
  createMemo,
  createSignal,
  on,
  onCleanup,
  onMount,
} from 'solid-js'
import { AddToListDialog } from '../components/AddToListDialog'
import { AlbumHeader, Tracklist } from '../components/AlbumParts'
import { DiscussButton } from '../components/groups/DiscussButton'
import { Wordmark } from '../components/Brand'
import { EpisodeSheet } from '../components/EpisodeSheet'
import { Poster } from '../components/Poster'
import { SeasonMap } from '../components/SeasonMap'
import {
  Button,
  Card,
  cardClass,
  ToggleGroup,
  ToggleGroupItem,
  Switch,
  SwitchControl,
  SwitchInput,
  SwitchLabel,
  SwitchThumb,
  Toaster,
  toast,
} from '~/components/ui'
import { cn } from '~/lib/utils'
import { KINDS, kindOf, statusOptions } from '../lib/library/model'
import type { LibraryEntry, LibraryStatus } from '../lib/library/model'
import { getSession } from '../lib/session/session'
import {
  getTitlePage,
  markSeason,
  setEpisode,
  updateItem,
} from '../lib/title/server'
import {
  airLabel,
  airedKeys,
  episodeKey,
  hasAired,
  neighbours,
  nextEpisode,
  nextRating,
  ratingLabel,
  orderedSeasons,
} from '../lib/title/model'
import type { Episode, LibraryItemPatch, Season } from '../lib/title/model'

// APP-005 on the web: the Title room, at parity with the Apple apps' `TitleDetailView`. An album
// (MUS-001) is a big square cover, its artist and genres, then the usual controls and its
// tracklist: no progress, no episodes.
export const Route = createFileRoute('/app_/title/$id')({
  head: () => ({ meta: [{ title: 'Title · Aaru' }] }),
  beforeLoad: async () => {
    const session = await getSession()
    if (!session.signedIn) throw redirect({ to: '/sign-in' })
  },
  loader: ({ params }) => getTitlePage({ data: { id: params.id } }),
  component: TitleRoom,
})

/** The room's hairline pitches (see `.atmos`), stable per title: each room has its own rhythm. */
function roomCode(id: string) {
  let hash = 0
  for (const char of id) hash = (hash * 31 + char.charCodeAt(0)) >>> 0
  return {
    '--code-a': `${5 + (hash % 5)}px`,
    '--code-b': `${13 + ((hash >> 4) % 11)}px`,
  }
}

const watchedSet = (entry: LibraryEntry) =>
  new Set(
    (entry.watchedEpisodes ?? []).map((e) => episodeKey(e.season, e.number)),
  )

function TitleRoom() {
  const page = Route.useLoaderData()
  const router = useRouter()
  const title = () => page().title ?? undefined
  const [entry, setEntry] = createSignal<LibraryEntry>(page().entry)
  const [watched, setWatched] = createSignal(watchedSet(page().entry))
  const [pending, setPending] = createSignal<Set<string>>(new Set())
  const [problem, setProblem] = createSignal<string | null>(null)
  const [picking, setPicking] = createSignal(false)
  const [notes, setNotes] = createSignal(page().entry.notes ?? '')
  const [pageNumber, setPageNumber] = createSignal(
    page().entry.bookProgress?.page?.toString() ?? '',
  )

  // A server-rendered <textarea> carries `value` only as an attribute, which the browser
  // ignores, and hydration does not set the property: a saved note looked empty after a load.
  let notesField: HTMLTextAreaElement | undefined
  onMount(() => {
    if (notesField) notesField.value = notes()
  })

  const [opened, setOpened] = createSignal<Episode | null>(null)
  const [retrying, setRetrying] = createSignal(false)

  const kind = () => kindOf(entry().title.type, entry().title.isAnime)
  const isAlbum = () => kind() === 'album'
  const seasons = createMemo(() => orderedSeasons(title()))
  const upNext = createMemo(() => nextEpisode(title(), watched()))
  /** The season to open first: the one holding the next episode, else the first. */
  const openSeason = () => upNext()?.season ?? seasons()[0]?.number

  async function retry() {
    setRetrying(true)
    try {
      await router.invalidate()
    } finally {
      setRetrying(false)
    }
  }

  /** The server's answer is the truth: it replaces the optimistic state. */
  function commit(response: LibraryEntry) {
    setEntry(response)
    if (response.watchedEpisodes) setWatched(watchedSet(response))
  }

  async function toggle(season: number, number: number) {
    const key = episodeKey(season, number)
    if (pending().has(key)) return
    const watch = !watched().has(key)
    const before = watched()
    setProblem(null)
    // Optimistic: the tick moves now; the server's answer decides.
    const next = new Set(before)
    if (watch) next.add(key)
    else next.delete(key)
    setWatched(next)
    setPending(new Set([...pending(), key]))
    try {
      commit(
        await setEpisode({
          data: { id: entry().id, season, episode: number, watched: watch },
        }),
      )
    } catch (error) {
      setWatched(before)
      setProblem(
        error instanceof Error
          ? error.message
          : `S${season} E${number} was not saved.`,
      )
    } finally {
      const rest = new Set(pending())
      rest.delete(key)
      setPending(rest)
    }
  }

  async function markAll(season: number) {
    const keys = airedKeys(title(), season)
    const before = watched()
    setProblem(null)
    setWatched(new Set([...before, ...keys]))
    setPending(new Set([...pending(), ...keys]))
    try {
      commit(await markSeason({ data: { id: entry().id, season } }))
    } catch (error) {
      setWatched(before)
      setProblem(
        error instanceof Error
          ? error.message
          : `Season ${season} was not marked.`,
      )
    } finally {
      const rest = new Set(pending())
      keys.forEach((k) => rest.delete(k))
      setPending(rest)
    }
  }

  async function update(
    patch: LibraryItemPatch,
    optimistic: Partial<LibraryEntry>,
  ) {
    const before = entry()
    setProblem(null)
    setEntry({ ...before, ...optimistic })
    try {
      const response = await updateItem({ data: { id: before.id, patch } })
      commit({ ...response, watchedEpisodes: undefined })
    } catch (error) {
      setEntry(before)
      setProblem(
        error instanceof Error ? error.message : 'That change was not saved.',
      )
    }
  }

  // A failed save shows as a toast until the next change starts or it is closed.
  let problemToast: string | number | undefined
  const dismissProblem = () => {
    if (problemToast !== undefined) toast.dismiss(problemToast)
    problemToast = undefined
  }
  createEffect(
    on(problem, (message) => {
      dismissProblem()
      if (message) problemToast = toast.error(message, { duration: Infinity })
    }),
  )
  onCleanup(dismissProblem)

  const meta = () =>
    [
      entry().title.year,
      KINDS.find((k) => k.kind === kind())?.label,
      title()?.runtimeMinutes ? `${title()?.runtimeMinutes} min` : undefined,
      title()?.status
        ? title()!.status!.charAt(0).toUpperCase() + title()!.status!.slice(1)
        : undefined,
    ]
      .filter(Boolean)
      .join(' · ')

  const backdrop = () => entry().title.backdropUrl
  const progress = () => {
    const p = entry().progress
    return p && p.airedCount > 0 ? p : null
  }
  /** The next aired, unwatched episode, for the room's one obvious action. */
  const nextUp = () => (entry().title.type === 'show' ? upNext() : undefined)

  return (
    <div class="min-h-[100dvh]">
      <header class="mx-auto flex h-18 max-w-6xl items-center justify-between px-5 md:px-8">
        <Wordmark to="/app" />
        <Link
          to="/app/library"
          class="text-sm font-medium text-muted hover:text-ink"
        >
          Library
        </Link>
      </header>

      <main class="mx-auto max-w-6xl px-5 pb-20 md:px-8">
        <Show
          when={isAlbum()}
          fallback={
            // The room's hero: the title's wide art fading into the paper, over the room's
            // own hairline rhythm (seeded by the title), with the poster and name standing in
            // front of it. Capped in height so the controls stay on the first screen.
            <section>
              <div
                class="atmos relative h-[clamp(180px,30vh,320px)] overflow-hidden rounded-card"
                style={roomCode(entry().title.id)}
              >
                <Show when={backdrop()}>
                  {(url) => (
                    <img
                      src={url()}
                      alt=""
                      decoding="async"
                      class="absolute inset-0 h-full w-full object-cover"
                    />
                  )}
                </Show>
                <div class="veil absolute inset-0" />
              </div>
              {/* On a phone only the poster steps into the art and the name sits under it, so a
                  long title never lies across the picture. */}
              <div class="relative -mt-12 flex items-start gap-5 px-1 md:-mt-28 md:items-end md:gap-7 md:px-6">
                <Poster
                  url={entry().title.posterUrl}
                  kind={kind()}
                  class="fringe w-24 shrink-0 rounded-field md:w-40"
                />
                <div class="min-w-0 pt-14 pb-1 md:pt-0">
                  <h1
                    class="line-clamp-3 font-display text-3xl leading-tight font-medium tracking-tight text-balance md:text-5xl"
                    title={entry().title.title}
                  >
                    {entry().title.title}
                  </h1>
                  <p class="mt-2 text-sm text-muted tabular-nums md:text-base">
                    {meta()}
                  </p>
                  <Show when={progress()}>
                    {(p) => (
                      <div class="mt-3 max-w-xs">
                        <div class="h-1 overflow-hidden rounded-full bg-line">
                          <div
                            class="h-full rounded-full bg-accent transition-[width]"
                            style={{
                              width: `${(p().watchedCount / p().airedCount) * 100}%`,
                            }}
                          />
                        </div>
                        <p class="mt-1.5 text-xs text-muted tabular-nums">
                          {p().watchedCount} of {p().airedCount} episodes
                        </p>
                      </div>
                    )}
                  </Show>
                </div>
              </div>
            </section>
          }
        >
          <AlbumHeader
            name={entry().title.title}
            posterUrl={entry().title.posterUrl}
            byline={entry().title.byline ?? title()?.byline}
            year={entry().title.year}
            genres={title()?.genres}
          >
            <Button
              variant="outline"
              size="sm"
              class="mt-4"
              onClick={() => setPicking(true)}
            >
              Add to list
            </Button>
            <DiscussButton
              titleId={entry().title.id}
              type={entry().title.type}
              name={entry().title.title}
            />
          </AlbumHeader>
        </Show>

        {/* What a visit is usually for, in one row: the next episode, where it stands on
            the shelf, and the two ways to take it elsewhere. */}
        <div class="mt-6 flex flex-wrap items-center gap-2">
          <Show when={nextUp()}>
            {(episode) => (
              <Button
                variant="default"
                disabled={pending().has(
                  episodeKey(episode().season, episode().number),
                )}
                onClick={() => void toggle(episode().season, episode().number)}
              >
                Mark S{episode().season} · E{episode().number} watched
              </Button>
            )}
          </Show>
          <ToggleGroup
            class="flex flex-wrap gap-1.5"
            aria-label="Status"
            value={entry().status}
            onChange={(next: string | null) => {
              if (!next) return
              const status = next as LibraryStatus
              void update({ status }, { status })
            }}
          >
            <For each={statusOptions(kind())}>
              {(option) => (
                <ToggleGroupItem
                  size="bare"
                  value={option.status}
                  variant="chip"
                  class="min-h-11 px-4 text-sm"
                >
                  {option.label}
                </ToggleGroupItem>
              )}
            </For>
          </ToggleGroup>
          <Show when={!isAlbum()}>
            <Button variant="quiet" onClick={() => setPicking(true)}>
              Add to list
            </Button>
            <DiscussButton
              titleId={entry().title.id}
              type={entry().title.type}
              name={entry().title.title}
            />
          </Show>
        </div>

        <div class="mt-10 grid gap-10 lg:grid-cols-[minmax(0,1fr)_20rem]">
          <div class="flex min-w-0 flex-col gap-8">
            <Show when={entry().title.type !== 'show' && title()?.synopsis}>
              <section>
                <h2 class="eyebrow">About</h2>
                <p class="mt-3 max-w-[65ch] text-lg leading-relaxed">
                  {title()?.synopsis}
                </p>
              </section>
            </Show>

            <Show when={isAlbum()}>
              <Tracklist tracks={title()?.tracks} />
            </Show>

            <Show when={entry().title.type === 'show'}>
              <Show when={page().titleError}>
                {(message) => (
                  <Card class="flex-row items-center gap-4 p-5">
                    <p class="text-sm text-muted">{message()}</p>
                    <Button
                      variant="outline"
                      size="sm"
                      class="ml-auto"
                      disabled={retrying()}
                      onClick={() => void retry()}
                    >
                      Try again
                    </Button>
                  </Card>
                )}
              </Show>
              <Show when={title() && seasons().length === 0}>
                <p class="text-sm text-muted">
                  No episodes are listed for this show yet.
                </p>
              </Show>
              <Show when={seasons().length > 0}>
                <section>
                  <h2 class="eyebrow">Episodes</h2>
                  <div class="mt-3">
                    <SeasonMap
                      seasons={seasons()}
                      watched={watched()}
                      pending={pending()}
                      next={upNext()}
                      onToggle={toggle}
                    />
                  </div>
                </section>
                <section class="-mt-4 flex flex-col gap-4">
                  <For each={seasons()}>
                    {(season) => (
                      <SeasonBlock
                        season={season}
                        open={season.number === openSeason()}
                        watched={watched()}
                        pending={pending()}
                        canMarkAll={airedKeys(title(), season.number).some(
                          (k) => !watched().has(k),
                        )}
                        onToggle={toggle}
                        onMarkAll={markAll}
                        onOpen={setOpened}
                      />
                    )}
                  </For>
                </section>
              </Show>
            </Show>
          </div>

          <aside class="flex flex-col gap-8" aria-label="Your notes">
            <Card class="flex flex-col gap-4 p-5">
              <div class="flex items-center justify-between gap-4 text-sm font-medium">
                Rating
                {/* The group carries the value; only the star equal to it is pressed, and
                    pressing that one again clears the rating. */}
                <div
                  class="-my-2 flex"
                  role="group"
                  aria-label={ratingLabel(entry().rating)}
                >
                  <For each={[1, 2, 3, 4, 5]}>
                    {(star) => (
                      <button
                        type="button"
                        aria-label={`${star} star${star === 1 ? '' : 's'}`}
                        aria-pressed={entry().rating === star * 2}
                        class="grid min-h-11 min-w-8 place-items-center rounded-full text-xl leading-none text-gold"
                        onClick={() => {
                          const rating = nextRating(entry().rating, star)
                          void (rating === null
                            ? update(
                                { clear: ['rating'] },
                                { rating: undefined },
                              )
                            : update({ rating }, { rating }))
                        }}
                      >
                        {(entry().rating ?? 0) >= star * 2 ? '★' : '☆'}
                      </button>
                    )}
                  </For>
                </div>
              </div>
              <Switch
                class="flex items-center justify-between gap-4 text-sm font-medium"
                checked={entry().isOwned}
                onChange={(isOwned) => void update({ isOwned }, { isOwned })}
              >
                <SwitchInput />
                <SwitchLabel class="cursor-pointer">Owned</SwitchLabel>
                <SwitchControl>
                  <SwitchThumb />
                </SwitchControl>
              </Switch>
              <Show when={entry().title.type === 'book'}>
                <form
                  class="flex items-center justify-between gap-4 text-sm font-medium"
                  onSubmit={(e) => {
                    e.preventDefault()
                    const bookPage = Number.parseInt(pageNumber(), 10)
                    if (Number.isFinite(bookPage)) {
                      void update(
                        { bookPage },
                        { bookProgress: { page: bookPage } },
                      )
                    }
                  }}
                >
                  <label for="page">Page</label>
                  <input
                    id="page"
                    inputmode="numeric"
                    class="w-24 rounded-full border-0 bg-paper px-4 py-1.5 text-right text-sm focus:ring-2 focus:ring-accent"
                    value={pageNumber()}
                    onInput={(e) => setPageNumber(e.currentTarget.value)}
                  />
                </form>
              </Show>
            </Card>
            <section>
              <label for="notes" class="eyebrow">
                Notes
              </label>
              <textarea
                ref={notesField}
                id="notes"
                rows="3"
                placeholder="Anything worth remembering"
                class="mt-3 w-full rounded-panel border-0 bg-surface px-4 py-3 text-base focus:ring-2 focus:ring-accent"
                value={notes()}
                onInput={(e) => setNotes(e.currentTarget.value)}
              />
              <Show when={notes() !== (entry().notes ?? '')}>
                <Button
                  variant="outline"
                  size="sm"
                  class="mt-2"
                  onClick={() => {
                    const text = notes().trim()
                    void (text
                      ? update({ notes: text }, { notes: text })
                      : update({ clear: ['notes'] }, { notes: undefined }))
                  }}
                >
                  Save note
                </Button>
              </Show>
            </section>

            <Show when={entry().title.type === 'show' && title()?.synopsis}>
              <section>
                <h2 class="eyebrow">About</h2>
                <p class="mt-3 leading-relaxed text-muted">
                  {title()?.synopsis}
                </p>
              </section>
            </Show>
          </aside>
        </div>
        <Show when={opened()}>
          {(episode) => (
            <EpisodeSheet
              showTitle={entry().title.title}
              episode={episode()}
              {...neighbours(title(), episode().season, episode().number)}
              watched={watched()}
              pending={pending()}
              onToggle={toggle}
              onSelect={setOpened}
              onClose={() => setOpened(null)}
            />
          )}
        </Show>
        <Show when={picking()}>
          <AddToListDialog
            mediaRef={{ titleId: entry().title.id, type: entry().title.type }}
            titleName={entry().title.title}
            onClose={() => setPicking(false)}
          />
        </Show>
      </main>
      <Toaster />
    </div>
  )
}

function SeasonBlock(props: {
  season: Season
  open: boolean
  watched: Set<string>
  pending: Set<string>
  canMarkAll: boolean
  onToggle: (season: number, number: number) => void
  onMarkAll: (season: number) => void
  onOpen: (episode: Episode) => void
}) {
  const count = () =>
    props.season.episodes.filter((e) =>
      props.watched.has(episodeKey(e.season, e.number)),
    ).length
  return (
    // "Mark watched" sits over the summary's row, not inside it: a <summary> may not hold
    // a button, and anything after it inside <details> is hidden while closed. It comes
    // first in the DOM so the tab order stays next to the summary, before the episodes.
    <div class={cn(cardClass, 'relative')}>
      <Show when={props.season.number > 0 && props.canMarkAll}>
        <button
          type="button"
          class="absolute top-[15px] z-10 right-5 rounded-full border border-ink/25 px-3 py-1 text-xs font-semibold hover:bg-paper"
          onClick={() => props.onMarkAll(props.season.number)}
        >
          Mark watched
        </button>
      </Show>
      <details open={props.open}>
        <summary class="flex h-14 cursor-pointer list-none items-center gap-4 px-5 [&::-webkit-details-marker]:hidden">
          <span class="font-medium">
            {props.season.number === 0
              ? 'Specials'
              : `Season ${props.season.number}`}
          </span>
          <span class="text-sm text-muted">
            {count()} of {props.season.episodes.length}
          </span>
        </summary>
        <ul class="px-2 pb-3">
          <For each={props.season.episodes}>
            {(episode) => {
              const key = () => episodeKey(episode.season, episode.number)
              const isWatched = () => props.watched.has(key())
              const aired = hasAired(episode)
              return (
                <li
                  class="flex items-center gap-3 rounded-[12px] px-3 py-2 hover:bg-paper/60"
                  classList={{ 'opacity-60': !aired && !isWatched() }}
                >
                  <input
                    type="checkbox"
                    class="h-5 w-5 shrink-0 accent-accent disabled:cursor-not-allowed"
                    aria-label={`Episode ${episode.number} watched`}
                    checked={isWatched()}
                    disabled={
                      (!aired && !isWatched()) || props.pending.has(key())
                    }
                    onChange={() =>
                      props.onToggle(episode.season, episode.number)
                    }
                  />
                  <button
                    type="button"
                    class="flex min-w-0 flex-1 items-center gap-3 text-left"
                    onClick={() => props.onOpen(episode)}
                  >
                    <Show
                      when={episode.stillUrl}
                      fallback={
                        <span
                          class="hidden aspect-video w-20 shrink-0 rounded-[8px] bg-paper sm:block"
                          aria-hidden="true"
                        />
                      }
                    >
                      {(url) => (
                        <img
                          src={url()}
                          alt=""
                          loading="lazy"
                          class="aspect-video w-20 shrink-0 rounded-[8px] bg-paper object-cover"
                        />
                      )}
                    </Show>
                    <span class="min-w-0 flex-1">
                      <span class="line-clamp-1">
                        {episode.number}.{' '}
                        {episode.name ?? `Episode ${episode.number}`}
                      </span>
                      <Show when={airLabel(episode)}>
                        <span class="block text-xs text-muted">
                          {aired ? '' : 'Airs '}
                          {airLabel(episode)}
                        </span>
                      </Show>
                      <Show when={episode.overview}>
                        <span class="mt-0.5 line-clamp-1 block text-xs text-muted">
                          {episode.overview}
                        </span>
                      </Show>
                    </span>
                  </button>
                </li>
              )
            }}
          </For>
        </ul>
      </details>
    </div>
  )
}
