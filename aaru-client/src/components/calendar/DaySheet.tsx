import { For } from 'solid-js'
import { agendaDayLabel } from '../../lib/calendar/model'
import type { CalendarEntry } from '../../lib/calendar/model'
import { Button, Dialog, DialogContent, DialogPortal } from '~/components/ui'
import { EpisodeRow } from './EpisodeRow'

/** A phone's month day, tapped: what airs that day, one row each (CAL-002). */
export default function DaySheet(props: {
  day: string
  entries: CalendarEntry[]
  pending: Set<string>
  keyOf: (entry: CalendarEntry) => string
  onOpen: (entry: CalendarEntry) => void
  onToggle: (entry: CalendarEntry) => void
  /** Defaults to true; the parent keeps it mounted with false so its exit plays (WEB-011). */
  open?: boolean
  onClose: () => void
}) {
  return (
    <Dialog
      open={props.open ?? true}
      onOpenChange={(open) => {
        if (!open) props.onClose()
      }}
    >
      <DialogPortal>
        <DialogContent
          placement="sheet"
          showCloseButton={false}
          aria-label={agendaDayLabel(props.day)}
          class="block gap-0 p-0 max-w-[34rem] sm:max-w-[34rem]"
        >
          <div class="px-5 pt-4 pb-5">
            <div class="flex items-center justify-between gap-4">
              <h2 class="font-display text-2xl font-medium">
                {agendaDayLabel(props.day)}
              </h2>
              <Button
                variant="ghost"
                size="bare"
                class="text-sm"
                onClick={() => props.onClose()}
              >
                Close
              </Button>
            </div>
            <ul class="mt-2 divide-y divide-line">
              <For
                each={props.entries}
                fallback={
                  <li class="py-6 text-center text-sm text-muted">
                    Nothing from your shows airs this day.
                  </li>
                }
              >
                {(entry) => (
                  <EpisodeRow
                    entry={entry}
                    pending={props.pending.has(props.keyOf(entry))}
                    onOpen={props.onOpen}
                    onToggle={props.onToggle}
                  />
                )}
              </For>
            </ul>
          </div>
        </DialogContent>
      </DialogPortal>
    </Dialog>
  )
}
