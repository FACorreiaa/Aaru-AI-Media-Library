import { createFileRoute } from '@tanstack/solid-router'
import { AccountPage } from '../components/settings/AccountPage'
import { loadAccountPage } from '../lib/settings/account'

export const Route = createFileRoute('/app_/settings/account')({
  head: () => ({ meta: [{ title: 'Account · Settings · Aaru' }] }),
  loader: () => loadAccountPage(),
  component: Account,
})

function Account() {
  const loaded = Route.useLoaderData()
  return <AccountPage data={loaded()} />
}
