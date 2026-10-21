import {
  Link,
  createFileRoute,
  redirect,
  useNavigate,
} from '@tanstack/solid-router'
import { For, Show, createSignal, onCleanup, onMount } from 'solid-js'
import { Wordmark } from '../components/Brand'
import { Button } from '../components/ui/button'
import {
  importSteps,
  isWorking,
  sourceLabel,
  stateLabel,
} from '../lib/imports/model'
import type { ImportStep } from '../lib/imports/model'
import {
  applyImport,
  discardImport,
  getImport,
  listImports,
} from '../lib/imports/server'
import type { ImportDetail } from '../lib/imports/server'
import { getSession } from '../lib/session/session'

// APP-007 on the web: one import. A ledger of steps while it is matched (IMP-017), then the
// plan to approve.
export const Route = createFileRoute('/app_/imports/$id')({
  head: () => ({ meta: [{ title: 'Import · Aaru' }] }),
  beforeLoad: async () => {
    const session = await getSession()
    if (!session.signedIn) throw redirect({ to: '/sign-in' })
  },
  loader: ({ params }) => getImport({ data: { id: params.id } }),
  component: ImportPage,
})

type Outcome = ImportDetail['rows'][number]['outcome']

function ImportPage() {
  const loaded = Route.useLoaderData()
  const navigate = useNavigate()
  const [detail, setDetail] = createSignal<ImportDetail>(loaded())
  const [applying, setApplying] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  const job = () => detail().job
  const planned = () => job().state === 'planned'

  // Polls every two seconds while the server is still matching. The job list carries the
  // progress without the rows (a 2,000-entry export is a big payload); the rows are read once,
  // when the plan is ready.
  onMount(() => {
    const timer = setInterval(async () => {
      if (!isWorking(job())) return clearInterval(timer)
      try {
        const fresh = (await listImports()).find((j) => j.id === job().id)
        if (!fresh) return
        if (isWorking(fresh)) setDetail({ ...detail(), job: fresh })
        else setDetail(await getImport({ data: { id: fresh.id } }))
      } catch {
        // A missed poll is retried on the next tick.
      }
    }, 2000)
    onCleanup(() => clearInterval(timer))
  })

  async function apply() {
    setApplying(true)
    setProblem(null)
    try {
      await applyImport({ data: { id: job().id } })
      setDetail(await getImport({ data: { id: job().id } }))
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'The import was not applied.',
      )
    } finally {
      setApplying(false)
    }
  }

  async function discard() {
    setProblem(null)
    try {
      await discardImport({ data: { id: job().id } })
      await navigate({ to: '/app/settings/imports' })
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : 'The import was not discarded.',
      )
    }
  }

  const rows = (outcome: Outcome) =>
    detail().rows.filter((r) => r.outcome === outcome)
  const stat = (label: string, value: number) => (
    <div class="rounded-[16px] bg-surface px-4 py-3">
      <div class="text-2xl font-medium tabular-nums">{value}</div>
      <div class="text-sm text-muted">{label}</div>
    </div>
  )

  return (
    <div class="min-h-[100dvh]">
      <header class="mx-auto flex h-18 max-w-3xl items-center justify-between px-5 md:px-8">
        <Wordmark to="/app" />
        <Link
          to="/app/settings/imports"
          hash="imports"
          class="text-sm font-medium text-muted hover:text-ink"
        >
          All imports
        </Link>
      </header>
      <main class="mx-auto max-w-3xl px-5 pb-20 md:px-8">
        <h1 class="mt-4 font-display text-3xl font-medium tracking-tight">
          {job().filename ?? sourceLabel(job())}
        </h1>
        <p class="mt-2 text-muted" aria-live="polite">
          {sourceLabel(job())} · {stateLabel(job())}
        </p>
        <Show when={importSteps(job()).length > 0}>
          <Ledger steps={importSteps(job())} />
          <p class="mt-6 text-sm text-muted">
            You can leave this page: the plan waits under Settings → Imports,
            and nothing reaches your shelf until you approve it.
          </p>
          <Show when={job().state === 'queued'}>
            <button
              type="button"
              onClick={discard}
              class="mt-3 text-sm text-muted hover:text-danger"
            >
              Cancel this import
            </button>
          </Show>
        </Show>
        <Show when={job().state === 'failed' && job().errorSummary}>
          <p class="mt-3 text-sm text-danger">{job().errorSummary}</p>
        </Show>
        <Show when={problem()}>
          {(message) => (
            <p role="alert" class="mt-3 text-sm text-danger">
              {message()}
            </p>
          )}
        </Show>

        <Show when={!isWorking(job()) && job().state !== 'failed'}>
          <div class="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
            {stat(
              planned() ? 'New on your shelf' : 'Added',
              job().stats.created,
            )}
            {stat(planned() ? 'Filled in' : 'Updated', job().stats.updated)}
            {stat('Already there', job().stats.skipped)}
            {stat('Not matched', job().stats.unmatched)}
          </div>
        </Show>

        <Show when={planned()}>
          <div class="mt-6 flex flex-wrap items-center gap-3">
            <Button
              variant="primary"
              size="lg"
              disabled={applying()}
              onClick={apply}
            >
              {applying() ? 'Importing…' : 'Approve and import'}
            </Button>
            <button
              type="button"
              onClick={discard}
              class="text-sm text-muted hover:text-danger"
            >
              Discard
            </button>
            <span class="text-sm text-muted">
              Lands in your history as one action you can undo.
            </span>
          </div>
        </Show>

        <For
          each={
            [
              ['unmatched', 'Not matched'],
              ['create', planned() ? 'Will be added' : 'Added'],
              ['update', planned() ? 'Will be filled in' : 'Filled in'],
            ] as Array<[Outcome, string]>
          }
        >
          {([outcome, title]) => (
            <Show when={!isWorking(job()) && rows(outcome).length > 0}>
              <section class="mt-10">
                <h2 class="font-display text-xl font-medium">
                  {title} ({rows(outcome).length})
                </h2>
                <ul class="mt-3 divide-y divide-line">
                  <For each={rows(outcome).slice(0, 200)}>
                    {(row) => (
                      <li class="py-2.5">
                        <p class="font-medium">
                          {row.title}
                          {row.year ? ` (${row.year})` : ''}
                        </p>
                        <Show when={row.reason}>
                          <p class="text-sm text-muted">{row.reason}</p>
                        </Show>
                      </li>
                    )}
                  </For>
                </ul>
              </section>
            </Show>
          )}
        </For>
      </main>
    </div>
  )
}

/** DESIGN §3: a working import is a timeline of steps, not a spinner. Nothing loops; the bar
 *  only moves when the count does. */
function Ledger(props: { steps: ImportStep[] }) {
  return (
    <ol class="mt-8" aria-label="Import progress">
      <For each={props.steps}>
        {(step, index) => (
          <li
            class="relative flex gap-4 pb-6 last:pb-0"
            aria-current={step.state === 'current' ? 'step' : undefined}
          >
            <Show when={index() < props.steps.length - 1}>
              <span
                aria-hidden="true"
                class={`absolute top-6 bottom-0 left-[11px] w-px ${
                  step.state === 'done' ? 'bg-accent' : 'bg-line'
                }`}
              />
            </Show>
            <span
              aria-hidden="true"
              class={`relative mt-0.5 grid h-6 w-6 shrink-0 place-items-center rounded-full text-xs ${
                step.state === 'done'
                  ? 'bg-accent text-on-accent'
                  : step.state === 'current'
                    ? 'border-2 border-accent bg-paper'
                    : 'border border-line bg-paper'
              }`}
            >
              {step.state === 'done' ? '✓' : ''}
            </span>
            <div class="min-w-0 flex-1">
              <p
                class={
                  step.state === 'todo' ? 'text-muted' : 'font-medium text-ink'
                }
              >
                {step.label}
                <span class="sr-only">
                  {step.state === 'done'
                    ? ' (done)'
                    : step.state === 'current'
                      ? ' (in progress)'
                      : ''}
                </span>
              </p>
              <Show when={step.detail}>
                <p class="mt-0.5 text-sm text-muted tabular-nums">
                  {step.detail}
                </p>
              </Show>
              <Show when={step.progress !== undefined}>
                <div
                  role="progressbar"
                  aria-label={step.label}
                  aria-valuemin={0}
                  aria-valuemax={100}
                  aria-valuenow={Math.round((step.progress ?? 0) * 100)}
                  class="mt-2 h-1.5 max-w-sm overflow-hidden rounded-full bg-line"
                >
                  <div
                    class="h-full rounded-full bg-accent transition-[width] duration-500 motion-reduce:transition-none"
                    style={{ width: `${(step.progress ?? 0) * 100}%` }}
                  />
                </div>
              </Show>
            </div>
          </li>
        )}
      </For>
    </ol>
  )
}
