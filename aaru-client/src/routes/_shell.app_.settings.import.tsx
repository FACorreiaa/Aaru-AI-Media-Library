import { createFileRoute, useNavigate } from '@tanstack/solid-router'
import { onMount } from 'solid-js'
import { ImportsPage } from '../components/settings/ImportsPage'
import { traktResult } from '../lib/imports/model'
import { getTraktConnection, listImports } from '../lib/imports/server'
import { optionalString } from '../lib/search-params'

export const Route = createFileRoute('/_shell/app_/settings/import')({
  head: () => ({ meta: [{ title: 'Import · Settings · Aaru' }] }),
  // Trakt's sign-in comes back here with `?trakt=connected|denied|failed`.
  validateSearch: (search): { trakt?: string } => ({
    trakt: optionalString(search.trakt),
  }),
  loader: async () => {
    const [imports, trakt] = await Promise.all([
      listImports(),
      getTraktConnection(),
    ])
    return { imports, trakt }
  },
  component: Imports,
})

function Imports() {
  const loaded = Route.useLoaderData()
  const search = Route.useSearch()
  const navigate = useNavigate()
  const traktReturn = traktResult(search().trakt)
  // The result is read once; a reload should not repeat it.
  onMount(() => {
    if (search().trakt !== undefined)
      void navigate({
        to: '/app/settings/import',
        search: {},
        replace: true,
      })
  })
  return (
    <ImportsPage
      imports={loaded().imports}
      trakt={loaded().trakt}
      traktReturn={traktReturn}
    />
  )
}
