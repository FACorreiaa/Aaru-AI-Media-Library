// SCR-007: the handshake with Aaru's connect page (`/connect/extension`). Both sides talk with
// `window.postMessage` on the page's own origin. Mirrors `aaru-client/src/lib/agents/extension.ts`;
// change both together.

export const PING = 'aaru-extension:ping'
export const READY = 'aaru-extension:ready'
export const TOKEN = 'aaru-extension:token'
export const CONNECTED = 'aaru-extension:connected'

/** The port a streaming page's content script reports on. */
export const PLAYER_PORT = 'aaru-player'
