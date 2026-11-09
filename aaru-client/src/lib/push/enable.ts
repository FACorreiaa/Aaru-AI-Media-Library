import { keyBytes, pushSupport } from './model'
import type { PushSupport } from './model'
import { saveNotifications, saveSubscription } from './server'
import type { NotificationSettings } from './server'

// Turning alerts on in this browser, from Settings → Notifications and from the first run's
// alerts screen (ONB-001). Permission is asked only here, on a tap.

/** What this browser can do with push, read off `window`. Browser-only. */
export function browserPushSupport(): PushSupport {
  return pushSupport({
    serviceWorker: 'serviceWorker' in navigator,
    pushManager: 'PushManager' in window,
    notification: 'Notification' in window,
    iOS: /iPad|iPhone|iPod/.test(navigator.userAgent),
    standalone: window.matchMedia('(display-mode: standalone)').matches,
  })
}

export type TurnOnResult =
  /** The browser said no; nothing was subscribed. */
  | { kind: 'blocked' }
  /** Subscribed. `settings` are the account's switches after; `airingFailed` when New episodes
   * had to be turned on (no alert was on yet) and that was not saved. */
  | { kind: 'on'; settings: NotificationSettings; airingFailed: boolean }

/**
 * Asks for permission, subscribes this browser and saves the subscription. With every switch
 * off, an alert would never come, so New episodes goes on too. Throws when the browser could
 * not be subscribed.
 */
export async function turnOn(
  publicKey: string,
  settings: NotificationSettings,
): Promise<TurnOnResult> {
  if ((await Notification.requestPermission()) !== 'granted')
    return { kind: 'blocked' }
  const registration = await navigator.serviceWorker.register('/sw.js')
  await navigator.serviceWorker.ready
  const subscription = await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: keyBytes(publicKey),
  })
  const json = subscription.toJSON()
  await saveSubscription({
    data: {
      endpoint: subscription.endpoint,
      keys: {
        p256dh: json.keys?.p256dh ?? '',
        auth: json.keys?.auth ?? '',
      },
    },
  })
  if (Object.values(settings).some(Boolean))
    return { kind: 'on', settings, airingFailed: false }
  try {
    const saved = await saveNotifications({ data: { airing: true } })
    return { kind: 'on', settings: saved, airingFailed: false }
  } catch {
    return { kind: 'on', settings, airingFailed: true }
  }
}

/** The message for a browser that refused. */
export const BLOCKED_MESSAGE =
  'Notifications are blocked for Aaru in this browser. Allow them in the site settings, then try again.'
