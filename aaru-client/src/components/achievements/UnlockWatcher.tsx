import { useNavigate } from '@tanstack/solid-router'
import {
  Show,
  Suspense,
  createSignal,
  lazy,
  onCleanup,
  onMount,
} from 'solid-js'
import { toast } from '~/components/ui'
import { browserQueryClient } from '../../integrations/tanstack-query/provider'
import { PROGRESS_KEY } from '../../lib/achievements/keys'
import { revealOf, unlockSummary } from '../../lib/achievements/model'
import type { BadgeAward, Progress } from '../../lib/achievements/model'
import { getProgress, markBadgesSeen } from '../../lib/achievements/server'
import { rememberTimeZone } from '../../lib/timezone'
import { BadgeMedallion } from './BadgeMedallion'

const BadgeReveal = lazy(() => import('./BadgeReveal'))

/** After a write, wait for a burst of them to settle before asking. */
const SETTLE_MS = 1200
/** Unseen awards come five at a time; a large import drains in a few rounds. */
const MAX_ROUNDS = 40

// GAM-004 on the web (DESIGN.md §17 "The unlock"), mounted once by the shell. Every write marks
// the cache old (`start.ts`); then this asks `/v1/me/progress` for badges not yet shown. One
// quiet toast at the bottom, one summary for an import or the first run, and the full card for
// a top tier. It also keeps the zone cookie current, so the server dates the next write right.
export function UnlockWatcher() {
  const navigate = useNavigate()
  const [reveal, setReveal] = createSignal<BadgeAward | null>(null)
  const [revealOpen, setRevealOpen] = createSignal(false)
  let timer: ReturnType<typeof setTimeout> | undefined
  let checking = false
  let quietUntil = 0

  const shelf = () => void navigate({ to: '/app/achievements' })

  function schedule() {
    if (Date.now() < quietUntil) return
    clearTimeout(timer)
    timer = setTimeout(() => void check(), SETTLE_MS)
  }

  async function check() {
    if (checking) return
    checking = true
    try {
      const progress = await getProgress()
      browserQueryClient()?.setQueryData(PROGRESS_KEY, progress)
      if (progress.unseen.count === 0) return
      announce(progress.unseen)
      await drain(progress)
    } catch {
      // A nicety: the badges wait on the shelf, and the next write asks again.
    } finally {
      checking = false
      // Marking them seen is a write too; its own invalidation is not news.
      quietUntil = Date.now() + SETTLE_MS * 2
    }
  }

  function announce(unseen: Progress['unseen']) {
    const top = revealOf(unseen)
    if (top) {
      setReveal(top)
      setRevealOpen(true)
      if (unseen.count === 1) return
    }
    const line = unlockSummary(unseen)
    if (!line) return
    const first = unseen.items[0]
    toast(
      <span class="flex items-center gap-3">
        <Show when={first}>
          {(award) => (
            <BadgeMedallion
              family={award().family}
              tier={award().tier}
              size="sm"
            />
          )}
        </Show>
        <span>{line}</span>
      </span>,
      { duration: 6000, action: { label: 'See badges', onClick: shelf } },
    )
  }

  /** Marks every unseen award seen, five at a time, so none is announced twice. */
  async function drain(first: Progress) {
    let unseen = first.unseen
    for (
      let round = 0;
      round < MAX_ROUNDS && unseen.items.length > 0;
      round++
    ) {
      await markBadgesSeen({ data: { ids: unseen.items.map((a) => a.id) } })
      if (unseen.count <= unseen.items.length) return
      unseen = (await getProgress()).unseen
    }
  }

  onMount(() => {
    rememberTimeZone()
    const visible = () => {
      if (document.visibilityState !== 'visible') return
      rememberTimeZone()
      schedule()
    }
    document.addEventListener('visibilitychange', visible)
    const unsubscribe = browserQueryClient()
      ?.getQueryCache()
      .subscribe((event) => {
        if (event.type === 'updated' && event.action.type === 'invalidate')
          schedule()
      })
    // The first look waits for the page to settle: an import or the first run may be waiting.
    timer = setTimeout(() => void check(), SETTLE_MS * 2)
    onCleanup(() => {
      clearTimeout(timer)
      document.removeEventListener('visibilitychange', visible)
      unsubscribe?.()
    })
  })

  return (
    <Show when={reveal()}>
      {(award) => (
        // Its own boundary, so loading the card never suspends the page around it.
        <Suspense>
          <BadgeReveal
            award={award()}
            open={revealOpen()}
            onClose={() => setRevealOpen(false)}
            onShelf={() => {
              setRevealOpen(false)
              shelf()
            }}
          />
        </Suspense>
      )}
    </Show>
  )
}
