import { Link } from '@tanstack/solid-router'
import { cardClass } from '~/components/ui'
import { cn } from '~/lib/utils'
import { levelFraction, nextLevelLine } from '../../lib/achievements/model'
import type { Progress } from '../../lib/achievements/model'
import { StreakBar } from './StreakBar'

// The Home strip (DESIGN.md §17 "Where it lives"): `StreakBar` with the level beside it, and
// the way into Achievements. The whole card is the link.
export function ProgressStrip(props: { progress: Progress }) {
  return (
    <section aria-labelledby="home-progress">
      <h2 id="home-progress" class="eyebrow">
        Achievements
      </h2>
      <Link
        to="/app/achievements"
        aria-label={`Level ${props.progress.level}, ${nextLevelLine(props.progress)}. Open Achievements.`}
        class={cn(cardClass, 'mt-3 block px-5 py-4 hover:bg-surface')}
      >
        <StreakBar streak={props.progress.streak} compact />
        <div class="mt-4 flex items-center gap-3">
          <span class="text-sm font-semibold tabular-nums">
            Level {props.progress.level}
          </span>
          <span class="h-1 flex-1 overflow-hidden rounded-full bg-line">
            <span
              class="block h-full rounded-full bg-accent"
              style={{ width: `${levelFraction(props.progress) * 100}%` }}
            />
          </span>
        </div>
        <p class="mt-1 text-xs text-muted">{nextLevelLine(props.progress)}</p>
      </Link>
    </section>
  )
}
