import { createFileRoute } from '@tanstack/solid-router'
import { KindPage } from '../components/kind/KindPage'
import { loadKindPage } from '../lib/queries'

// NAV-001: Manga, in the sidebar's More. Your manga shelf, then AniList's trending and
// publishing-now rows from Discover (DISC-004). While AniList is down there are no rows
// (MNG-001), and the shelf stands alone.
export const Route = createFileRoute('/_shell/app_/manga')({
  head: () => ({ meta: [{ title: 'Manga · Aaru' }] }),
  loader: ({ context: { queryClient } }) => loadKindPage(queryClient),
  component: MangaPage,
})

function MangaPage() {
  const loaded = Route.useLoaderData()
  return (
    <KindPage
      kind="manga"
      title="Manga"
      blurb="The series you are reading, the ones you plan to, and what is trending now."
      entries={loaded().entries}
      rows={loaded().rows}
      rowsProblem={loaded().rowsProblem}
    />
  )
}
