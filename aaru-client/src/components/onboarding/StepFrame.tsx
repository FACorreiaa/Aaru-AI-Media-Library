import { Show } from 'solid-js'
import type { JSX } from 'solid-js'
import { Alert, AlertDescription, Button } from '~/components/ui'

// One first-run screen (DESIGN.md §0a): a big headline, the screen's own content, and the
// pill pinned to the bottom. The top bar (Back, Skip) is the flow's.

export type Problem = { message: string; retry: () => void }

export function StepFrame(props: {
  title: string
  /** Above the headline: the owl on the first screen. */
  lead?: JSX.Element
  /** A line under the headline. */
  body?: string
  children?: JSX.Element
  /** The bottom pill and anything with it. */
  footer: JSX.Element
  problem?: Problem | null
}) {
  return (
    <section aria-labelledby="onboarding-heading" class="pb-44">
      {props.lead}
      <h1
        id="onboarding-heading"
        tabindex="-1"
        class="font-display text-4xl font-semibold tracking-tight text-balance outline-none md:text-5xl"
      >
        {props.title}
      </h1>
      <Show when={props.body}>
        {(body) => (
          <p class="mt-3 max-w-xl text-base text-balance text-muted">
            {body()}
          </p>
        )}
      </Show>
      {props.children}
      <div class="fixed inset-x-0 bottom-0 z-20 bg-linear-to-t from-paper from-60% to-transparent px-4 pt-10 pb-[max(1.25rem,env(safe-area-inset-bottom))]">
        <div class="mx-auto flex max-w-md flex-col gap-3">
          <Show when={props.problem}>
            {(problem) => (
              <Alert
                variant="destructive"
                class="flex items-center justify-between gap-3"
              >
                <AlertDescription>{problem().message}</AlertDescription>
                <Button
                  variant="quiet"
                  size="sm"
                  onClick={() => problem().retry()}
                >
                  Try again
                </Button>
              </Alert>
            )}
          </Show>
          {props.footer}
        </div>
      </div>
    </section>
  )
}

/** The pill at the bottom of a screen. */
export function PillButton(props: {
  children: JSX.Element
  onClick: () => void
  disabled?: boolean
  busy?: boolean
}) {
  return (
    <Button
      size="lg"
      class="w-full"
      disabled={props.disabled || props.busy}
      aria-busy={props.busy || undefined}
      onClick={() => props.onClick()}
    >
      {props.children}
    </Button>
  )
}
