import { Show, createSignal } from 'solid-js'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogPortal,
  DialogTitle,
} from '~/components/ui'
import { kindOf } from '../lib/library/model'
import type { CatalogHit } from '../lib/library/model'
import { resolveImportRow } from '../lib/imports/server'
import type { ImportJob, ImportRow } from '../lib/imports/server'
import { TitlePicker } from './groups/TitlePicker'

/** IMP-011: search for the title an unmatched import row meant, and pick it. The row's status,
 *  rating and ticks come with it; before approval it joins the plan. The page keeps it mounted
 *  on its last row (`lastShown`) so the exit plays (WEB-011). */
export function ResolveRowDialog(props: {
  open: boolean
  jobId: string
  row: ImportRow
  onResolved: (resolved: { job: ImportJob; row: ImportRow }) => void
  onClose: () => void
}) {
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
      props.onClose()
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
      open={props.open}
      onOpenChange={(open) => {
        if (!open) props.onClose()
      }}
    >
      <DialogPortal>
        <DialogContent
          placement="sheet"
          class="block w-[min(30rem,calc(100vw-2rem))] gap-0 p-5 sm:max-w-none"
        >
          <DialogTitle class="line-clamp-1 pr-8 text-xl">
            Find “{props.row.title}”
          </DialogTitle>
          <DialogDescription class="mt-2 mb-4">
            Pick the title this row meant. What the file said about it (status,
            rating, episodes) comes with it.
          </DialogDescription>
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
        </DialogContent>
      </DialogPortal>
    </Dialog>
  )
}
