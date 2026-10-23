import { Link, createFileRoute, useNavigate } from '@tanstack/solid-router'
import { BackLink } from '../components/shell/BackLink'
import { For, Show, createSignal, onCleanup, onMount } from 'solid-js'
import { Button } from '~/components/ui'
import { ResolveRowDialog } from '../components/ResolveRowDialog'
import { lastShown } from '../lib/presence'
import { offerUndo } from '../components/undo-toast'
import {
  appliedMessage,
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
import type { ImportDetail, ImportRow } from '../lib/imports/server'

// APP-007 on the web: one import. A ledger of steps while it is matched (IMP-017), then the
// plan to approve. An unmatched row can be matched by hand, before or after approval (IMP-011).
export const Route = createFileRoute('/_shell/app_/imports/$id')({
  loader: ({ params }) => getImport({ data: { id: params.id } }),
  // UX-013: the tab names the import.
  head: ({ loaderData }) => ({
    meta: [
      {
        title: loaderData
          ? `${loaderData.job.filename ?? sourceLabel(loaderData.job)} · Import · Aaru`
          : 'Import · Aaru',
      },
    ],
  }),
  component: ImportPage,
})

type Outcome = ImportDetail['rows'][number]['outcome']

/** Rows drawn per section; the rest are counted (UX-078). */
const SHOWN = 200
const count = new Intl.NumberFormat('en')

function ImportPage() {
  const loaded = Route.useLoaderData()
  const navigate = useNavigate()
  const [detail, setDetail] = createSignal<ImportDetail>(loaded())
  const [applying, setApplying] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  const [finding, setFinding] = createSignal<ImportRow | null>(null)
  const shownRow = lastShown(finding)
  const job = () => detail().job
  const planned = () => job().state === 'planned'
  const resolvable = () =>
    planned() || job().state === 'partial' || job().state === 'succeeded'

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
      const applied = await applyImport({ data: { id: job().id } })
      setDetail(await getImport({ data: { id: job().id } }))
      // The whole import is one action, so the toast offers Undo.
      if (applied.actionId) {
        offerUndo(appliedMessage(applied.stats), applied.actionId, () => {
          void getImport({ data: { id: applied.id } }).then(setDetail)
        })
      }
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
      await navigate({ to: '/app/settings/import' })
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : 'The import was not discarded.',
      )
    }
  }

  function resolved(next: { job: ImportDetail['job']; row: ImportRow }) {
    if (next.job.state === 'planned') {
      // Before approval the plan is decided again as a whole: rows for the same title merge.
      void getImport({ data: { id: next.job.id } }).then(setDetail, () =>
        setDetail({ ...detail(), job: next.job }),
      )
    }
    setDetail({
      job: next.job,
      rows: detail().rows.map((r) =>
        r.index === next.row.index ? next.row : r,
      ),
    })
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
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <BackLink to="/app/settings/import" label="Import" class="-ml-1" />
        <h1 class="mt-4 font-display text-3xl font-medium tracking-tight">
          {job().filename ?? sourceLabel(job())}
        </h1>
        <p class="mt-2 text-muted" aria-live="polite">
          {sourceLabel(job())} · {stateLabel(job())}
        </p>
        <Show when={importSteps(job()).length > 0}>
          <Ledger steps={importSteps(job())} />
          <p class="mt-6 max-w-prose text-sm text-muted">
            You can leave this page: the plan waits under Settings → Import, and
            nothing reaches your library until you approve it.
          </p>
          <Show when={job().state === 'queued'}>
            <Button
              variant="ghost"
              size="bare"
              onClick={discard}
              class="mt-3 min-h-9 text-sm hover:text-danger"
            >
              Cancel this import
            </Button>
          </Show>
        </Show>
        <Show when={job().state === 'failed'}>
          <Show when={job().errorSummary}>
            <p class="mt-3 text-sm text-danger">{job().errorSummary}</p>
          </Show>
          {/* UX-078: a failed import is not kept forever. */}
          <Button variant="outline" size="sm" class="mt-4" onClick={discard}>
            Remove this import
          </Button>
        </Show>
        <Show when={problem()}>
          {(message) => (
            <p role="alert" class="mt-3 text-sm text-danger">
              {message()}
            </p>
          )}
        </Show>

        <Show when={!isWorking(job()) && job().state !== 'failed'}>
          <div class="mt-6 grid max-w-[56rem] grid-cols-[repeat(auto-fill,minmax(9rem,1fr))] gap-3">
            {stat(
              planned() ? 'New in your library' : 'Added',
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
              variant="default"
              size="lg"
              disabled={applying()}
              onClick={apply}
            >
              {applying() ? 'Importing…' : 'Approve and import'}
            </Button>
            <Button
              variant="ghost"
              size="bare"
              onClick={discard}
              class="min-h-9 text-sm hover:text-danger"
            >
              Discard
            </Button>
            <span class="text-sm text-muted">
              Lands in your history as one action you can undo.
            </span>
          </div>
        </Show>
        {/* UX-060: an applied import is one action in History, undone from there. */}
        <Show when={job().state === 'succeeded' || job().state === 'partial'}>
          <p class="mt-6 text-sm text-muted">
            This import is one action in your history.{' '}
            <Link
              to="/app/settings/data"
              hash="history"
              class="font-medium text-accent hover:underline"
            >
              Undo it from History
            </Link>
          </p>
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
                <ul class="mt-3 max-w-[56rem] divide-y divide-line">
                  <For each={rows(outcome).slice(0, SHOWN)}>
                    {(row) => (
                      <li class="flex items-start justify-between gap-4 py-2.5">
                        <div class="min-w-0">
                          <p class="font-medium">
                            {row.title}
                            {row.year ? ` (${row.year})` : ''}
                          </p>
                          <Show when={row.reason}>
                            <p class="text-sm text-muted">{row.reason}</p>
                          </Show>
                        </div>
                        <Show when={outcome === 'unmatched' && resolvable()}>
                          <Button
                            variant="quiet"
                            size="sm"
                            class="shrink-0"
                            onClick={() => setFinding(row)}
                          >
                            Find it
                          </Button>
                        </Show>
                      </li>
                    )}
                  </For>
                </ul>
                <Show when={rows(outcome).length > SHOWN}>
                  <p class="mt-3 text-sm text-muted tabular-nums">
                    Showing {count.format(SHOWN)} of{' '}
                    {count.format(rows(outcome).length)}
                  </p>
                </Show>
              </section>
            </Show>
          )}
        </For>
        <Show when={shownRow()}>
          {(row) => (
            <ResolveRowDialog
              open={finding() !== null}
              jobId={job().id}
              row={row()}
              onResolved={resolved}
              onClose={() => setFinding(null)}
            />
          )}
        </Show>
      </div>
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
