import { useNavigate, useRouter } from '@tanstack/solid-router'
import {
  Match,
  Show,
  Switch,
  createEffect,
  createMemo,
  createSignal,
  on,
  onMount,
} from 'solid-js'
import { Button } from '~/components/ui'
import type { components } from '../../lib/api/schema'
import { loadFavorites, saveFavorites } from '../../lib/favorites/server'
import { setAiSharing } from '../../lib/ai-sharing/server'
import { aiSharingAnswered } from '../../lib/ai-sharing/session'
import { hitKey } from '../../lib/library/model'
import type { CatalogHit, MediaKind } from '../../lib/library/model'
import { slideIn } from '../../lib/motion'
import {
  PICKS_LIMIT,
  livePicks,
  markSaved,
  mergeFavorites,
  pickItems,
  relatedTitleIds,
  sampleAlertTitle,
  setPick,
  stepAfter,
  stepBefore,
  stepKind,
  steps,
  toggleStar,
  unsent,
} from '../../lib/onboarding/model'
import type {
  OnboardingPick,
  OnboardingRelatedItem,
  Step,
} from '../../lib/onboarding/model'
import {
  addOnboardingPicks,
  finishOnboarding,
  getOnboardingRelated,
} from '../../lib/onboarding/server'
import { browserPushSupport } from '../../lib/push/enable'
import { getPushSetup } from '../../lib/push/server'
import type { PushSetup } from '../../lib/push/server'
import { onboardingFinished } from '../../lib/onboarding/session'
import { AiSharingStep } from './AiSharingStep'
import { FavoritesStep } from './FavoritesStep'
import { KindsStep } from './KindsStep'
import { NotificationsStep } from './NotificationsStep'
import { PickerStep } from './PickerStep'
import { RelatedStep } from './RelatedStep'
import type { Problem } from './StepFrame'

// ONB-001: a new account's first run (DESIGN.md §0a), full screen outside the app shell. It
// holds everything the screens share: the kinds chosen, every pick and whether the server has
// it, the stars, the related titles. Back keeps it all; Skip (every screen) ends the flow and
// keeps what was saved; nothing is sent until a screen's Continue.

type DiscoverRow = components['schemas']['DiscoverRow']

function message(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback
}

export function OnboardingFlow(props: {
  next: string
  /** BRD-011: where the 3D owl's model is. Null: the opening screen keeps the still. */
  owl3dModelUrl: string | null
}) {
  const router = useRouter()
  const navigate = useNavigate()
  const [step, setStep] = createSignal<Step>('kinds')
  const [direction, setDirection] = createSignal<1 | -1>(1)
  const [kinds, setKinds] = createSignal<MediaKind[]>([])
  const [picks, setPicks] = createSignal<OnboardingPick[]>([])
  const [stars, setStars] = createSignal<OnboardingPick[]>([])
  const [related, setRelated] = createSignal<OnboardingRelatedItem[]>([])
  const [rows, setRows] = createSignal<
    Partial<Record<MediaKind, DiscoverRow[]>>
  >({})
  const [push, setPush] = createSignal<PushSetup | null>(null)
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<Problem | null>(null)
  let screen: HTMLDivElement | undefined

  // Alerts are asked about only where this browser can take them and the server sends them.
  onMount(() => {
    if (browserPushSupport() !== 'supported') return
    getPushSetup()
      .then(setPush)
      .catch(() => setPush(null))
  })

  const list = createMemo(() =>
    steps({
      kinds: kinds(),
      picks: livePicks(picks(), kinds()),
      hasRelated: related().length > 0,
      pushSupported: !!push()?.publicKey,
    }),
  )

  // Related titles are looked up after each screen saves, so they are ready by the time the
  // flow gets there; the last lookup wins.
  let relatedTicket = 0
  let relatedLoad: Promise<void> | null = null
  function lookUpRelated() {
    const titleIds = relatedTitleIds(picks())
    if (titleIds.length === 0) return
    const ticket = ++relatedTicket
    const load = getOnboardingRelated({ data: { titleIds } })
      .then((answer) => {
        if (ticket === relatedTicket) setRelated(answer.items)
      })
      // Nothing related, as far as the flow knows: the screen is left out.
      .catch(() => undefined)
      .finally(() => {
        if (relatedLoad === load) relatedLoad = null
      })
    relatedLoad = load
  }

  createEffect(
    on(
      step,
      () => {
        if (!screen) return
        window.scrollTo({ top: 0 })
        screen.querySelector<HTMLElement>('#onboarding-heading')?.focus()
        void slideIn(screen, direction())
      },
      { defer: true },
    ),
  )

  function go(to: Step, way: 1 | -1) {
    setProblem(null)
    setDirection(way)
    setStep(to)
  }

  async function forward() {
    // The related screen depends on the lookup: past the pickers, wait for it.
    const after = stepAfter(list(), step())
    if (relatedLoad && (!after || !stepKind(after))) {
      setBusy(true)
      await relatedLoad
      setBusy(false)
    }
    const next = stepAfter(list(), step())
    if (next) go(next, 1)
    else await end(false)
  }

  function back() {
    const before = stepBefore(list(), step())
    if (before) go(before, -1)
  }

  /** Ends the flow (finished or skipped) and goes where the visit was headed. */
  async function end(skipped: boolean, to = props.next) {
    setBusy(true)
    setProblem(null)
    try {
      await finishOnboarding({ data: { skipped } })
      onboardingFinished(router.options.context.queryClient)
      await navigate({ href: to, replace: true })
    } catch (error) {
      setProblem({
        message: message(error, 'That did not go through.'),
        retry: () => void end(skipped, to),
      })
    } finally {
      setBusy(false)
    }
  }

  /** PRV-002: stores the answer to AI sharing, then goes on. Skip never comes here. */
  async function answerAiSharing(allowed: boolean) {
    setBusy(true)
    setProblem(null)
    try {
      const state = await setAiSharing({ data: { allowed } })
      aiSharingAnswered(router.options.context.queryClient, state)
    } catch (error) {
      setProblem({
        message: message(error, 'Your answer was not saved.'),
        retry: () => void answerAiSharing(allowed),
      })
      return
    } finally {
      setBusy(false)
    }
    await forward()
  }

  /** Sends picks in batches of 60 (one action each); any that failed stay picked to retry.
   * A picker's save looks up related titles again; the related screen's own save does not, or
   * the screen would lose the titles it just added and leave the step list under the user. */
  async function save(
    batch: OnboardingPick[],
    retry: () => void,
    lookUp = true,
  ) {
    setBusy(true)
    setProblem(null)
    try {
      for (let at = 0; at < batch.length; at += PICKS_LIMIT) {
        const chunk = batch.slice(at, at + PICKS_LIMIT)
        const answer = await addOnboardingPicks({
          data: { items: pickItems(chunk) },
        })
        setPicks((current) => markSaved(current, chunk, answer))
      }
      if (lookUp) lookUpRelated()
      return true
    } catch (error) {
      setProblem({
        message: message(error, 'Your picks were not saved.'),
        retry,
      })
      return false
    } finally {
      setBusy(false)
    }
  }

  async function continuePicker(kind: MediaKind) {
    if (busy()) return
    const batch = unsent(picks(), kind)
    if (
      batch.length > 0 &&
      !(await save(batch, () => void continuePicker(kind)))
    )
      return
    await forward()
  }

  async function continueFavorites() {
    if (busy()) return
    const starred = stars().filter((star) => star.saved)
    if (starred.length > 0) {
      setBusy(true)
      setProblem(null)
      try {
        // Merged with what is there already, so the first run never empties a kind.
        const existing = await loadFavorites()
        const touched = [...new Set(starred.map((star) => star.kind))]
        for (const kind of touched) {
          await saveFavorites({
            data: {
              kind,
              items: mergeFavorites(
                existing[kind],
                starred.filter((star) => star.kind === kind),
              ),
            },
          })
        }
      } catch (error) {
        setProblem({
          message: message(error, 'Your favorites were not saved.'),
          retry: () => void continueFavorites(),
        })
        return
      } finally {
        setBusy(false)
      }
    }
    await forward()
  }

  async function continueRelated() {
    if (busy()) return
    const keys = new Set(related().map((item) => hitKey(item.hit)))
    const batch = picks().filter((pick) => keys.has(pick.key) && !pick.saved)
    if (
      batch.length > 0 &&
      !(await save(batch, () => void continueRelated(), false))
    )
      return
    await forward()
  }

  function toggleRelated(hit: CatalogHit) {
    setPicks((current) => {
      const pick = current.find((p) => p.key === hitKey(hit))
      return setPick(current, hit, pick ? null : 'wishlist')
    })
  }

  const toggleKind = (kind: MediaKind) =>
    setKinds((current) =>
      current.includes(kind)
        ? current.filter((k) => k !== kind)
        : [...current, kind],
    )

  return (
    <div class="mx-auto w-full max-w-6xl px-4 md:px-8">
      <div class="flex h-16 items-center justify-between">
        <Show when={stepBefore(list(), step())} fallback={<span />}>
          <Button variant="ghost" size="sm" class="-ml-2" onClick={back}>
            ‹ Back
          </Button>
        </Show>
        <Button
          variant="ghost"
          size="sm"
          class="-mr-2"
          disabled={busy()}
          onClick={() => void end(true)}
        >
          Skip
        </Button>
      </div>
      <div ref={screen}>
        <Switch>
          <Match when={step() === 'kinds'}>
            <KindsStep
              kinds={kinds()}
              onToggle={toggleKind}
              onContinue={() => void forward()}
              onImport={() => void end(false, '/app/settings/import')}
              busy={busy()}
              problem={problem()}
              owl3dModelUrl={props.owl3dModelUrl}
            />
          </Match>
          <Match when={stepKind(step())} keyed>
            {(kind) => (
              <PickerStep
                kind={kind}
                picks={picks()}
                onPicks={setPicks}
                rows={rows()[kind]}
                onRows={(loaded) =>
                  setRows((current) => ({ ...current, [kind]: loaded }))
                }
                onContinue={() => void continuePicker(kind)}
                busy={busy()}
                problem={problem()}
              />
            )}
          </Match>
          <Match when={step() === 'favorites'}>
            <FavoritesStep
              picks={picks()}
              stars={stars()}
              onStar={(pick) =>
                setStars((current) => toggleStar(current, pick))
              }
              onContinue={() => void continueFavorites()}
              busy={busy()}
              problem={problem()}
            />
          </Match>
          <Match when={step() === 'related'}>
            <RelatedStep
              items={related()}
              picks={picks()}
              onToggle={toggleRelated}
              onContinue={() => void continueRelated()}
              busy={busy()}
              problem={problem()}
            />
          </Match>
          <Match when={step() === 'ai'}>
            <AiSharingStep
              onAnswer={(allowed) => void answerAiSharing(allowed)}
              busy={busy()}
              problem={problem()}
            />
          </Match>
          <Match when={step() === 'notifications' && push()}>
            {(setup) => (
              <NotificationsStep
                sample={sampleAlertTitle(picks())}
                setup={setup()}
                onDone={() => void forward()}
                busy={busy()}
              />
            )}
          </Match>
        </Switch>
      </div>
    </div>
  )
}
