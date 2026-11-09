import { For } from 'solid-js'
import { FAVORITE_LIMIT, favoriteLabel } from '../../lib/favorites/model'
import { favoriteCandidates } from '../../lib/onboarding/model'
import type { OnboardingPick } from '../../lib/onboarding/model'
import { PosterPick } from './PosterPick'
import { PillButton, StepFrame } from './StepFrame'
import type { Problem } from './StepFrame'

// Your favorites (DESIGN.md §0a, step n+1): the titles marked Watched / Read / Listened, by
// kind. A tap stars one; the order is the order of the taps, ten a kind (FAV-001).

export function FavoritesStep(props: {
  picks: OnboardingPick[]
  stars: OnboardingPick[]
  onStar: (pick: OnboardingPick) => void
  onContinue: () => void
  busy: boolean
  problem: Problem | null
}) {
  const place = (pick: OnboardingPick) => {
    const sameKind = props.stars.filter((star) => star.kind === pick.kind)
    const at = sameKind.findIndex((star) => star.key === pick.key)
    return at === -1 ? null : at + 1
  }
  return (
    <StepFrame
      title="Your favorites"
      body={`Star the ones you love most, up to ${FAVORITE_LIMIT} of each. They show on your profile in the order you tap them.`}
      problem={props.problem}
      footer={
        <PillButton busy={props.busy} onClick={props.onContinue}>
          {props.busy
            ? 'Saving…'
            : props.stars.length > 0
              ? `Continue (${props.stars.length})`
              : 'Skip favorites'}
        </PillButton>
      }
    >
      <For each={favoriteCandidates(props.picks)}>
        {(group) => (
          <section class="mt-10">
            <h2 class="font-display text-2xl font-medium tracking-tight">
              {favoriteLabel(group.kind)}
            </h2>
            <ul class="mt-4 grid grid-cols-3 gap-4 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6">
              <For each={group.picks}>
                {(pick) => (
                  <li>
                    <PosterPick
                      hit={pick.hit}
                      kind={pick.kind}
                      layout="grid"
                      selected={place(pick) !== null}
                      chip={place(pick) ? `★ ${place(pick)}` : null}
                      onTap={() => props.onStar(pick)}
                    />
                  </li>
                )}
              </For>
            </ul>
          </section>
        )}
      </For>
    </StepFrame>
  )
}
