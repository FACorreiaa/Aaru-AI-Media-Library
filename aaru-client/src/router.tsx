import { createRouter as createTanStackRouter } from '@tanstack/solid-router'
import { setupRouterSsrQueryIntegration } from '@tanstack/solid-router-ssr-query'
import { routeTree } from './routeTree.gen'
import { NotFound, RouteError } from './components/RouteError'

import { getContext } from './integrations/tanstack-query/provider'

export function getRouter() {
  const context = getContext()
  const router = createTanStackRouter({
    routeTree,

    context,

    scrollRestoration: true,
    defaultPreload: 'intent',
    // The query cache decides what is fresh, so a preload always asks it.
    defaultPreloadStaleTime: 0,
    defaultErrorComponent: RouteError,
    defaultNotFoundComponent: NotFound,
  })

  // What the server's loaders fetched lands in the browser's cache, not fetched twice.
  setupRouterSsrQueryIntegration({ router, queryClient: context.queryClient })

  return router
}

declare module '@tanstack/solid-router' {
  interface Register {
    router: ReturnType<typeof getRouter>
  }
}
