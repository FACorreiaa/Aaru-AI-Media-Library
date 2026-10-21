import { createFileRoute, redirect } from '@tanstack/solid-router'

// DESIGN.md §18: the old slug. A Trakt sign-in started before the move still returns here.
export const Route = createFileRoute('/_shell/app_/settings/imports')({
  beforeLoad: ({ search }) => {
    throw redirect({
      to: '/app/settings/import',
      search: search as Record<string, string>,
      replace: true,
    })
  },
})
