import { defineConfig } from 'vite'
import { devtools } from '@tanstack/devtools-vite'
import tailwindcss from '@tailwindcss/vite'

import { tanstackStart } from '@tanstack/solid-start/plugin/vite'

import solidPlugin from 'vite-plugin-solid'
import { cloudflare } from '@cloudflare/vite-plugin'
import { sentryVitePlugin } from '@sentry/vite-plugin'
import { unstable_readConfig } from 'wrangler'

// The project has no Node types; the config only reads the environment.
declare const process: { env: Record<string, string | undefined> }

// Error reporting (docs/privacy.md). The browser's DSN and channel come from the same
// wrangler.jsonc vars the Worker reads at runtime (`SENTRY_DSN`, `CHANNEL`), for the
// environment being built (`CLOUDFLARE_ENV`). The release is the commit CI builds.
const workerVars = unstable_readConfig({
  config: 'wrangler.jsonc',
  env: process.env.CLOUDFLARE_ENV || undefined,
}).vars as Record<string, unknown>
const text = (value: unknown) => (typeof value === 'string' ? value : '')
const release = process.env.SENTRY_RELEASE || process.env.GITHUB_SHA || ''

// Source maps go to Sentry only from CI (SENTRY_AUTH_TOKEN set), and are deleted from the
// output after the upload so they are never served or deployed.
const uploadSourceMaps = Boolean(process.env.SENTRY_AUTH_TOKEN)

export default defineConfig({
  resolve: { tsconfigPaths: true },
  // The legal pages render the repo's own docs (docs/privacy.md) at build time.
  server: {
    fs: { allow: ['.', '../docs'] },
  },
  define: {
    'import.meta.env.VITE_SENTRY_DSN': JSON.stringify(
      text(workerVars.SENTRY_DSN),
    ),
    'import.meta.env.VITE_SENTRY_ENVIRONMENT': JSON.stringify(
      text(workerVars.CHANNEL),
    ),
    'import.meta.env.VITE_SENTRY_RELEASE': JSON.stringify(release),
  },
  build: uploadSourceMaps ? { sourcemap: 'hidden' } : {},
  plugins: [
    devtools(),
    cloudflare({ viteEnvironment: { name: 'ssr' } }),
    tailwindcss(),
    tanstackStart(),
    solidPlugin({ ssr: true }),
    uploadSourceMaps &&
      sentryVitePlugin({
        org: process.env.SENTRY_ORG || 'fernando-lda',
        project: process.env.SENTRY_PROJECT || 'aaru-web',
        authToken: process.env.SENTRY_AUTH_TOKEN,
        url: process.env.SENTRY_URL || 'https://de.sentry.io/',
        release: release ? { name: release } : undefined,
        telemetry: false,
        sourcemaps: { filesToDeleteAfterUpload: ['./dist/**/*.map'] },
      }),
  ],
})
