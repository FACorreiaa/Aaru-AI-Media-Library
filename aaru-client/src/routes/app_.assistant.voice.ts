import { createFileRoute } from '@tanstack/solid-router'
import { env } from 'cloudflare:workers'
import { proxyTranscribe } from '../lib/assistant/proxy'

// POST /app/assistant/voice: a spoken question's audio, turned into text (ASK-009).
export const Route = createFileRoute('/app_/assistant/voice')({
  server: {
    handlers: {
      POST: ({ request }) => proxyTranscribe(request, env.API_BASE_URL),
    },
  },
})
