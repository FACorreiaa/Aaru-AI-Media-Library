import { Show, createSignal, onMount } from 'solid-js'
import { keyBytes, pushSupport } from '../lib/push/model'
import type { PushSupport } from '../lib/push/model'
import {
  deleteSubscription,
  saveSubscription,
  setAiring,
} from '../lib/push/server'
import type { PushSetup } from '../lib/push/server'

// Airing alerts in this browser. "New episodes" is the account's switch, shared with the Apple
// apps; "this browser" is one push subscription. Permission is asked only on a tap.
export function NotificationsSection(props: { setup: PushSetup }) {
  const [airing, setAiringState] = createSignal(props.setup.airing)
  const [support, setSupport] = createSignal<PushSupport>('unsupported')
  const [subscribed, setSubscribed] = createSignal(false)
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)

  const fail = (error: unknown, fallback: string) =>
    setProblem(error instanceof Error ? error.message : fallback)

  onMount(async () => {
    setSupport(
      pushSupport({
        serviceWorker: 'serviceWorker' in navigator,
        pushManager: 'PushManager' in window,
        notification: 'Notification' in window,
        iOS: /iPad|iPhone|iPod/.test(navigator.userAgent),
        standalone: window.matchMedia('(display-mode: standalone)').matches,
      }),
    )
    if (support() !== 'supported') return
    const registration = await navigator.serviceWorker.getRegistration('/')
    setSubscribed(Boolean(await registration?.pushManager.getSubscription()))
  })

  async function toggleAiring(on: boolean) {
    setProblem(null)
    try {
      setAiringState(await setAiring({ data: { airing: on } }))
    } catch (error) {
      fail(error, 'That was not saved.')
    }
  }

  async function turnOn(publicKey: string) {
    setBusy(true)
    setProblem(null)
    try {
      if ((await Notification.requestPermission()) !== 'granted') {
        setProblem(
          'Notifications are blocked for Aaru in this browser. Allow them in the site settings, then try again.',
        )
        return
      }
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
      setSubscribed(true)
      if (!airing()) await toggleAiring(true)
    } catch (error) {
      fail(error, 'This browser could not be signed up for alerts.')
    } finally {
      setBusy(false)
    }
  }

  async function turnOff() {
    setBusy(true)
    setProblem(null)
    try {
      const registration = await navigator.serviceWorker.getRegistration('/')
      const subscription = await registration?.pushManager.getSubscription()
      if (subscription) {
        await deleteSubscription({ data: { endpoint: subscription.endpoint } })
        await subscription.unsubscribe()
      }
      setSubscribed(false)
    } catch (error) {
      fail(error, 'Alerts could not be turned off in this browser.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <section class="mt-10 rounded-[20px] bg-surface p-5">
      <h2 class="font-display text-xl font-medium">Notifications</h2>
      <label class="mt-3 flex items-start gap-2 text-sm">
        <input
          type="checkbox"
          class="mt-0.5"
          checked={airing()}
          onChange={(e) => void toggleAiring(e.currentTarget.checked)}
        />
        <span>
          New episodes
          <span class="block text-xs text-muted">
            When a show you are watching airs a new episode, on every device
            where alerts are on.
          </span>
        </span>
      </label>

      <Show
        when={props.setup.publicKey}
        fallback={
          <p class="mt-4 text-sm text-muted">
            Alerts in the browser are not available yet.
          </p>
        }
      >
        {(publicKey) => (
          <div class="mt-4">
            <Show when={support() === 'needs-install'}>
              <p class="text-sm text-muted">
                On iPhone and iPad, add Aaru to your Home Screen (Share → Add to
                Home Screen) and open it from there to get alerts.
              </p>
            </Show>
            <Show when={support() === 'unsupported'}>
              <p class="text-sm text-muted">
                This browser cannot show alerts from websites.
              </p>
            </Show>
            <Show when={support() === 'supported'}>
              <button
                type="button"
                class="min-h-11 rounded-full border border-ink/25 px-5 text-sm font-semibold disabled:opacity-50"
                disabled={busy()}
                onClick={() =>
                  void (subscribed() ? turnOff() : turnOn(publicKey()))
                }
              >
                {subscribed()
                  ? 'Turn off alerts in this browser'
                  : 'Turn on alerts in this browser'}
              </button>
            </Show>
          </div>
        )}
      </Show>

      <Show when={problem()}>
        {(message) => (
          <p role="alert" class="mt-3 text-sm text-danger">
            {message()}
          </p>
        )}
      </Show>
    </section>
  )
}
