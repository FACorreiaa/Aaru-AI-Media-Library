import { createFileRoute } from '@tanstack/solid-router'
import { Show, Suspense, lazy } from 'solid-js'
import { ConcertPlaceSection } from '../components/ConcertPlaceSection'
import { FriendsCard } from '../components/FriendsCard'
import { SettingsPageTitle } from '../components/settings/SettingsNav'
import { loadPrivacyPage } from '../lib/settings/account'

// The country picker (a long Select) loads on its own: most visits here are about friends.
const SportSettingsSection = lazy(() =>
  import('../components/SportSettingsSection').then((m) => ({
    default: m.SportSettingsSection,
  })),
)

// Settings → Friends & privacy (DESIGN.md §18): who sees your library, the concerts city, and
// the Sports "Where to watch" country (SPT-003).
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
      <Show when={loaded().sports?.available ? loaded().sports : null}>
        {(setting) => (
          <Suspense>
            <SportSettingsSection setting={setting()} />
          </Suspense>
        )}
      </Show>
    </>
  )
}
