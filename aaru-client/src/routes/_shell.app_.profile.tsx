import { createFileRoute } from '@tanstack/solid-router'
import { ProfilePanel } from '../components/ProfilePanel'
import { BackLink } from '../components/shell/BackLink'
import { libraryQuery, profileStatsQuery } from '../lib/queries'

// The profile on the web (GAM-006b, owner 2026-10-22): reached from the medallion on Home's
// heading, a detail page inside the shell. All-time numbers; Insights keeps the periods. The
// library (usually cached already) only maps the most-watched titles to their items.
export const Route = createFileRoute('/_shell/app_/profile')({
  head: () => ({ meta: [{ title: 'Profile · Aaru' }] }),
  loader: async ({ context: { queryClient, session } }) => {
    const [stats, library] = await Promise.all([
      queryClient.query(profileStatsQuery),
      queryClient.query(libraryQuery).catch(() => []),
    ])
    const items = new Map(library.map((entry) => [entry.title.id, entry.id]))
    return {
      stats,
      person: { displayName: session.displayName, handle: session.handle },
      items: Object.fromEntries(
        stats.mostWatched.flatMap((top) => {
          const id = items.get(top.title.id)
          return id ? [[top.title.id, id]] : []
        }),
      ) as Record<string, string>,
    }
  },
  component: Profile,
})

function Profile() {
  const loaded = Route.useLoaderData()
  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <BackLink to="/app" label="Home" class="-ml-1" />
        <ProfilePanel
          stats={loaded().stats}
          person={loaded().person}
          itemFor={(titleId) => loaded().items[titleId]}
        />
      </div>
    </div>
  )
}
