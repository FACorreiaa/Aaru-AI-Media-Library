import { createFileRoute, redirect, useNavigate } from '@tanstack/solid-router'
import { onMount } from 'solid-js'
import { SettingsList } from '../components/settings/SettingsNav'
import { optionalString } from '../lib/search-params'

// UX-033: a phone sees the list of pages; from 768px, where the sub-nav is beside the page,
// /app/settings is Account. Old anchors (#profile, #friends…) land on their page.
const ANCHORS: Partial<Record<string, string>> = {
  '#profile': '/app/settings/friends',
  '#friends': '/app/settings/friends',
  '#handle': '/app/settings/account',
  '#notifications': '/app/settings/notifications',
  '#concerts': '/app/settings/friends',
  '#imports': '/app/settings/import',
}

export const Route = createFileRoute('/_shell/app_/settings/')({
  head: () => ({ meta: [{ title: 'Settings · Aaru' }] }),
  // A Trakt sign-in started before Settings had pages still returns here.
  validateSearch: (search): { trakt?: string } => ({
    trakt: optionalString(search.trakt),
  }),
  beforeLoad: ({ search }) => {
    if (search.trakt !== undefined)
      throw redirect({
        to: '/app/settings/import',
        search: { trakt: search.trakt },
      })
  },
  component: SettingsIndex,
})

function SettingsIndex() {
  const navigate = useNavigate()
  onMount(() => {
    const anchored = ANCHORS[window.location.hash]
    const wide = window.matchMedia('(min-width: 48rem)').matches
    const to = anchored ?? (wide ? '/app/settings/account' : null)
    if (to) void navigate({ to, replace: true })
  })
  return <SettingsList />
}
