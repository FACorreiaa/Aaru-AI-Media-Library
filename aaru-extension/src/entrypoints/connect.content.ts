import { browser, defineContentScript } from '#imports'
import { CONNECTED, PING, READY, TOKEN } from '../lib/protocol'

const reply = (message: object) =>
  window.postMessage(message, window.location.origin)

/** Hands the token to the background, and tells the page once it is stored. */
async function store(secret: string) {
  const stored: unknown = await browser.runtime.sendMessage({
    type: TOKEN,
    secret,
  })
  if (stored === true) reply({ type: CONNECTED })
}

// SCR-007: on Aaru's connect page, answer the page and take the token it hands over. Only
// messages from this page's own window and origin count.
export default defineContentScript({
  matches: [
    'https://aaruapp.com/connect/extension*',
    'https://beta.aaruapp.com/connect/extension*',
    ...(import.meta.env.MODE === 'development'
      ? ['http://localhost/connect/extension*']
      : []),
  ],
  runAt: 'document_start',
  main() {
    window.addEventListener('message', (event: MessageEvent) => {
      if (event.source !== window || event.origin !== window.location.origin)
        return
      const data: { type?: unknown; secret?: unknown } | null = event.data
      if (data?.type === PING)
        reply({ type: READY, version: browser.runtime.getManifest().version })
      if (data?.type === TOKEN && typeof data.secret === 'string')
        void store(data.secret)
    })
    reply({ type: READY, version: browser.runtime.getManifest().version })
  },
})
