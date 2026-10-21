import { createFileRoute } from '@tanstack/solid-router'
import { ConnectionsSection } from '../components/ConnectionsSection'
import { StremioSection } from '../components/StremioSection'
import { SettingsPageTitle } from '../components/settings/SettingsNav'
import { listConnections } from '../lib/agents/server'
import { listStremio } from '../lib/stremio/server'

// Apps that reach Aaru with a token of their own: Stremio's addon and agents.
export const Route = createFileRoute('/app_/settings/connected')({
  head: () => ({ meta: [{ title: 'Connected apps · Settings · Aaru' }] }),
  loader: async () => {
    const [stremio, connections] = await Promise.all([
      listStremio(),
      listConnections(),
    ])
    return { stremio, connections }
  },
  component: Connected,
})

function Connected() {
  const loaded = Route.useLoaderData()
  return (
    <>
      <SettingsPageTitle title="Connected apps" />
      <StremioSection links={loaded().stremio} />
      <ConnectionsSection connections={loaded().connections} />
    </>
  )
}
