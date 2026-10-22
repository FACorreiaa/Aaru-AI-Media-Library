import {
  HeadContent,
  Outlet,
  Scripts,
  createRootRouteWithContext,
} from '@tanstack/solid-router'
import { HydrationScript } from 'solid-js/web'
import type { QueryClient } from '@tanstack/solid-query'
import { Suspense, onMount } from 'solid-js'
import styleCss from '../styles.css?url'
import { DAYPART_SCRIPT, themeColorMeta } from '../lib/appearance'
import { readAppearance } from '../lib/appearance-read'
import { startBrowserErrorReporting } from '../lib/observability/browser'

export const Route = createRootRouteWithContext<{ queryClient: QueryClient }>()(
  {
    // Settings re-runs this (router.invalidate) after the appearance changes.
    loader: () => ({ appearance: readAppearance() }),
    head: ({ loaderData }) => ({
      meta: [
        { charset: 'utf-8' },
        { name: 'viewport', content: 'width=device-width, initial-scale=1' },
        ...themeColorMeta(loaderData?.appearance ?? 'system'),
      ],
      links: [
        { rel: 'stylesheet', href: styleCss },
        // The display face is on nearly every page's first screen.
        {
          rel: 'preload',
          href: '/fonts/newsreader-roman.woff2',
          as: 'font',
          type: 'font/woff2',
          crossOrigin: 'anonymous',
        },
        { rel: 'icon', href: '/favicon.ico', sizes: '32x32' },
        {
          rel: 'icon',
          href: '/favicon.png',
          type: 'image/png',
          sizes: '64x64',
        },
        { rel: 'apple-touch-icon', href: '/apple-touch-icon.png' },
        { rel: 'manifest', href: '/manifest.webmanifest' },
      ],
      scripts: [{ children: DAYPART_SCRIPT }],
    }),
    shellComponent: RootComponent,
  },
)

function RootComponent() {
  const data = Route.useLoaderData()
  // After hydration, so the reporting chunk never delays the first paint. No DSN, no chunk.
  onMount(() => void startBrowserErrorReporting())
  const theme = () => {
    const appearance = data().appearance
    return appearance === 'system' ? undefined : appearance
  }
  return (
    <html lang="en" data-theme={theme()}>
      <head>
        <HydrationScript />
        <HeadContent />
      </head>
      <body>
        <Suspense>
          <Outlet />
        </Suspense>
        <Scripts />
      </body>
    </html>
  )
}
