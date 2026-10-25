import { createFileRoute } from '@tanstack/solid-router'
import { KindPage } from '../components/kind/KindPage'
import { loadKindPage } from '../lib/queries'

// NAV-001: Books, in the sidebar's More. Your reading shelf, then Open Library's weekly
// trending books from Discover (DISC-001).
export const Route = createFileRoute('/_shell/app_/books')({
  head: () => ({ meta: [{ title: 'Books · Aaru' }] }),
  loader: ({ context: { queryClient } }) => loadKindPage(queryClient),
  component: BooksPage,
})

function BooksPage() {
  const loaded = Route.useLoaderData()
  return (
    <KindPage
      kind="book"
      title="Books"
      blurb="What you are reading, what is next, and what readers are picking up this week."
      entries={loaded().entries}
      rows={loaded().rows}
      rowsProblem={loaded().rowsProblem}
    />
  )
}
