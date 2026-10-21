// SCR-007: the handshake between the connect page and Aaru's browser extension. The extension's
// content script runs on this page only; both sides talk with `window.postMessage` on this
// origin, so no other site can hand the extension a token or read one. Mirrored in
// `aaru-extension/src/protocol.ts`; change both together.

/** Page → extension: are you there? Extension → page: `ready`. */
export const PING = 'aaru-extension:ping'
export const READY = 'aaru-extension:ready'
/** Page → extension: the new token. Extension → page: `connected` once it is stored. */
export const TOKEN = 'aaru-extension:token'
export const CONNECTED = 'aaru-extension:connected'

export type ExtensionMessage =
  | { type: typeof PING }
  | { type: typeof READY; version: string }
  | { type: typeof TOKEN; secret: string }
  | { type: typeof CONNECTED }

const TYPES = new Set<string>([PING, READY, TOKEN, CONNECTED])

/** A message from this page's own window and origin, of a type the handshake knows. */
export function extensionMessage(
  event: Pick<MessageEvent, 'data' | 'origin' | 'source'>,
  self: { origin: string; window: unknown },
): ExtensionMessage | null {
  if (event.source !== self.window || event.origin !== self.origin) return null
  const data: unknown = event.data
  if (typeof data !== 'object' || data === null) return null
  const type = (data as { type?: unknown }).type
  return typeof type === 'string' && TYPES.has(type)
    ? (data as ExtensionMessage)
    : null
}

/** Where to get the extension. Empty until each store has listed it (owner submits). */
export const EXTENSION_STORES: { label: string; href: string }[] = []

/** How long the page waits for the extension to answer before saying it is not installed. */
export const READY_TIMEOUT_MS = 2500
/** How long it waits for the extension to store a token before taking the token back. */
export const STORE_TIMEOUT_MS = 5000
