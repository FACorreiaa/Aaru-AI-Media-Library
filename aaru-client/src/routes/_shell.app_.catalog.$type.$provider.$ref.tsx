import { createFileRoute, redirect, useNavigate } from '@tanstack/solid-router'
import { Show, createSignal } from 'solid-js'
import { AddControl } from '../components/AddControl'
import { AddToListDialog } from '../components/AddToListDialog'
import { AlbumHeader, Tracklist } from '../components/AlbumParts'
import { Poster } from '../components/Poster'
import { ShareDialog } from '../components/ShareDialog'
import { BackLink } from '../components/shell/BackLink'
import { Button } from '~/components/ui'
import { KINDS, kindOf } from '../lib/library/model'
import type { CatalogHit, LibraryStatus } from '../lib/library/model'
import { addToLibrary } from '../lib/library/server'
import { MEDIA_TYPES } from '../lib/media'
import { titlePreviewQuery } from '../lib/queries'
import { orderedSeasons, showStatusLabel } from '../lib/title/model'
import { PREVIEW_PROVIDERS } from '../lib/title/preview'
import type { PreviewParams } from '../lib/title/preview'
import { lastShown } from '../lib/presence'

// LIB-006 on the web: the page for a title that is not in the library. The same facts as the
// Title room (poster, kind, year, synopsis, seasons or tracklist) with Add and List; nothing is
// written until one is tapped. A title already in the library opens its Title room instead.
export const Route = createFileRoute(
  '/_shell/app_/catalog/$type/$provider/$ref',
)({
  params: {
    parse: (raw): PreviewParams => {
      const type = MEDIA_TYPES.find((t) => t === raw.type)
      const provider = PREVIEW_PROVIDERS.find((p) => p === raw.provider)
      if (!type || !provider) throw new Error('Not a title address.')
      return { type, provider, ref: raw.ref }
    },
    stringify: (params) => params,
  },
  loader: async ({ params, context: { queryClient } }) => {
    const preview = await queryClient.query(titlePreviewQuery(params))
    if (preview.libraryItemId)
      throw redirect({
        to: '/app/title/$id',
        params: { id: preview.libraryItemId },
        replace: true,
      })
    return preview.title
  },
  head: ({ loaderData }) => ({
    meta: [{ title: `${loaderData?.title ?? 'Title'} · Aaru` }],
  }),
  component: TitlePreview,
})

function TitlePreview() {
  const title = Route.useLoaderData()
  const navigate = useNavigate()
  const [adding, setAdding] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  const [listing, setListing] = createSignal(false)
  const listShown = lastShown(() => (listing() ? title() : null))
  const [sharing, setSharing] = createSignal(false)
  // Mounted on first open, then kept, so closing plays the exit (WEB-011).
  const [sharedOnce, setSharedOnce] = createSignal(false)
  const share = () => {
    setSharedOnce(true)
    setSharing(true)
  }
  const kind = () => kindOf(title().type, title().isAnime)
  const hit = (): CatalogHit => ({
    type: title().type,
    title: title().title,
    originalTitle: title().originalTitle,
    year: title().year,
    posterUrl: title().posterUrl,
    byline: title().byline,
    isAnime: title().isAnime,
    ids: title().ids,
  })
  // Specials are not a season in the count.
  const seasons = () => orderedSeasons(title()).filter((s) => s.number > 0)
  const episodes = () => seasons().reduce((n, s) => n + s.episodes.length, 0)
  const facts = () =>
    [
      KINDS.find((k) => k.kind === kind())?.label,
      title().year,
      title().byline,
      title().runtimeMinutes ? `${title().runtimeMinutes} min` : undefined,
      showStatusLabel(title().status),
      seasons().length > 0
        ? `${seasons().length} ${seasons().length === 1 ? 'season' : 'seasons'} · ${episodes()} episodes`
        : undefined,
    ]
      .filter(Boolean)
      .join(' · ')

  async function add(status: LibraryStatus) {
    if (adding()) return
    setAdding(true)
    setProblem(null)
    try {
      const entry = await addToLibrary({
        data: {
          type: title().type,
          ids: title().ids,
          title: title().title,
          year: title().year,
          status,
        },
      })
      // Now it is the user's: its Title room takes this page's place in history.
      void navigate({
        to: '/app/title/$id',
        params: { id: entry.id },
        replace: true,
      })
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : `${title().title} could not be added.`,
      )
      setAdding(false)
    }
  }

  const actions = () => (
    <div class="mt-6 flex flex-wrap items-center gap-3">
      <AddControl hit={hit()} adding={adding()} onAdd={(s) => void add(s)} />
      <Button variant="outline" size="sm" onClick={() => setListing(true)}>
        Add to list
      </Button>
      <Button variant="outline" size="sm" onClick={share}>
        Share
      </Button>
    </div>
  )

  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <BackLink to="/app/library" label="Library" class="-ml-1" />
        <Show
          when={kind() !== 'album'}
          fallback={
            <>
              <AlbumHeader
                name={title().title}
                posterUrl={title().posterUrl}
                byline={title().byline}
                year={title().year}
                genres={title().genres}
              >
                {actions()}
              </AlbumHeader>
              <Tracklist tracks={title().tracks} />
            </>
          }
        >
          <section class="mt-4 flex flex-col gap-6 sm:flex-row sm:items-start">
            <Poster
              url={title().posterUrl}
              kind={kind()}
              class="w-40 shrink-0 sm:w-48 md:w-56"
            />
            <div class="min-w-0 max-w-[42rem]">
              <h1 class="font-display text-3xl leading-tight font-medium tracking-tight text-balance md:text-4xl">
                {title().title}
              </h1>
              <Show when={title().originalTitle !== title().title}>
                <p class="mt-1 text-muted">{title().originalTitle}</p>
              </Show>
              <p class="mt-2 text-sm text-muted">{facts()}</p>
              <Show when={title().synopsis}>
                {(synopsis) => <p class="mt-4 text-pretty">{synopsis()}</p>}
              </Show>
              {actions()}
            </div>
          </section>
        </Show>
        <Show when={problem()}>
          {(message) => (
            <p role="alert" class="mt-3 text-sm text-danger">
              {message()}
            </p>
          )}
        </Show>
        <Show when={listShown()}>
          {(shown) => (
            <AddToListDialog
              mediaRef={{
                type: shown().type,
                ids: shown().ids,
                title: shown().title,
                year: shown().year,
              }}
              titleName={shown().title}
              open={listing()}
              onClose={() => setListing(false)}
            />
          )}
        </Show>
        <Show when={sharedOnce()}>
          <ShareDialog
            open={sharing()}
            target={{
              kind: 'title',
              ref: {
                type: title().type,
                ids: title().ids,
                title: title().title,
                year: title().year,
              },
            }}
            name={title().title}
            onClose={() => setSharing(false)}
          />
        </Show>
      </div>
    </div>
  )
}
