import { Link } from '@tanstack/solid-router'
import { cardClass } from '~/components/ui'
import { cn } from '~/lib/utils'
import { dayCount, levelFraction } from '../../lib/achievements/model'
import type { Progress } from '../../lib/achievements/model'

// The "You" card at the top of Friends (DESIGN.md §17): your level, this week's points and the
// streak, the way friends see you, and the way into Achievements.
export function YouCard(props: { progress: Progress; name: string }) {
  return (
    <Link
      to="/app/achievements"
      class={cn(
        cardClass,
        'flex items-center gap-4 px-5 py-4 hover:bg-surface',
      )}
    >
      <span
        aria-hidden="true"
        class="grid size-12 shrink-0 place-items-center rounded-full bg-medallion ring-1 ring-gold font-display text-xl font-medium tabular-nums"
      >
        {props.progress.level}
      </span>
      <span class="min-w-0 flex-1">
        <span class="block truncate font-display text-lg font-medium">
          {props.name} · Level {props.progress.level}
        </span>
        <span class="mt-1 block h-1 overflow-hidden rounded-full bg-line">
          <span
            class="block h-full rounded-full bg-accent"
            style={{ width: `${levelFraction(props.progress) * 100}%` }}
          />
        </span>
        <span class="mt-1 block text-xs text-muted tabular-nums">
          {props.progress.weekPoints.toLocaleString('en-US')} points this week
          {props.progress.streak.current > 0
            ? ` · ${dayCount(props.progress.streak.current)} streak`
            : ''}
        </span>
      </span>
      <span class="shrink-0 text-sm font-semibold text-accent">Badges →</span>
    </Link>
  )
}
