import { createFileRoute } from '@tanstack/solid-router'
import { env } from 'cloudflare:workers'
import { proxyExport } from '../lib/export/proxy'

// GET /app/export?format=json|csv: the account export as a native browser download.
export const Route = createFileRoute('/app_/export')({
  server: {
    handlers: {
      GET: ({ request }) => proxyExport(request, env.API_BASE_URL),
    },
  },
})
