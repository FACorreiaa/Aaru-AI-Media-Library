import { Outlet, createFileRoute } from '@tanstack/solid-router'
import {
  SettingsRail,
  useSettingsIndex,
} from '../components/settings/SettingsNav'

// DESIGN.md §18: Settings is eight pages. From 768px the sub-nav sits beside the page; a phone
// lists the pages at /app/settings and opens one at a time.
export const Route = createFileRoute('/_shell/app_/settings')({
  component: SettingsLayout,
})

function SettingsLayout() {
  const atIndex = useSettingsIndex()
  return (
    <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
      <h1
        class="font-display text-4xl font-medium tracking-tight"
        classList={{ 'max-md:sr-only': !atIndex() }}
      >
        Settings
      </h1>
      <div class="mt-6 md:mt-8 md:grid md:grid-cols-[12rem_minmax(0,1fr)] md:gap-10 xl:gap-14">
        <SettingsRail />
        <div class="min-w-0 max-w-3xl">
          <Outlet />
        </div>
      </div>
    </div>
  )
}
