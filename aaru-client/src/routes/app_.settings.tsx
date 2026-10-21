import { Outlet, createFileRoute, redirect } from '@tanstack/solid-router'
import { AppHeader } from '../components/AppHeader'
import {
  SettingsRail,
  useSettingsIndex,
} from '../components/settings/SettingsNav'
import { Toaster } from '../components/ui/toast'
import { getSession } from '../lib/session/session'

// APP-007 on the web: Settings in groups. Desktop keeps the groups in a rail beside the page;
// a phone lists the groups and opens one at a time.
export const Route = createFileRoute('/app_/settings')({
  beforeLoad: async () => {
    const session = await getSession()
    if (!session.signedIn) throw redirect({ to: '/sign-in' })
  },
  component: SettingsLayout,
})

function SettingsLayout() {
  const atIndex = useSettingsIndex()
  return (
    <div class="min-h-[100dvh]">
      <AppHeader class="max-w-5xl" />
      <main class="mx-auto max-w-5xl px-5 pb-20 md:px-8">
        <h1
          class="mt-4 font-display text-4xl font-medium tracking-tight"
          classList={{ 'max-md:sr-only': !atIndex() }}
        >
          Settings
        </h1>
        <div class="mt-6 md:mt-8 md:grid md:grid-cols-[11rem_minmax(0,1fr)] md:gap-10">
          <SettingsRail />
          <div class="max-w-3xl min-w-0">
            <Outlet />
          </div>
        </div>
      </main>
      {/* The Connected apps page's "Copied" toasts. */}
      <Toaster />
    </div>
  )
}
