import { createFileRoute } from '@tanstack/solid-router'
import { env } from 'cloudflare:workers'
import { proxyAvatar } from '../lib/profile/avatar-proxy'

// GET /app/avatars/{userId}?v=: someone's avatar, same-origin, behind the session (SOC-001b).
export const Route = createFileRoute('/app_/avatars/$userId')({
  server: {
    handlers: {
      GET: ({ request, params }) =>
        proxyAvatar(request, params.userId, env.API_BASE_URL),
    },
  },
})
