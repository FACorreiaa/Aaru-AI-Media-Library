import { For, Show, createSignal, onMount } from 'solid-js'
import { keyBytes, pushSupport } from '../lib/push/model'
import type { PushSupport } from '../lib/push/model'
import {
  deleteSubscription,
  saveNotifications,
  saveSubscription,
} from '../lib/push/server'
import type { NotificationSettings, PushSetup } from '../lib/push/server'
import { Button } from './ui/button'
import { Card } from './ui/card'
import { Switch } from './ui/switch'

type SettingKey = keyof NotificationSettings

const switches: { key: SettingKey; label: string; detail: string }[] = [
  {
    key: 'airing',
    label: 'New episodes',
    detail: 'When a show you are watching airs a new episode.',
  },
  {
    key: 'groupMentions',
    label: 'Mentions in groups',
    detail:
      'When someone tags you in a group you have not muted. The alert says who and where, never what they wrote.',
  },
  {
    key: 'groupInvites',
    label: 'Group invites',
    detail: 'When a friend invites you into a group.',
  },
]

// Alerts in this browser. The switches are the account's, shared with the Apple apps, and reach
// every device where alerts are on; "this browser" is one push subscription. Permission is asked
// only on a tap.
export function NotificationsSection(props: { setup: PushSetup }) {
  const [settings, setSettings] = createSignal(props.setup.settings)
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

  async function toggle(key: SettingKey, on: boolean) {
    const before = settings()
    setProblem(null)
    // The switch moves at once; the server's answer decides.
    setSettings({ ...before, [key]: on })
    try {
      setSettings(await saveNotifications({ data: { [key]: on } }))
    } catch (error) {
      setSettings(before)
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
      if (!Object.values(settings()).some(Boolean)) await toggle('airing', true)
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
    <Card class="mt-10 p-5">
      <h2 class="font-display text-xl font-medium">Notifications</h2>
      <For each={switches}>
        {(item) => (
          <Switch
            class="mt-3 flex items-start gap-3 text-sm"
            checked={settings()[item.key]}
            onChange={(checked) => void toggle(item.key, checked)}
            label={item.label}
            description={item.detail}
          />
        )}
      </For>

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
              <Button
                disabled={busy()}
                onClick={() =>
                  void (subscribed() ? turnOff() : turnOn(publicKey()))
                }
              >
                {subscribed()
                  ? 'Turn off alerts in this browser'
                  : 'Turn on alerts in this browser'}
              </Button>
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
    </Card>
  )
}
