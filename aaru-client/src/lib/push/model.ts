// What this browser can do with push, decided from facts the component reads off `window`.

export type PushSupport = 'supported' | 'needs-install' | 'unsupported'

export function pushSupport(env: {
  serviceWorker: boolean
  pushManager: boolean
  notification: boolean
  iOS: boolean
  standalone: boolean
}): PushSupport {
  // Safari on iPhone and iPad only offers push to a site added to the Home Screen.
  if (env.iOS && !env.standalone) return 'needs-install'
  return env.serviceWorker && env.pushManager && env.notification
    ? 'supported'
    : 'unsupported'
}

/** A base64url VAPID key as the bytes `pushManager.subscribe` wants. */
export function keyBytes(base64url: string): Uint8Array<ArrayBuffer> {
  const padded = base64url.replace(/-/g, '+').replace(/_/g, '/')
  const binary = atob(padded + '='.repeat((4 - (padded.length % 4)) % 4))
  const bytes = new Uint8Array(new ArrayBuffer(binary.length))
  for (let index = 0; index < binary.length; index++)
    bytes[index] = binary.charCodeAt(index)
  return bytes
}
