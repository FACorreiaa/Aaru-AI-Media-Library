import { createFileRoute } from '@tanstack/solid-router'
import { env } from 'cloudflare:workers'
import { proxyChatAttachment } from '../lib/assistant/proxy'

// POST and DELETE /app/assistant/attach?chat=…: a file in a Chat with Aaru (ASK-010).
export const Route = createFileRoute('/app_/assistant/attach')({
  server: {
    handlers: {
      POST: ({ request }) => proxyChatAttachment(request, env.API_BASE_URL),
      DELETE: ({ request }) => proxyChatAttachment(request, env.API_BASE_URL),
    },
  },
})
