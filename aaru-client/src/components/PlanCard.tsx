import { Link } from '@tanstack/solid-router'
import { For, Show, createSignal } from 'solid-js'
import { Button } from '~/components/ui'
import { countsLine, decidedLabel, expiresLabel } from '../lib/plans/model'
import { approvePlan, denyPlan } from '../lib/plans/server'
import { offerUndo } from './undo-toast'
import type { AgentPlan } from '../lib/plans/server'

// DESIGN §12: an agent's request leads with who asked, then what changes, then the two
// answers. Nothing is written until the user approves; approval is one undoable action.
export function PlanCard(props: {
  plan: AgentPlan
  onDecided?: (plan: AgentPlan) => void
}) {
  const [plan, setPlan] = createSignal(props.plan)
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)

  async function decide(approve: boolean) {
    setBusy(true)
    setProblem(null)
    try {
      const decided = approve
        ? await approvePlan({ data: { id: plan().id } })
        : await denyPlan({ data: { id: plan().id } })
      setPlan(decided)
      props.onDecided?.(decided)
      // Approval is one action, so the toast offers Undo; Home loads again after it.
      if (decided.status === 'applied' && decided.actionId) {
        offerUndo(`Applied: ${decided.summary}`, decided.actionId, () =>
          props.onDecided?.(decided),
        )
      }
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'Nothing was changed.',
      )
    } finally {
      setBusy(false)
    }
  }

  return (
    <article class="edge-lit rounded-card bg-surface p-5">
      <p class="flex items-center gap-2 text-xs font-semibold tracking-wide text-muted uppercase">
        <span class="size-1.5 rounded-full bg-gold" aria-hidden="true" />
        {plan().agentName} asks
      </p>
      <h3 class="mt-1 font-display text-xl font-medium">{plan().summary}</h3>
      <p class="mt-1 text-sm text-muted">
        {countsLine(plan())} · nothing changes until you approve ·{' '}
        {expiresLabel(plan())}
      </p>
      <Show when={plan().changes.length > 1}>
        <ul class="mt-3 flex flex-col gap-1 text-sm">
          <For each={plan().changes}>
            {(change) => <li class="truncate">{change.text}</li>}
          </For>
        </ul>
      </Show>
      <Show
        when={decidedLabel(plan())}
        fallback={
          <div class="mt-4 flex flex-wrap gap-2">
            <Button
              variant="default"
              disabled={busy()}
              onClick={() => void decide(true)}
            >
              Approve
            </Button>
            <Button
              variant="outline"
              disabled={busy()}
              onClick={() => void decide(false)}
            >
              Not this
            </Button>
          </div>
        }
      >
        {(label) => (
          <p class="mt-4 text-sm font-medium">
            {label()}
            {/* UX-060: the history it promises is one click away. */}
            <Show when={plan().status === 'applied'}>
              {' '}
              <Link
                to="/app/settings/data"
                hash="history"
                class="text-accent hover:underline"
              >
                Open History
              </Link>
            </Show>
          </p>
        )}
      </Show>
      <Show when={problem()}>
        {(message) => (
          <p role="alert" class="mt-3 text-sm text-danger">
            {message()}
          </p>
        )}
      </Show>
    </article>
  )
}
