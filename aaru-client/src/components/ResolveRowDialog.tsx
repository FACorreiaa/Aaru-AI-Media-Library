import { Show, createSignal } from 'solid-js'
import { kindOf } from '../lib/library/model'
import type { CatalogHit } from '../lib/library/model'
import { resolveImportRow } from '../lib/imports/server'
import type { ImportJob, ImportRow } from '../lib/imports/server'
import { TitlePicker } from './groups/TitlePicker'
import { Button } from './ui/button'
import { Dialog } from './ui/dialog'

/** IMP-011: search for the title an unmatched import row meant, and pick it. The row's status,
 *  rating and ticks come with it; before approval it joins the plan. */
export function ResolveRowDialog(props: {
  jobId: string
  row: ImportRow
  onResolved: (resolved: { job: ImportJob; row: ImportRow }) => void
  onClose: () => void
}) {
  let dialog: HTMLDialogElement | undefined
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  const anime = () => Boolean(props.row.ids?.anilist ?? props.row.ids?.mal)

  async function pick(hit: CatalogHit) {
    setBusy(true)
    setProblem(null)
    try {
      const resolved = await resolveImportRow({
        data: {
          id: props.jobId,
          index: props.row.index,
          type: hit.type,
          ids: hit.ids,
          title: hit.title,
          year: hit.year ?? undefined,
        },
      })
      props.onResolved(resolved)
      dialog?.close()
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'That row was not matched.',
      )
    } finally {
      setBusy(false)
    }
  }

  return (
    <Dialog
      ref={dialog}
      openOnMount
      aria-label={`Find “${props.row.title}”`}
      class="w-[min(30rem,calc(100vw-2rem))]"
      onClose={() => props.onClose()}
    >
      <div class="flex items-center justify-between gap-4 border-b border-line px-5 py-4">
        <h2 class="line-clamp-1 font-display text-xl font-medium">
          Find “{props.row.title}”
        </h2>
        <Button
          variant="ghost"
          size="bare"
          class="text-sm"
          onClick={() => dialog?.close()}
        >
          Cancel
        </Button>
      </div>
      <div class="px-5 py-4">
        <p class="mb-3 text-sm text-muted">
          Pick the title this row meant. What the file said about it (status,
          rating, episodes) comes with it.
        </p>
        <TitlePicker
          initialQuery={props.row.title}
          initialKind={kindOf(props.row.type, anime())}
          busy={busy()}
          onPick={(hit) => void pick(hit)}
        />
        <Show when={problem()}>
          {(message) => (
            <p role="alert" class="mt-3 text-sm text-danger">
              {message()}
            </p>
          )}
        </Show>
      </div>
    </Dialog>
  )
}
