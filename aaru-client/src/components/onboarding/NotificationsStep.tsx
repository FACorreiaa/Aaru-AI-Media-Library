import { Show, createSignal } from 'solid-js'
import { Button } from '~/components/ui'
import type { OnboardingPick } from '../../lib/onboarding/model'
import { BLOCKED_MESSAGE, turnOn } from '../../lib/push/enable'
import type { PushSetup } from '../../lib/push/server'
import { Poster } from '../Poster'
import { PillButton, StepFrame } from './StepFrame'

// Never miss a new episode (DESIGN.md §0a, the last step): a sample alert for one of the shows
// picked as Watching, then the browser's own permission prompt on a tap. Shown only where push
// works and a show or anime is in progress: airing alerts follow those alone.

export function NotificationsStep(props: {
  sample: OnboardingPick | null
  setup: PushSetup
  onDone: () => void
  busy: boolean
}) {
  const [working, setWorking] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  // Subscribed, but New episodes could not be switched on: say so and let them go on.
  const [halfway, setHalfway] = createSignal(false)

  async function enable(publicKey: string) {
    setWorking(true)
    setProblem(null)
    try {
      const result = await turnOn(publicKey, props.setup.settings)
      if (result.kind === 'blocked') {
        setProblem(BLOCKED_MESSAGE)
        return
      }
      if (result.airingFailed) {
        setHalfway(true)
        setProblem(
          'Alerts are on in this browser, but New episodes was not switched on. Turn it on in Settings → Notifications.',
        )
        return
      }
      props.onDone()
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : 'This browser could not be signed up for alerts.',
      )
    } finally {
      setWorking(false)
    }
  }

  return (
    <StepFrame
      title="Never miss a new episode"
      body="Aaru tells you when a show you are watching airs its next one. Nothing else unless you ask."
      footer={
        <>
          <Show when={problem()}>
            {(text) => (
              <p role="alert" class="text-center text-sm text-danger">
                {text()}
              </p>
            )}
          </Show>
          <Show
            when={!halfway()}
            fallback={
              <PillButton busy={props.busy} onClick={props.onDone}>
                Continue
              </PillButton>
            }
          >
            <Button
              variant="ghost"
              class="self-center"
              disabled={working() || props.busy}
              onClick={() => props.onDone()}
            >
              Not now
            </Button>
            <PillButton
              busy={working() || props.busy}
              disabled={!props.setup.publicKey}
              onClick={() => {
                const key = props.setup.publicKey
                if (key) void enable(key)
              }}
            >
              Turn on notifications
            </PillButton>
          </Show>
        </>
      }
    >
      <Show when={props.sample}>
        {(pick) => (
          <div class="mx-auto mt-16 flex max-w-md items-center gap-3 rounded-panel bg-surface p-4 shadow-[0_18px_40px_-24px_rgb(0_0_0/0.6)] md:mt-24">
            <Poster
              url={pick().hit.posterUrl}
              kind={pick().kind}
              radius="thumb"
              class="w-10 shrink-0"
            />
            <div class="min-w-0 flex-1">
              <div class="flex items-baseline justify-between gap-3">
                <p class="truncate font-semibold">{pick().hit.title}</p>
                <span class="shrink-0 text-xs text-muted">now</span>
              </div>
              <p class="truncate text-sm text-muted">A new episode is out.</p>
            </div>
          </div>
        )}
      </Show>
    </StepFrame>
  )
}
