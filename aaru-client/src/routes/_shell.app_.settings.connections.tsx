import { createFileRoute } from '@tanstack/solid-router'
import { ConnectionsSection } from '../components/ConnectionsSection'
import { MusicSection } from '../components/MusicSection'
import { StremioSection } from '../components/StremioSection'
import { SettingsPageTitle } from '../components/settings/SettingsNav'
import { listConnections } from '../lib/agents/server'
import { latestListen, listScrobblers } from '../lib/music/server'
import { listStremio } from '../lib/stremio/server'

// Apps that reach Aaru with a token of their own: Stremio's addon, music scrobblers and agents.
export const Route = createFileRoute('/_shell/app_/settings/connections')({
  head: () => ({ meta: [{ title: 'Connected apps · Settings · Aaru' }] }),
  loader: async () => {
    const [stremio, scrobblers, latest, connections] = await Promise.all([
      listStremio(),
      listScrobblers(),
      // The last listen is a nicety; the page still loads without it.
      latestListen().catch(() => null),
      listConnections(),
    ])
    return { stremio, scrobblers, latest, connections }
  },
  component: Connected,
})

function Connected() {
  const loaded = Route.useLoaderData()
  return (
    <>
      <SettingsPageTitle title="Connected apps" />
      <StremioSection links={loaded().stremio} />
      <MusicSection scrobblers={loaded().scrobblers} latest={loaded().latest} />
      <ConnectionsSection connections={loaded().connections} />
    </>
  )
}
