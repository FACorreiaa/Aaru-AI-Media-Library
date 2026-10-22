import { createFileRoute } from '@tanstack/solid-router'
import { Show } from 'solid-js'
import { ConcertPlaceSection } from '../components/ConcertPlaceSection'
import { FriendsSection } from '../components/settings/FriendsSection'
import { SettingsPageTitle } from '../components/settings/SettingsNav'
import { loadFriendsPage } from '../lib/settings/account'

// Settings → Friends & privacy (DESIGN.md §18).
export const Route = createFileRoute('/_shell/app_/settings/friends')({
  head: () => ({ meta: [{ title: 'Friends & privacy · Settings · Aaru' }] }),
  loader: () => loadFriendsPage(),
  component: Friends,
})

function Friends() {
  const loaded = Route.useLoaderData()
  return (
    <>
      <SettingsPageTitle
        title="Friends & privacy"
        description="Friends find you by your exact handle. Nobody can search or browse for you, and your library stays private."
      />
      <FriendsSection handle={loaded().handle} state={loaded().social} />
      <Show when={loaded().concerts?.available ? loaded().concerts : null}>
        {(setting) => <ConcertPlaceSection setting={setting()} />}
      </Show>
    </>
  )
}
