# aaru-extension

Aaru's browser extension (SCR-007). One Manifest V3 source for Chrome and Firefox, built with
[WXT](https://wxt.dev). It reads what plays on Netflix, Disney+ and Prime Video from the
player's title overlay and URL, follows the page's main `<video>`, and scrobbles to
`POST /v1/scrobble/start|pause|stop` with a token that can only scrobble. It draws nothing on
those sites, never controls the player, and reads nothing else.

```bash
npm install
npm run dev            # Chrome with the extension loaded; dev:firefox for Firefox
npm run build          # .output/chrome-mv3 and .output/firefox-mv3
npm test && npm run typecheck && npm run lint && npm run check
npm run zip            # store packages, submitted by the owner
```

Against a local stack, set `WXT_API_BASE=http://localhost:8080` and
`WXT_WEB_BASE=http://localhost:3000` before `npm run dev`; development builds also allow
`localhost` for the API and the connect page.

## How it fits

- `src/entrypoints/connect.content.ts` — on `aaruapp.com/connect/extension`, answers the page and
  takes the token it hands over (`src/lib/protocol.ts`, mirrored in
  `aaru-client/src/lib/agents/extension.ts`).
- `src/entrypoints/streaming.content.ts` — on the three sites, reports what it sees to the
  background on a port, every few seconds and on video events.
- `src/lib/session.ts` — turns those reports into `start` (also every 5 minutes), `pause` and
  `stop` (end of video, next episode, tab gone). Aaru decides from the stop's progress.
- `src/entrypoints/background.ts` — sends them, retries stops for a day, keeps what the popup
  shows, and sets the badge: ✓ matched, ? not matched, ! connect again.
- `src/sites/*` — one reader per site. **These depend on each site's markup**; when one stops
  matching, update its selectors and the fixture in `src/sites/sites.test.ts` from the live page.

## Error reporting (Sentry)

Errors only, to the `aaru-extension` project (EU), as `docs/privacy.md` says. A store build
(`npm run build` / `npm run zip`) reports to the project's DSN in `src/lib/reporting/config.ts`;
`npm run dev` reports nothing. Set `WXT_SENTRY_DSN=` (empty) to build one with reporting off, and
pass the release for readable issues:

```bash
WXT_SENTRY_RELEASE=$(git rev-parse HEAD) npm run zip
```

`WXT_SENTRY_ENVIRONMENT` defaults to `production` (`development` under `npm run dev`); the
release defaults to `aaru-extension@<version>`. A DSN is public, not a secret.

- `src/lib/reporting/reporter.ts` — the background's Sentry client, the only one: a
  `BrowserClient` on its own `Scope`, never `Sentry.init`, with no integration that wraps
  timers, listeners, `fetch`, `console` or `history`. No breadcrumbs, no tracing, no user.
- `src/lib/reporting/content.ts` — the content scripts load no Sentry code and install
  nothing on the page. What can fail runs in `reporter.guard`; an error goes to the
  background as name, message and stack, and is reported with the site's **origin** only.
  The path names what the user watches, so it never leaves (`src/lib/reporting/scrub.ts`).
- `src/lib/reporting/deliver.ts` — posts from the background without cookies or a referrer.
  In Firefox only after the user allowed "technical and interaction data", which the manifest
  declares as optional (Mozilla does not let that category be required). Firefox shows it at
  install and in about:addons.
