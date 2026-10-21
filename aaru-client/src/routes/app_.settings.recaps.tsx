import { Link, createFileRoute } from '@tanstack/solid-router'
import { For } from 'solid-js'
import { SettingsPageTitle } from '../components/settings/SettingsNav'
import { periodLabel, recapShortcuts } from '../lib/recap/model'

export const Route = createFileRoute('/app_/settings/recaps')({
  head: () => ({ meta: [{ title: 'Insights & recaps · Settings · Aaru' }] }),
  component: Recaps,
})

function Recaps() {
  return (
    <>
      <SettingsPageTitle title="Insights & recaps" />
      <p class="mt-2 text-sm text-muted">
        What you watched and read, as a story you can share.
      </p>
      <div class="mt-4 flex flex-wrap gap-2">
        <Link
          to="/app/insights"
          class="rounded-full border border-line px-4 py-2 text-sm font-medium text-accent hover:bg-surface"
        >
          Insights
        </Link>
        <For each={recapShortcuts(new Date())}>
          {(period) => (
            <Link
              to="/app/recap"
              search={period}
              class="rounded-full bg-surface px-4 py-2 text-sm font-medium hover:text-accent"
            >
              {periodLabel(period)}
            </Link>
          )}
        </For>
      </div>
    </>
  )
}
