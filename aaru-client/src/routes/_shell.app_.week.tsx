import { createFileRoute, redirect } from '@tanstack/solid-router'

// UX-005: Calendar is the destination and Week one of its modes; old links keep working.
export const Route = createFileRoute('/_shell/app_/week')({
  beforeLoad: ({ search }) => {
    throw redirect({
      to: '/app/calendar',
      search: search as Record<string, string>,
      replace: true,
    })
  },
})
