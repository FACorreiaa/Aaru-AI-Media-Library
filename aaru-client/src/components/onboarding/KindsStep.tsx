import { For, Show } from 'solid-js'
import { Button, ToggleButton } from '~/components/ui'
import { KIND_CARDS, MANGA_CARD } from '../../lib/landing/art'
import type { KindCard as KindArt } from '../../lib/landing/art'
import type { MediaKind } from '../../lib/library/model'
import { ONBOARDING_KINDS } from '../../lib/onboarding/model'
import { MascotMedallion } from '../Brand'
import { KindCard } from '../KindCard'
import { Owl3D } from '../Owl3D'
import { PillButton, StepFrame } from './StepFrame'
import type { Problem } from './StepFrame'

// The first screen (DESIGN.md §0a, step 1): which kinds you keep, the landing's kind cards to
// choose from. The owl sits here and nowhere else in the flow.

const LANDING_ID: Record<MediaKind, string> = {
  film: 'movies',
  show: 'shows',
  anime: 'anime',
  manga: 'manga',
  book: 'books',
  album: 'music',
}

function art(kind: MediaKind): KindArt {
  if (kind === 'manga') return MANGA_CARD
  return KIND_CARDS.find((card) => card.id === LANDING_ID[kind]) ?? MANGA_CARD
}

export function KindsStep(props: {
  kinds: MediaKind[]
  onToggle: (kind: MediaKind) => void
  onContinue: () => void
  /** "Bring your history instead": ends the flow at Import. */
  onImport: () => void
  busy: boolean
  problem: Problem | null
  /** BRD-011: where the 3D owl's model is. Null: the still on the disc. */
  owl3dModelUrl: string | null
}) {
  return (
    <StepFrame
      title="What do you keep?"
      body="Pick everything you watch, read or listen to. You can add the rest any time."
      lead={
        <Show
          when={props.owl3dModelUrl}
          fallback={
            <MascotMedallion
              idle
              decorative
              priority
              pose="curious"
              class="mb-6 w-20 md:w-24"
            />
          }
        >
          {(modelUrl) => (
            <Owl3D
              modelUrl={modelUrl()}
              state="curious"
              decorative
              class="mb-6 w-28 md:w-36"
            />
          )}
        </Show>
      }
      problem={props.problem}
      footer={
        <>
          <PillButton
            disabled={props.kinds.length === 0}
            busy={props.busy}
            onClick={props.onContinue}
          >
            {props.kinds.length === 0 ? 'Pick at least one' : 'Continue'}
          </PillButton>
          <Button
            variant="ghost"
            size="sm"
            class="self-center"
            disabled={props.busy}
            onClick={() => props.onImport()}
          >
            Bring your history instead
          </Button>
        </>
      }
    >
      <ul class="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <For each={ONBOARDING_KINDS}>
          {(kind) => {
            const card = art(kind)
            const on = () => props.kinds.includes(kind)
            return (
              <li class="relative">
                {/* The toggle over it speaks for the card. */}
                <div aria-hidden="true">
                  <KindCard kind={card} compact />
                </div>
                <ToggleButton
                  size="bare"
                  pressed={on()}
                  onChange={() => props.onToggle(kind)}
                  aria-label={card.name}
                  class="absolute inset-0 items-start justify-end rounded-[28px] bg-transparent p-4 ring-line ring-inset hover:bg-ink/5 hover:text-ink data-[pressed]:bg-transparent data-[pressed]:ring-3 data-[pressed]:ring-accent"
                >
                  <span
                    aria-hidden="true"
                    class={`grid size-7 place-items-center rounded-full border text-sm font-bold ${on() ? 'border-transparent bg-accent text-on-accent' : 'border-line-strong bg-paper'}`}
                  >
                    <Show when={on()}>✓</Show>
                  </span>
                </ToggleButton>
              </li>
            )
          }}
        </For>
      </ul>
    </StepFrame>
  )
}
