import {
  Link,
  createFileRoute,
  redirect,
  useRouter,
} from '@tanstack/solid-router'
import { For, Show, createMemo, createSignal } from 'solid-js'
import { AddToListDialog } from '../components/AddToListDialog'
import { DiscussButton } from '../components/groups/DiscussButton'
import { Wordmark } from '../components/Brand'
import { EpisodeSheet } from '../components/EpisodeSheet'
import { Poster } from '../components/Poster'
import { SeasonMap } from '../components/SeasonMap'
import { Button } from '../components/ui/button'
import { Card, cardClass } from '../components/ui/card'
import { cn } from '../lib/cn'
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
  orderedSeasons,
} from '../lib/title/model'
import type { Episode, LibraryItemPatch, Season } from '../lib/title/model'

// APP-005 on the web: the Title room, at parity with the Apple apps' `TitleDetailView`.
export const Route = createFileRoute('/app_/title/$id')({
  head: () => ({ meta: [{ title: 'Title · Aaru' }] }),
  beforeLoad: async () => {
    const session = await getSession()
    if (!session.signedIn) throw redirect({ to: '/sign-in' })
  },
  loader: ({ params }) => getTitlePage({ data: { id: params.id } }),
  component: TitleRoom,
})

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

  const [opened, setOpened] = createSignal<Episode | null>(null)
  const [retrying, setRetrying] = createSignal(false)

  const kind = () => kindOf(entry().title.type, entry().title.isAnime)
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

  return (
    <div class="min-h-[100dvh]">
      <header class="mx-auto flex h-18 max-w-4xl items-center justify-between px-5 md:px-8">
        <Wordmark />
        <Link
          to="/app/library"
          class="text-sm font-medium text-muted hover:text-ink"
        >
          Library
        </Link>
      </header>

      <main class="mx-auto max-w-4xl px-5 pb-20 md:px-8">
        <section class="mt-4 flex gap-6">
          <Poster
            url={entry().title.posterUrl}
            kind={kind()}
            class="w-28 shrink-0 md:w-40"
          />
          <div class="min-w-0">
            <h1 class="font-display text-3xl leading-tight font-medium tracking-tight md:text-4xl">
              {entry().title.title}
            </h1>
            <p class="mt-2 text-muted">{meta()}</p>
            <Button size="sm" class="mt-4" onClick={() => setPicking(true)}>
              Add to list
            </Button>
            <DiscussButton
              titleId={entry().title.id}
              type={entry().title.type}
              name={entry().title.title}
            />
            <Show when={entry().progress && entry().progress!.airedCount > 0}>
              <div class="mt-4 max-w-xs">
                <div class="h-1.5 overflow-hidden rounded-full bg-surface">
                  <div
                    class="h-full rounded-full bg-accent transition-[width]"
                    style={{
                      width: `${(entry().progress!.watchedCount / entry().progress!.airedCount) * 100}%`,
                    }}
                  />
                </div>
                <p class="mt-2 text-sm text-muted">
                  {entry().progress!.watchedCount} of{' '}
                  {entry().progress!.airedCount} episodes
                </p>
              </div>
            </Show>
          </div>
        </section>

        <Show when={problem()}>
          {(message) => (
            <p
              role="alert"
              class="fixed inset-x-4 bottom-4 z-20 mx-auto max-w-md rounded-panel bg-danger px-4 py-3 text-sm text-paper shadow-lg"
            >
              {message()}
            </p>
          )}
        </Show>

        <Card class="mt-8 grid gap-4 p-5 sm:grid-cols-2">
          <label class="flex items-center justify-between gap-4 text-sm font-medium">
            Status
            <select
              class="rounded-full border-0 bg-paper py-1.5 pr-8 pl-4 text-sm focus:ring-2 focus:ring-accent"
              value={entry().status}
              onChange={(e) => {
                const status = e.currentTarget.value as LibraryStatus
                void update({ status }, { status })
              }}
            >
              <For each={statusOptions(kind())}>
                {(s) => (
                  // `selected` on the option, not `value` on the select: the value would be
                  // applied before the options exist and show the first one.
                  <option
                    value={s.status}
                    selected={s.status === entry().status}
                  >
                    {s.label}
                  </option>
                )}
              </For>
            </select>
          </label>
          <div class="flex items-center justify-between gap-4 text-sm font-medium">
            Rating
            <div class="flex gap-1" role="group" aria-label="Rating">
              <For each={[1, 2, 3, 4, 5]}>
                {(star) => (
                  <button
                    type="button"
                    aria-label={`${star} star${star === 1 ? '' : 's'}`}
                    aria-pressed={(entry().rating ?? 0) >= star * 2}
                    class="text-xl leading-none text-accent"
                    onClick={() => {
                      const rating = nextRating(entry().rating, star)
                      void (rating === null
                        ? update({ clear: ['rating'] }, { rating: undefined })
                        : update({ rating }, { rating }))
                    }}
                  >
                    {(entry().rating ?? 0) >= star * 2 ? '★' : '☆'}
                  </button>
                )}
              </For>
            </div>
          </div>
          <label class="flex items-center justify-between gap-4 text-sm font-medium">
            Owned
            <input
              type="checkbox"
              class="h-5 w-5 rounded text-accent focus:ring-accent"
              checked={entry().isOwned}
              onChange={(e) => {
                const isOwned = e.currentTarget.checked
                void update({ isOwned }, { isOwned })
              }}
            />
          </label>
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

        <section class="mt-8">
          <label for="notes" class="font-display text-xl font-medium">
            Notes
          </label>
          <textarea
            id="notes"
            rows="3"
            placeholder="Anything worth remembering"
            class="mt-3 w-full rounded-panel border-0 bg-surface px-4 py-3 text-base focus:ring-2 focus:ring-accent"
            value={notes()}
            onInput={(e) => setNotes(e.currentTarget.value)}
          />
          <Show when={notes() !== (entry().notes ?? '')}>
            <Button
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

        <Show when={title()?.synopsis}>
          <section class="mt-8">
            <h2 class="font-display text-xl font-medium">About</h2>
            <p class="mt-3 max-w-[65ch] leading-relaxed text-muted">
              {title()?.synopsis}
            </p>
          </section>
        </Show>

        <Show when={entry().title.type === 'show'}>
          <Show when={page().titleError}>
            {(message) => (
              <Card class="mt-10 flex items-center gap-4 p-5">
                <p class="text-sm text-muted">{message()}</p>
                <Button
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
            <p class="mt-10 text-sm text-muted">
              No episodes are listed for this show yet.
            </p>
          </Show>
          <Show when={seasons().length > 0}>
            <section class="mt-10">
              <h2 class="font-display text-xl font-medium">Episodes</h2>
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
            <section class="mt-4 flex flex-col gap-4">
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
    <details class={cn(cardClass, 'group')} open={props.open}>
      <summary class="flex cursor-pointer list-none items-center gap-4 px-5 py-4 [&::-webkit-details-marker]:hidden">
        <span class="font-medium">
          {props.season.number === 0
            ? 'Specials'
            : `Season ${props.season.number}`}
        </span>
        <span class="text-sm text-muted">
          {count()} of {props.season.episodes.length}
        </span>
        <Show when={props.season.number > 0 && props.canMarkAll}>
          <button
            type="button"
            class="ml-auto rounded-full border border-ink/25 px-3 py-1 text-xs font-semibold hover:bg-paper"
            onClick={(e) => {
              e.preventDefault()
              props.onMarkAll(props.season.number)
            }}
          >
            Mark watched
          </button>
        </Show>
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
                  class="h-5 w-5 shrink-0 rounded-full text-accent focus:ring-accent disabled:cursor-not-allowed"
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
  )
}
