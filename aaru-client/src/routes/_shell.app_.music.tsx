import { createFileRoute } from '@tanstack/solid-router'
import { For, Show, Suspense, createSignal, lazy, onMount } from 'solid-js'
import { Skeleton } from '~/components/ui'
import { KindPage } from '../components/kind/KindPage'
import { localDayKey } from '../lib/calendar/model'
import type { ConcertPlaceSetting } from '../lib/concerts/model'
import { prefersReducedMotion } from '../lib/reduced-motion'
import { optionalEnum } from '../lib/search-params'
import { concertPlaceQuery, loadKindPage } from '../lib/queries'

// Concerts and Listens sit below the albums and load their code after the page, Concerts as
// they did on Discover.
const ConcertList = lazy(() =>
  import('../components/ConcertList').then((m) => ({
    default: m.ConcertList,
  })),
)
const Listens = lazy(() =>
  import('../components/music/Listens').then((m) => ({
    default: m.Listens,
  })),
)

// NAV-001: Music, the albums kind's page (DESIGN.md §18: "Music" is the albums, "Listens" the
// log). Your albums shelf, ListenBrainz's New albums and Coming soon (MUS-002), Concerts
// (MUS-003, only where the server has them on), then Listens (MUS-008). `?view=listens` and
// `?view=concerts` (or `#listens`, `#concerts`) open the page at that section.
export const Route = createFileRoute('/_shell/app_/music')({
  head: () => ({ meta: [{ title: 'Music · Aaru' }] }),
  validateSearch: (search): { view?: 'listens' | 'concerts' } => ({
    view: optionalEnum(search.view, ['listens', 'concerts']),
  }),
  loader: async ({ context: { queryClient } }) => {
    const [page, concerts] = await Promise.all([
      loadKindPage(queryClient),
      // Concerts are an extra: without an answer the section stays hidden.
      queryClient
        .query(concertPlaceQuery)
        .catch((): ConcertPlaceSetting | null => null),
    ])
    return { ...page, concerts }
  },
  component: MusicPage,
})

function MusicPage() {
  const loaded = Route.useLoaderData()
  const search = Route.useSearch()
  const [concerts, setConcerts] = createSignal<ConcertPlaceSetting | null>(
    loaded().concerts,
  )
  const [today, setToday] = createSignal<string | null>(null)
  onMount(() => {
    setToday(localDayKey(new Date()))
    // A link that names a section (Insights' "All listens") opens the page there.
    const target = search().view
    const section = target ? document.getElementById(target) : null
    if (section)
      requestAnimationFrame(() =>
        section.scrollIntoView({
          block: 'start',
          behavior: prefersReducedMotion() ? 'auto' : 'smooth',
        }),
      )
  })
  // Until the browser says, the server's day stands in: it only decides when a date names its year.
  const day = () => today() ?? localDayKey(new Date())

  return (
    <KindPage
      kind="album"
      title="Music"
      blurb="Your albums, what is new and coming, concerts, and what you have been playing."
      entries={loaded().entries}
      rows={loaded().rows}
      rowsProblem={loaded().rowsProblem}
    >
      <Show when={concerts()?.available ? concerts() : null}>
        {(setting) => (
          <section
            id="concerts"
            aria-label="Concerts"
            class="mt-2 scroll-mt-20"
          >
            <Suspense fallback={<ConcertsPlaceholder />}>
              <ConcertList
                setting={setting()}
                today={day()}
                onSettingChange={setConcerts}
              />
            </Suspense>
          </section>
        )}
      </Show>
      {/* The anchor is here, not in the section, so a link lands while its code still loads. */}
      <div id="listens" class="mt-16 scroll-mt-20">
        <Suspense fallback={<ListensPlaceholder />}>
          <Listens />
        </Suspense>
      </div>
    </KindPage>
  )
}

/** Holds the Listens section's place while its code loads. */
function ListensPlaceholder() {
  return (
    <div class="flex flex-col gap-3" aria-hidden="true">
      <Skeleton class="h-8 w-32 rounded-field" />
      <For each={[0, 1, 2]}>{() => <Skeleton class="h-12 rounded-card" />}</For>
    </div>
  )
}

/** Holds the Concerts section's place while its code loads. */
function ConcertsPlaceholder() {
  return (
    <div class="mt-8 flex max-w-3xl flex-col gap-3" aria-hidden="true">
      <Skeleton class="h-8 w-56 rounded-field" />
      <For each={[0, 1, 2]}>{() => <Skeleton class="h-16 rounded-card" />}</For>
    </div>
  )
}
