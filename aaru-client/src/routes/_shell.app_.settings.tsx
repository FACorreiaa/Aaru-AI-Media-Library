import { Outlet, createFileRoute } from '@tanstack/solid-router'
import {
  SettingsRail,
  useSettingsIndex,
} from '../components/settings/SettingsNav'
import { Toaster } from '~/components/ui'

// APP-007 on the web: Settings in groups. Desktop keeps the groups in a rail beside the page;
// a phone lists the groups and opens one at a time.
export const Route = createFileRoute('/_shell/app_/settings')({
  component: SettingsLayout,
})

function SettingsLayout() {
  const atIndex = useSettingsIndex()
  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
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
      </div>
      {/* The Connected apps page's "Copied" toasts. */}
      <Toaster />
    </div>
  )
}
