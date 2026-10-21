import { QueryClient } from '@tanstack/solid-query'

// The cache in front of the server functions. Loaders read through it, so hovering a link
// preloads the page and Back shows it from memory. Anything older than this is fetched again.
const STALE_MS = 30_000

let browserClient: QueryClient | undefined

function createQueryClient() {
  return new QueryClient({
    defaultOptions: { queries: { staleTime: STALE_MS } },
  })
}

/** One client per request on the server, so users never share one; one per tab in the
 * browser. */
export function getContext() {
  if (typeof window === 'undefined') return { queryClient: createQueryClient() }
  browserClient ??= createQueryClient()
  return { queryClient: browserClient }
}

/** The tab's client, for code outside the component tree. Undefined on the server. */
export function browserQueryClient(): QueryClient | undefined {
  return browserClient
}
