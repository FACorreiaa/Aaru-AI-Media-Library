import { browser, defineContentScript } from '#imports'
import { CONNECTED, PING, READY, TOKEN } from '../lib/protocol'

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
    const reply = (message: object) =>
      window.postMessage(message, window.location.origin)
    window.addEventListener('message', (event: MessageEvent) => {
      if (event.source !== window || event.origin !== window.location.origin)
        return
      const data = event.data as { type?: unknown; secret?: unknown } | null
      if (data?.type === PING)
        reply({ type: READY, version: browser.runtime.getManifest().version })
      if (data?.type === TOKEN && typeof data.secret === 'string') {
        void browser.runtime
          .sendMessage({ type: TOKEN, secret: data.secret })
          .then((stored: unknown) => {
            if (stored === true) reply({ type: CONNECTED })
          })
      }
    })
    reply({ type: READY, version: browser.runtime.getManifest().version })
  },
})
