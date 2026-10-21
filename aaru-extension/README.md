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
