import { createFileRoute, useNavigate } from '@tanstack/solid-router'
import { onMount } from 'solid-js'
import { AccountPage } from '../components/settings/AccountPage'
import { loadAccountPage } from '../lib/settings/account'

// Sections that lived on Account before DESIGN.md §18 and the page each now has.
const MOVED: Record<string, string> = {
  '#profile': '/app/settings/friends',
  '#friends': '/app/settings/friends',
  '#concerts': '/app/settings/friends',
  '#notifications': '/app/settings/notifications',
}

export const Route = createFileRoute('/_shell/app_/settings/account')({
  head: () => ({ meta: [{ title: 'Account · Settings · Aaru' }] }),
  loader: () => loadAccountPage(),
  component: Account,
})

function Account() {
  const loaded = Route.useLoaderData()
  const navigate = useNavigate()
  onMount(() => {
    const moved = MOVED[window.location.hash]
    if (moved) void navigate({ to: moved, replace: true })
  })
  return <AccountPage data={loaded()} />
}
