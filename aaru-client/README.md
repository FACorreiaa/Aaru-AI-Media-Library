# aaru-client

Aaru on the web: the landing page, sign-in, and the signed-in app. SolidJS + TanStack Start on
Cloudflare Workers, a pure client of the `/v1` API with the same functionality as the Apple apps.

```bash
npm install
printf 'API_BASE_URL=http://localhost:8080\nCHANNEL=dev\n' > .dev.vars   # local API
npm run dev            # http://localhost:3000

npm run check && npm run lint && npm run typecheck && npm test && npm run build
npm run api:generate   # after any change to aaru-server/Sources/AppAPI/openapi.yaml
npm run cf:types       # after changing vars in wrangler.jsonc
```

- `src/routes/index.tsx`: the landing page. It never reads the session.
- `src/routes/sign-in.tsx`, `src/routes/app.tsx`: sign-in and the signed-in app.
- `src/lib/session/`: the session. The token sits in an HttpOnly cookie; server functions send
  every `/v1` call with it, so page scripts never see it. A 401 clears it once. `query.ts`
  checks it once per tab for the app's pages.
- `src/lib/queries.ts`: the shared reads, as TanStack Query options. Loaders and rows read
  through them; a POST marks them old (`src/start.ts`).
- `src/lib/api/`: the `/v1` client. `schema.d.ts` is generated from the server's spec, the same
  spec the Apple apps' `AaruAPI` comes from; CI fails if it is stale.

Deploys (REL-006): every merge to `main` builds with `CLOUDFLARE_ENV=staging` and deploys the
beta Worker; the production Worker deploys only on manual dispatch of "Web Deploy". Both use
the production API.

## Error reporting (Sentry)

Errors and crashes only, as `docs/privacy.md` says: no tracing, session replay, profiling,
feedback widget, session pings or console capture. URLs lose their query string and fragment;
cookies, headers, request bodies and the user are never sent (`src/lib/observability/scrub.ts`).

| Name                           | Where                                                                    | What                                                                                                                                             |
| ------------------------------ | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `SENTRY_DSN`                   | `wrangler.jsonc` `vars`, top level (production) and `env.staging` (beta) | The `aaru-web` project's DSN. Public, not a secret. Empty turns reporting off: the Worker is not wrapped and the browser never downloads the SDK |
| `SENTRY_RELEASE`               | build env (CI sets the commit SHA; falls back to `GITHUB_SHA`)           | The release on every event, browser and Worker                                                                                                   |
| `SENTRY_AUTH_TOKEN`            | GitHub secret, read by `web-deploy.yml`                                  | Uploads source maps to Sentry (EU, `de.sentry.io`) and deletes the `.map` files from `dist/`. Unset, the build skips it                          |
| `SENTRY_ORG`, `SENTRY_PROJECT` | GitHub variables (`fernando-lda`, `aaru-web`)                            | Where the source maps go                                                                                                                         |

- The Worker entry is `src/server.ts`: Start's handler, wrapped with `withSentry` when
  `SENTRY_DSN` is set. `src/lib/observability/middleware.ts` reports what pages and server
  functions throw before Start turns it into a response.
- In the browser, `src/lib/observability/browser.ts` loads `sdk.ts` with `import()` after
  hydration, so the SDK is an async chunk outside every route's budget. The build reads the
  DSN and `CHANNEL` (the Sentry environment) from `wrangler.jsonc` for `CLOUDFLARE_ENV`.
- After changing a var, run `npm run cf:types`.
