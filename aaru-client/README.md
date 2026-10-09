# aaru-client

Aaru on the web: SvelteKit (Svelte 5, Kit 3) on Cloudflare Workers. A pure client of the
`/v1` API — no database, no business logic, no web-only endpoint. The landing page will
live here as a route group (`BACKLOG.md` LAND-001); the logged-in app is WEB-001.

## Commands

```bash
npm install
npm run dev          # local dev server
npm run check        # svelte-kit sync + svelte-check
npm run lint         # prettier --check + eslint
npm run test:ci      # vitest: server, client (browser), storybook projects, one at a time
npm run build        # production build (adapter-cloudflare)
npm run gen          # regenerate worker-configuration.d.ts after editing wrangler.jsonc
```

`wrangler types --check` is not part of `check` or `build`: its hash depends on the built
Worker entrypoint, so it fails on every fresh checkout (same choice as LuminaVaultWebApp).

```bash

```

`npx playwright install chromium` once before running browser tests locally.

## Channels

| Channel | Config                   | Worker                | Deployed by                        |
| ------- | ------------------------ | --------------------- | ---------------------------------- |
| Beta    | `wrangler.staging.jsonc` | `aaru-client-staging` | every merge to `main` after Web CI |
| Prod    | `wrangler.jsonc`         | `aaru-client`         | manual dispatch of Web Deploy      |

Both read `PUBLIC_API_BASE_URL` from the Worker's `vars` at request time
(`$app/env/public`) and point at the production API. The host is a placeholder until the
domain exists (REL-005).
