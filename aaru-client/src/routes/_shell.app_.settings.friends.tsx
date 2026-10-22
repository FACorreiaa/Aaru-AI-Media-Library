import { createFileRoute } from '@tanstack/solid-router'
import { Show } from 'solid-js'
import { ConcertPlaceSection } from '../components/ConcertPlaceSection'
import { FriendsCard } from '../components/FriendsCard'
import { SettingsPageTitle } from '../components/settings/SettingsNav'
import { loadPrivacyPage } from '../lib/settings/account'

// Settings → Friends & privacy (DESIGN.md §18): who sees your library, and the concerts city.
// Friends themselves (invites, requests, profiles) are their own page, /app/friends.
export const Route = createFileRoute('/_shell/app_/settings/friends')({
  head: () => ({ meta: [{ title: 'Friends & privacy · Settings · Aaru' }] }),
  loader: () => loadPrivacyPage(),
  component: Friends,
})

function Friends() {
  const loaded = Route.useLoaderData()
  return (
    <>
      <SettingsPageTitle
        title="Friends & privacy"
        description="Nobody can search or browse for you, and your library stays private unless you show it to friends."
      />
      <FriendsCard handle={loaded().handle} settings={loaded().sharing} />
      <Show when={loaded().concerts?.available ? loaded().concerts : null}>
        {(setting) => <ConcertPlaceSection setting={setting()} />}
      </Show>
    </>
  )
}
