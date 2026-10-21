import { createFileRoute, redirect } from '@tanstack/solid-router'

// DESIGN.md §18: "Connected apps" is now Connections.
export const Route = createFileRoute('/_shell/app_/settings/connected')({
  beforeLoad: () => {
    throw redirect({ to: '/app/settings/connections', replace: true })
  },
})
