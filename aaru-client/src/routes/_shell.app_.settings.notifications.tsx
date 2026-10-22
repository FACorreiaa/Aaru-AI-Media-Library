import { createFileRoute } from '@tanstack/solid-router'
import { NotificationsSection } from '../components/NotificationsSection'
import { SettingsPageTitle } from '../components/settings/SettingsNav'
import { loadNotificationsPage } from '../lib/settings/account'

// Settings → Notifications (DESIGN.md §18).
export const Route = createFileRoute('/_shell/app_/settings/notifications')({
  head: () => ({ meta: [{ title: 'Notifications · Settings · Aaru' }] }),
  loader: () => loadNotificationsPage(),
  component: Notifications,
})

function Notifications() {
  const loaded = Route.useLoaderData()
  return (
    <>
      <SettingsPageTitle title="Notifications" />
      <NotificationsSection setup={loaded()} />
    </>
  )
}
