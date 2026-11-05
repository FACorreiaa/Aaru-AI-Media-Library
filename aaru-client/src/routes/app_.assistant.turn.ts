import { createFileRoute } from '@tanstack/solid-router'
import { env } from 'cloudflare:workers'
import { proxyChatTurn } from '../lib/assistant/proxy'

// POST /app/assistant/turn?chat=…: one Chat turn with Aaru, streamed (ASK-009).
export const Route = createFileRoute('/app_/assistant/turn')({
  server: {
    handlers: {
      POST: ({ request }) => proxyChatTurn(request, env.API_BASE_URL),
    },
  },
})
