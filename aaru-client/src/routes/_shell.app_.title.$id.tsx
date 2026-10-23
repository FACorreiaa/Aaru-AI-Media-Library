import {
  Link,
  createFileRoute,
  useNavigate,
  useRouter,
} from '@tanstack/solid-router'
import { BackLink } from '../components/shell/BackLink'
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
import { announceShowWatched } from '../components/mark-watched'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { AlbumHeader, Tracklist } from '../components/AlbumParts'
import { DiscussButton } from '../components/groups/DiscussButton'
import { RecommendDialog } from '../components/Recommendations'
import { EpisodeSheet } from '../components/EpisodeSheet'
import { PostCard } from '../components/board/PostCard'
import { Poster } from '../components/Poster'
import { SeasonMap } from '../components/SeasonMap'
import { Segmented } from '../components/Segmented'
import {
  Button,
  Card,
  Checkbox,
  CheckboxControl,
  CheckboxInput,
  CheckboxLabel,
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuPortal,
  DropdownMenuTrigger,
  RadioGroup,
  RadioGroupItem,
  RadioGroupItemInput,
  RadioGroupItemLabel,
  RadioGroupLabel,
  Switch,
  SwitchControl,
  SwitchInput,
  SwitchLabel,
  SwitchThumb,
  TextField,
  TextFieldInput,
  TextFieldLabel,
  TextFieldTextArea,
  cardClass,
  toast,
} from '~/components/ui'
import { loadFromFriends } from '../lib/board/server'
import { lastShown } from '../lib/presence'
import { cn } from '~/lib/utils'
import { KINDS, kindOf, statusOptions } from '../lib/library/model'
import type { LibraryEntry, LibraryStatus } from '../lib/library/model'
import { titlePageQuery } from '../lib/queries'
import {
  markSeason,
  markShowWatched,
  removeItem,
  setEpisode,
  updateItem,
} from '../lib/title/server'
import {
  airLabel,
  airedKeys,
  episodeCode,
  episodeKey,
  hasAired,
  isCaughtUp,
  neighbours,
  nextEpisode,
  orderedSeasons,
  ratingLabel,
  showStatusLabel,
} from '../lib/title/model'
import type { Episode, LibraryItemPatch, Season } from '../lib/title/model'

// APP-005 on the web: the Title room, at parity with the Apple apps' `TitleDetailView`. An album
// (MUS-001) is a big square cover, its artist and genres, then the usual controls and its
// tracklist: no progress, no episodes.
export const Route = createFileRoute('/_shell/app_/title/$id')({
  loader: ({ params, context: { queryClient } }) =>
    queryClient.query(titlePageQuery(params.id)),
  // UX-013: the tab names the title.
  head: ({ loaderData }) => ({
    meta: [{ title: `${loaderData?.entry.title.title ?? 'Title'} · Aaru` }],
  }),
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
  const { queryClient } = Route.useRouteContext()()
  const router = useRouter()
  const navigate = useNavigate()
  const title = () => page().title ?? undefined
  const [entry, setEntry] = createSignal<LibraryEntry>(page().entry)
  const [watched, setWatched] = createSignal(watchedSet(page().entry))
  const [pending, setPending] = createSignal<Set<string>>(new Set())
  const [problem, setProblem] = createSignal<string | null>(null)
  const [picking, setPicking] = createSignal(false)
  // Mounted on first open, then kept, so closing plays the exit (WEB-011).
  const [pickedOnce, setPickedOnce] = createSignal(false)
  const pick = () => {
    setPickedOnce(true)
    setPicking(true)
  }
  const [removing, setRemoving] = createSignal(false)
  const [removeBusy, setRemoveBusy] = createSignal(false)
  const [recommending, setRecommending] = createSignal(false)
  // Mounted on first open, then kept, so closing plays the exit (WEB-011).
  const [recommendedOnce, setRecommendedOnce] = createSignal(false)
  const recommendTitle = () => {
    setRecommendedOnce(true)
    setRecommending(true)
  }
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

  // BOARD-002: what friends wrote about this title. Read in the browser after the room shows,
  // and a failed read just leaves the section out.
  const [fromFriends, setFromFriends] = createSignal<Awaited<
    ReturnType<typeof loadFromFriends>
  > | null>(null)
  onMount(() => {
    loadFromFriends({ data: { titleId: page().entry.title.id } })
      .then(setFromFriends)
      .catch(() => undefined)
  })
  const friendHandles = createMemo(
    () =>
      new Set(
        [
          fromFriends()?.myHandle,
          ...(fromFriends()?.friendHandles ?? []),
          ...(fromFriends()?.posts.map((p) => p.author.handle) ?? []),
        ]
          .filter((h): h is string => Boolean(h))
          .map((h) => h.toLowerCase()),
      ),
  )

  const [opened, setOpened] = createSignal<Episode | null>(null)
  const shownEpisode = lastShown(opened)
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
          : `${episodeCode(season, number)} was not saved.`,
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

  /** The item and its ticks again, past the cache: after an undo the server's state is new. */
  async function reload() {
    try {
      const fresh = await queryClient.query({
        ...titlePageQuery(entry().id),
        staleTime: 0,
      })
      commit(fresh.entry)
    } catch {
      // The undo landed; the room catches up on the next visit.
    }
  }

  /** Watched, for a show, ticks every aired episode as one action (owner, 2026-10-22). An
   * ended show finishes; a running one stays Watching, caught up, and the toast says so. */
  async function finishShow() {
    const before = entry()
    const beforeWatched = watched()
    const aired = seasons()
      .filter((s) => s.number > 0)
      .flatMap((s) => airedKeys(title(), s.number))
    setProblem(null)
    setEntry({ ...before, status: 'finished' })
    setWatched(new Set([...beforeWatched, ...aired]))
    try {
      const result = await markShowWatched({ data: { id: before.id } })
      commit(result.entry)
      announceShowWatched(result, before.title.title, () => void reload())
    } catch (error) {
      setEntry(before)
      setWatched(beforeWatched)
      setProblem(
        error instanceof Error
          ? error.message
          : `${before.title.title} was not marked watched.`,
      )
    }
  }

  async function update(
    patch: LibraryItemPatch,
    optimistic: Partial<LibraryEntry>,
  ) {
    if (patch.status === 'finished' && entry().title.type === 'show')
      return finishShow()
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

  // UX-061: out of the library, journaled on the server, so History can undo it.
  async function remove() {
    setRemoveBusy(true)
    try {
      await removeItem({ data: { id: entry().id } })
      setRemoving(false)
      toast('Removed from your library', {
        action: {
          label: 'History',
          onClick: () =>
            void navigate({ to: '/app/settings/data', hash: 'history' }),
        },
      })
      if (window.history.length > 1) router.history.back()
      else await navigate({ to: '/app/library' })
    } catch (error) {
      setRemoving(false)
      setProblem(
        error instanceof Error
          ? error.message
          : `${entry().title.title} was not removed.`,
      )
    } finally {
      setRemoveBusy(false)
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
      showStatusLabel(title()?.status),
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
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <BackLink to="/app/library" label="Library" class="-ml-1" />
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
            <Button variant="outline" size="sm" class="mt-4" onClick={pick}>
              Add to list
            </Button>
            <DiscussButton
              titleId={entry().title.id}
              type={entry().title.type}
              name={entry().title.title}
            />
          </AlbumHeader>
        </Show>

        {/* What a visit is usually for, in one row: the next episode, where it stands in
            the library, the ways to take it elsewhere, and More. */}
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
                Mark {episodeCode(episode().season, episode().number)} watched
              </Button>
            )}
          </Show>
          <Segmented
            variant="chip"
            label="Status"
            value={entry().status}
            options={statusOptions(kind()).map((option) => ({
              value: option.status,
              label: option.label,
            }))}
            itemClass="min-h-11 px-4 text-sm"
            onChange={(status: LibraryStatus) =>
              void update({ status }, { status })
            }
          />
          <Show
            when={isCaughtUp({
              type: entry().title.type,
              status: entry().status,
              progress: entry().progress,
            })}
          >
            <span class="px-1 text-sm font-medium text-accent">Caught up</span>
          </Show>
          <Show when={!isAlbum()}>
            <Button variant="quiet" onClick={pick}>
              Add to list
            </Button>
            <DiscussButton
              titleId={entry().title.id}
              type={entry().title.type}
              name={entry().title.title}
            />
            <Button variant="quiet" onClick={recommendTitle}>
              Recommend
            </Button>
          </Show>
          <DropdownMenu placement="bottom-end">
            <DropdownMenuTrigger
              as={Button}
              variant="ghost"
              size="icon"
              aria-label={`More for ${entry().title.title}`}
              class="text-ink"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="currentColor"
                aria-hidden="true"
                class="size-5"
              >
                <circle cx="5.5" cy="12" r="1.6" />
                <circle cx="12" cy="12" r="1.6" />
                <circle cx="18.5" cy="12" r="1.6" />
              </svg>
            </DropdownMenuTrigger>
            <DropdownMenuPortal>
              <DropdownMenuContent class="min-w-52 rounded-panel border-line bg-paper p-1">
                <DropdownMenuItem
                  variant="destructive"
                  class="min-h-10 rounded-[10px] px-3"
                  onSelect={() => setRemoving(true)}
                >
                  Remove from library…
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenuPortal>
          </DropdownMenu>
        </div>

        <div class="mt-10 grid gap-10 lg:grid-cols-[minmax(0,1fr)_20rem]">
          <div class="flex min-w-0 flex-col gap-8">
            <Show when={entry().title.type !== 'show' && title()?.synopsis}>
              <section>
                <h2 class="eyebrow">About</h2>
                <p class="mt-3 max-w-prose text-lg leading-relaxed">
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
              {/* WEB-012: five stars as one radio group ("Rating, 4 of 5"); arrows move the
                  rating, Clear takes it off. Ratings are stored out of ten. */}
              <RadioGroup
                class="flex items-center justify-between gap-4"
                value={
                  entry().rating !== undefined && entry().rating! % 2 === 0
                    ? String(entry().rating! / 2)
                    : ''
                }
                onChange={(value: string) => {
                  const rating = Number(value) * 2
                  void update({ rating }, { rating })
                }}
              >
                <RadioGroupLabel class="text-sm font-medium">
                  Rating
                  <span class="sr-only">
                    , {ratingLabel(entry().rating).replace('Rating, ', '')}
                  </span>
                </RadioGroupLabel>
                <div class="-my-2 flex items-center">
                  <For each={[1, 2, 3, 4, 5]}>
                    {(star) => (
                      <RadioGroupItem value={String(star)} class="gap-0">
                        <RadioGroupItemInput />
                        <RadioGroupItemLabel class="grid min-h-11 min-w-8 cursor-pointer place-items-center rounded-full text-xl leading-none font-normal text-gold peer-focus-visible/radio-group:outline-2 peer-focus-visible/radio-group:outline-offset-2 peer-focus-visible/radio-group:outline-ring">
                          <span class="sr-only">{star} of 5</span>
                          <span aria-hidden="true">
                            {(entry().rating ?? 0) >= star * 2 ? '★' : '☆'}
                          </span>
                        </RadioGroupItemLabel>
                      </RadioGroupItem>
                    )}
                  </For>
                  <Show when={entry().rating !== undefined}>
                    <Button
                      variant="ghost"
                      size="xs"
                      class="ml-1"
                      onClick={() =>
                        void update(
                          { clear: ['rating'] },
                          { rating: undefined },
                        )
                      }
                    >
                      Clear
                    </Button>
                  </Show>
                </div>
              </RadioGroup>
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
                  <TextField
                    class="flex w-auto flex-row items-center justify-between gap-4"
                    value={pageNumber()}
                    onChange={setPageNumber}
                  >
                    <TextFieldLabel>Page</TextFieldLabel>
                    <TextFieldInput
                      inputmode="numeric"
                      class="min-h-9 w-24 rounded-full border-0 bg-paper px-4 py-1.5 text-right text-sm"
                    />
                  </TextField>
                </form>
              </Show>
            </Card>
            <section>
              <TextField value={notes()} onChange={setNotes} class="gap-0">
                <TextFieldLabel class="eyebrow">Notes</TextFieldLabel>
                <TextFieldTextArea
                  ref={notesField}
                  rows="3"
                  placeholder="Anything worth remembering"
                  class="mt-3 w-full rounded-panel border-0 bg-surface px-4 py-3 text-base md:text-base"
                />
              </TextField>
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

            <Show
              when={
                fromFriends() &&
                (fromFriends()!.posts.length > 0 ||
                  fromFriends()!.friendHandles.length > 0)
              }
            >
              <section aria-labelledby="from-friends">
                <h2 id="from-friends" class="eyebrow">
                  From friends
                </h2>
                <Show
                  when={fromFriends()!.posts.length > 0}
                  fallback={
                    <p class="mt-3 text-sm text-muted">
                      None of your friends has written about this yet.
                    </p>
                  }
                >
                  <ul class="mt-1 divide-y divide-line">
                    <For each={fromFriends()!.posts.slice(0, 5)}>
                      {(post) => (
                        <li>
                          <PostCard
                            post={post}
                            hideTitle
                            handles={friendHandles()}
                            myHandle={fromFriends()!.myHandle?.toLowerCase()}
                          />
                        </li>
                      )}
                    </For>
                  </ul>
                </Show>
                <Link
                  to="/app/friends"
                  search={{ title: page().entry.id }}
                  class="mt-2 inline-block text-sm font-medium text-accent hover:underline"
                >
                  Write about this
                </Link>
              </section>
            </Show>

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
        <Show when={shownEpisode()}>
          {(episode) => (
            <EpisodeSheet
              open={opened() !== null}
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
        <Show when={recommendedOnce()}>
          <RecommendDialog
            open={recommending()}
            title={{
              ref: { titleId: entry().title.id, type: entry().title.type },
              name: entry().title.title,
              posterUrl: entry().title.posterUrl,
              kind: kindOf(entry().title.type, entry().title.isAnime),
            }}
            onClose={() => setRecommending(false)}
          />
        </Show>
        <Show when={pickedOnce()}>
          <AddToListDialog
            open={picking()}
            mediaRef={{ titleId: entry().title.id, type: entry().title.type }}
            titleName={entry().title.title}
            onClose={() => setPicking(false)}
          />
        </Show>
        <ConfirmDialog
          open={removing()}
          title={`Remove ${entry().title.title} from your library?`}
          description="Its status, rating, notes and ticks go. You can undo it from History."
          confirmLabel="Remove"
          cancelLabel="Keep it"
          busy={removeBusy()}
          onConfirm={() => void remove()}
          onCancel={() => setRemoving(false)}
        />
      </div>
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
        <Button
          variant="outline"
          size="xs"
          class="absolute top-[15px] right-5 z-10 hover:bg-paper"
          onClick={() => props.onMarkAll(props.season.number)}
        >
          Mark watched
        </Button>
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
                  <Checkbox
                    class="shrink-0"
                    checked={isWatched()}
                    disabled={
                      (!aired && !isWatched()) || props.pending.has(key())
                    }
                    onChange={() =>
                      props.onToggle(episode.season, episode.number)
                    }
                  >
                    <CheckboxInput />
                    <CheckboxControl class="size-5 rounded-[6px] border-ink/30 bg-paper data-[checked]:border-accent data-[checked]:bg-accent data-[checked]:text-on-accent" />
                    <CheckboxLabel class="sr-only">
                      Episode {episode.number} watched
                    </CheckboxLabel>
                  </Checkbox>
                  <Button
                    variant="ghost"
                    size="bare"
                    class="min-w-0 flex-1 justify-start gap-3 rounded-[10px] text-left font-normal text-ink hover:text-ink motion-safe:active:scale-100"
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
                  </Button>
                </li>
              )
            }}
          </For>
        </ul>
      </details>
    </div>
  )
}
