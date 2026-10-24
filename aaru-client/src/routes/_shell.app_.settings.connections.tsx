import { createFileRoute, useNavigate } from '@tanstack/solid-router'
import { Show, onMount } from 'solid-js'
import { ConnectionsSection } from '../components/ConnectionsSection'
import { MALSection } from '../components/MALSection'
import { MusicSection } from '../components/MusicSection'
import { StremioSection } from '../components/StremioSection'
import { SettingsPageTitle } from '../components/settings/SettingsNav'
import { listConnections } from '../lib/agents/server'
import { malResult } from '../lib/mal/model'
import { getMALConnection } from '../lib/mal/server'
import { latestListen, listScrobblers } from '../lib/music/server'
import { listStremio } from '../lib/stremio/server'
import { optionalString } from '../lib/search-params'
import { Alert, AlertDescription } from '~/components/ui'

// Settings → Connections (DESIGN.md §18): everything that reaches Aaru with a token of its own,
// agents first, then Stremio's addon, MyAnimeList and music scrobblers. One verb ends each:
// Disconnect.
export const Route = createFileRoute('/_shell/app_/settings/connections')({
  head: () => ({ meta: [{ title: 'Connections · Settings · Aaru' }] }),
  // MyAnimeList's sign-in comes back here with `?mal=connected|denied|failed`.
  validateSearch: (search): { mal?: string } => ({
    mal: optionalString(search.mal),
  }),
  loader: async () => {
    const [stremio, scrobblers, latest, connections, mal] = await Promise.all([
      listStremio(),
      listScrobblers(),
      // The last listen is a nicety; the page still loads without it.
      latestListen().catch(() => null),
      listConnections(),
      getMALConnection(),
    ])
    return { stremio, scrobblers, latest, connections, mal }
  },
  component: Connected,
})

function Connected() {
  const loaded = Route.useLoaderData()
  const search = Route.useSearch()
  const navigate = useNavigate()
  const malReturn = malResult(search().mal)
  // The result is read once; a reload should not repeat it.
  onMount(() => {
    if (search().mal !== undefined)
      void navigate({
        to: '/app/settings/connections',
        search: {},
        replace: true,
      })
  })
  return (
    <>
      <SettingsPageTitle title="Connections" />
      <Show when={malReturn}>
        {(result) =>
          result().ok ? (
            <p role="status" class="mb-6 rounded-panel bg-surface p-3 text-sm">
              {result().message}
            </p>
          ) : (
            <Alert variant="destructive" class="mb-6">
              <AlertDescription>{result().message}</AlertDescription>
            </Alert>
          )
        }
      </Show>
      <ConnectionsSection connections={loaded().connections} />
      <StremioSection links={loaded().stremio} />
      <MALSection
        connection={loaded().mal}
        returnTo={() => `${window.location.origin}/app/settings/connections`}
      />
      <MusicSection scrobblers={loaded().scrobblers} latest={loaded().latest} />
    </>
  )
}
