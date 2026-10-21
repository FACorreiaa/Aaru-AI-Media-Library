import { createFileRoute } from '@tanstack/solid-router'
import { appleAppSiteAssociation } from '../../lib/links/apple'

// GET /.well-known/apple-app-site-association: universal links for invites (SOC-002).
export const Route = createFileRoute('/.well-known/apple-app-site-association')(
  {
    server: {
      handlers: {
        GET: () => appleAppSiteAssociation(),
      },
    },
  },
)
