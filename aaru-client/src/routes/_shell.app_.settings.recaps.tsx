import { createFileRoute, redirect } from '@tanstack/solid-router'

// DESIGN.md §18: the recap shortcuts live on Your data; Insights is in the sidebar.
export const Route = createFileRoute('/_shell/app_/settings/recaps')({
  beforeLoad: () => {
    throw redirect({ to: '/app/settings/data', replace: true })
  },
})
