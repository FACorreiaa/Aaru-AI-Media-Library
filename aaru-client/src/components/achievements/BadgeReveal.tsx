import { MascotMedallion } from '../Brand'
import { Show } from 'solid-js'
import {
  Button,
  Dialog,
  DialogContent,
  DialogDescription,
  DialogPortal,
  DialogTitle,
} from '~/components/ui'
import { play } from '../../lib/motion'
import { tierName } from '../../lib/achievements/model'
import type { BadgeAward } from '../../lib/achievements/model'
import { BadgeMedallion } from './BadgeMedallion'

// The one full card a badge's top tier gets, once (DESIGN.md §17 "The unlock"). The medallion
// settles into place through `motion/mini`; with reduced motion the dialog's own cross-fade is
// all that moves. Loaded only when there is one to show.
export default function BadgeReveal(props: {
  award: BadgeAward
  open: boolean
  onClose: () => void
  onShelf: () => void
}) {
  const settle = (el: HTMLElement) =>
    void play(
      el,
      {
        opacity: [0, 1],
        transform: ['scale(0.72) rotate(-14deg)', 'scale(1) rotate(0deg)'],
      },
      0.6,
    )
  return (
    <Dialog open={props.open} onOpenChange={(open) => !open && props.onClose()}>
      <DialogPortal>
        <DialogContent class="atmos max-w-sm justify-items-center px-8 py-10 text-center">
          <div ref={settle} class="relative">
            <BadgeMedallion
              family={props.award.family}
              tier={props.award.tier}
              size="lg"
            />
            {/* Aaru celebrates it with you (owner, 2026-10-23). */}
            <MascotMedallion
              decorative
              pose="celebrating"
              class="absolute -right-4 -bottom-2 w-14 ring-4 ring-paper"
            />
          </div>
          <div>
            <Show when={tierName(props.award.tier, props.award.maxTier)}>
              {(name) => <p class="eyebrow">{name()}</p>}
            </Show>
            <DialogTitle class="mt-1 font-display text-3xl font-medium tracking-tight">
              {props.award.name}
            </DialogTitle>
            <DialogDescription class="mt-2 text-muted">
              {props.award.maxTier > 1
                ? 'Every tier, earned.'
                : 'A hidden one, found.'}
            </DialogDescription>
          </div>
          <div class="flex flex-wrap justify-center gap-2">
            <Button onClick={() => props.onShelf()}>See your badges</Button>
            <Button variant="quiet" onClick={() => props.onClose()}>
              Close
            </Button>
          </div>
        </DialogContent>
      </DialogPortal>
    </Dialog>
  )
}
