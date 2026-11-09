import { For } from 'solid-js'
import { hitKey, statusLabel } from '../../lib/library/model'
import type { CatalogHit } from '../../lib/library/model'
import {
  hitKind,
  relatedGroups,
  relatedHeading,
} from '../../lib/onboarding/model'
import type {
  OnboardingPick,
  OnboardingRelatedItem,
} from '../../lib/onboarding/model'
import { PosterPick } from './PosterPick'
import { PillButton, StepFrame } from './StepFrame'
import type { Problem } from './StepFrame'

// More from what you picked (DESIGN.md §0a, step n+2): sequels, prequels, spin-offs and
// adaptations of the picks, from the relation graph (GRAPH-001). Catalog data, never a
// recommendation: no "for you", no "because you watched". A tap plans one.

export function RelatedStep(props: {
  items: OnboardingRelatedItem[]
  picks: OnboardingPick[]
  onToggle: (hit: CatalogHit) => void
  onContinue: () => void
  busy: boolean
  problem: Problem | null
}) {
  const byKey = () => new Map(props.picks.map((pick) => [pick.key, pick]))
  const count = () =>
    props.items.filter((item) => {
      const pick = byKey().get(hitKey(item.hit))
      return pick && !pick.saved
    }).length
  return (
    <StepFrame
      title="More from what you picked"
      body="Sequels, prequels, spin-offs and adaptations of your titles. Tap one to plan it."
      problem={props.problem}
      footer={
        <PillButton busy={props.busy} onClick={props.onContinue}>
          {props.busy
            ? 'Saving…'
            : count() > 0
              ? `Continue (${count()})`
              : 'Skip these'}
        </PillButton>
      }
    >
      <For each={relatedGroups(props.items)}>
        {(group) => (
          <section class="mt-10">
            <h2 class="font-display text-2xl font-medium tracking-tight">
              {relatedHeading(group.fromTitle)}
            </h2>
            <ul class="mt-4 grid grid-cols-3 gap-4 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6">
              <For each={group.items}>
                {(hit) => {
                  const kind = hitKind(hit)
                  const pick = () => byKey().get(hitKey(hit))
                  return (
                    <li>
                      <PosterPick
                        hit={hit}
                        kind={kind}
                        layout="grid"
                        selected={!!pick()}
                        locked={!!pick()?.saved}
                        chip={
                          pick()
                            ? statusLabel(pick()?.status ?? 'wishlist', kind)
                            : null
                        }
                        note={pick()?.saved ? 'Added' : undefined}
                        onTap={() => props.onToggle(hit)}
                      />
                    </li>
                  )
                }}
              </For>
            </ul>
          </section>
        )}
      </For>
    </StepFrame>
  )
}
