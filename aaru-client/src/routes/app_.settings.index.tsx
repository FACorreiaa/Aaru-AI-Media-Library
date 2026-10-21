import { createFileRoute, redirect } from '@tanstack/solid-router'
import { AccountPage } from '../components/settings/AccountPage'
import { SettingsList } from '../components/settings/SettingsNav'
import { loadAccountPage } from '../lib/settings/account'
import { optionalString } from '../lib/search-params'

// A phone sees the list of groups; a desktop sees Account beside the rail.
export const Route = createFileRoute('/app_/settings/')({
  head: () => ({ meta: [{ title: 'Settings · Aaru' }] }),
  // A Trakt sign-in started before Settings had pages still returns here.
  validateSearch: (search): { trakt?: string } => ({
    trakt: optionalString(search.trakt),
  }),
  beforeLoad: ({ search }) => {
    if (search.trakt !== undefined)
      throw redirect({
        to: '/app/settings/imports',
        search: { trakt: search.trakt },
      })
  },
  loader: () => loadAccountPage(),
  component: SettingsIndex,
})

function SettingsIndex() {
  const loaded = Route.useLoaderData()
  return (
    <>
      <SettingsList />
      <div class="hidden md:block">
        <AccountPage data={loaded()} />
      </div>
    </>
  )
}
