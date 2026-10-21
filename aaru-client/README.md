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
