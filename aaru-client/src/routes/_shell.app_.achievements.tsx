import { createFileRoute } from '@tanstack/solid-router'
import { For, Show, createSignal } from 'solid-js'
import { Button, cardClass } from '~/components/ui'
import { cn } from '~/lib/utils'
import { BadgeShelf } from '../components/achievements/BadgeShelf'
import { StreakBar } from '../components/achievements/StreakBar'
import { BackLink } from '../components/shell/BackLink'
import {
  earnedLine,
  levelFraction,
  nextLevelLine,
  pointsDelta,
  pointsKind,
} from '../lib/achievements/model'
import type { PointsEvent } from '../lib/achievements/model'
import { getPoints } from '../lib/achievements/server'
import { badgesQuery, progressQuery } from '../lib/queries'

// GAM-001…004 on the web (DESIGN.md §17 "Achievements"): level and points to the next one, the
// streak, then the badges by family, and "How you earned it" (the points ledger) on request.
// Not a destination: Home's strip, the "You" card on Friends and Insights open it.
export const Route = createFileRoute('/_shell/app_/achievements')({
  head: () => ({ meta: [{ title: 'Achievements · Aaru' }] }),
  loader: async ({ context: { queryClient } }) => {
    const [progress, badges] = await Promise.all([
      queryClient.query(progressQuery),
      queryClient.query(badgesQuery),
    ])
    return { progress, badges }
  },
  component: Achievements,
})

function Achievements() {
  const loaded = Route.useLoaderData()
  const progress = () => loaded().progress
  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <BackLink to="/app" label="The Field" class="-ml-1" />
        <h1 class="mt-4 font-display text-4xl font-medium tracking-tight">
          Achievements
        </h1>
        <p class="mt-1 text-muted">{earnedLine(loaded().badges)}</p>

        <div class="mt-8 grid max-w-4xl gap-4 md:grid-cols-2">
          <section
            class={cn(cardClass, 'edge-lit px-5 py-4')}
            aria-labelledby="achievements-level"
          >
            <h2 id="achievements-level" class="eyebrow">
              Level
            </h2>
            <p class="mt-2 flex items-baseline gap-3">
              <span class="font-display text-5xl leading-none font-medium tabular-nums">
                {progress().level}
              </span>
              <span class="text-sm text-muted tabular-nums">
                {progress().total.toLocaleString('en-US')} points
              </span>
            </p>
            <div
              class="mt-4 h-1.5 overflow-hidden rounded-full bg-line"
              role="progressbar"
              aria-label={nextLevelLine(progress())}
              aria-valuemin={0}
              aria-valuemax={100}
              aria-valuenow={Math.round(levelFraction(progress()) * 100)}
            >
              <div
                class="h-full rounded-full bg-accent"
                style={{ width: `${levelFraction(progress()) * 100}%` }}
              />
            </div>
            <p class="mt-2 text-xs text-muted">{nextLevelLine(progress())}</p>
          </section>
          <section
            class={cn(cardClass, 'px-5 py-4')}
            aria-labelledby="achievements-streak"
          >
            <h2 id="achievements-streak" class="eyebrow">
              Streak
            </h2>
            <div class="mt-3">
              <StreakBar streak={progress().streak} />
            </div>
          </section>
        </div>

        <div class="mt-12">
          <BadgeShelf badges={loaded().badges} />
        </div>

        <Ledger />
      </div>
    </div>
  )
}

/** "How you earned it": the points ledger, newest first, loaded when asked for. */
function Ledger() {
  const [items, setItems] = createSignal<PointsEvent[] | null>(null)
  const [next, setNext] = createSignal<string | undefined>()
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)

  async function load(before?: string) {
    setBusy(true)
    setProblem(null)
    try {
      const page = await getPoints({ data: { before } })
      setItems((current) => [...(before ? (current ?? []) : []), ...page.items])
      setNext(page.nextBefore)
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'Your points did not load.',
      )
    } finally {
      setBusy(false)
    }
  }

  return (
    <section class="mt-14 max-w-3xl" aria-labelledby="achievements-ledger">
      <h2 id="achievements-ledger" class="font-display text-xl font-medium">
        How you earned it
      </h2>
      <Show
        when={items()}
        fallback={
          <Button
            size="sm"
            variant="quiet"
            class="mt-3"
            disabled={busy()}
            onClick={() => void load()}
          >
            Show your points
          </Button>
        }
      >
        {(rows) => (
          <Show
            when={rows().length > 0}
            fallback={<p class="mt-2 text-sm text-muted">No points yet.</p>}
          >
            <ol class="mt-3 divide-y divide-line">
              <For each={rows()}>
                {(row) => (
                  <li class="flex items-baseline gap-4 py-2.5 text-sm">
                    <span class="w-24 shrink-0 text-muted tabular-nums">
                      {row.day}
                    </span>
                    <span class="min-w-0 flex-1 truncate">
                      {pointsKind(row.kind)}
                      <Show when={row.title}>
                        {(title) => (
                          <span class="text-muted"> · {title().title}</span>
                        )}
                      </Show>
                      <Show when={row.revocation}>
                        <span class="text-muted"> · taken back</span>
                      </Show>
                    </span>
                    <span
                      class="font-semibold tabular-nums"
                      classList={{ 'text-muted': row.points <= 0 }}
                    >
                      {pointsDelta(row.points)}
                    </span>
                  </li>
                )}
              </For>
            </ol>
            <Show when={next()}>
              {(before) => (
                <Button
                  size="sm"
                  variant="quiet"
                  class="mt-3"
                  disabled={busy()}
                  onClick={() => void load(before())}
                >
                  Earlier
                </Button>
              )}
            </Show>
          </Show>
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
