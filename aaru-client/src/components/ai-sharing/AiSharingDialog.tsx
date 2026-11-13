import { Show } from 'solid-js'
import {
  Button,
  Dialog,
  DialogContent,
  DialogHeader,
  DialogPortal,
  DialogTitle,
} from '~/components/ui'
import { AI_SHARING } from '../../lib/ai-sharing/model'
import { AiSharingDisclosure } from './AiSharingDisclosure'

/**
 * The in-place ask (PRV-002): shown where an AI surface is used without a yes (the owl's card,
 * capture, tagging @aaru), instead of an error. Allow saves the answer and lets the action go
 * on; Not now leaves everything as it was.
 */
export function AiSharingDialog(props: {
  open: boolean
  busy: boolean
  problem: string | null
  onAllow: () => void
  onNotNow: () => void
}) {
  return (
    <Dialog
      open={props.open}
      onOpenChange={(open) => {
        if (!open && !props.busy) props.onNotNow()
      }}
    >
      <DialogPortal>
        <DialogContent showCloseButton={false}>
          <DialogHeader>
            <DialogTitle class="font-display text-2xl leading-tight font-semibold text-balance">
              {AI_SHARING.title}
            </DialogTitle>
          </DialogHeader>
          <AiSharingDisclosure />
          <Show when={props.problem}>
            {(text) => (
              <p role="alert" class="text-sm text-danger">
                {text()}
              </p>
            )}
          </Show>
          <div class="grid grid-cols-2 gap-3">
            <Button
              variant="outline"
              disabled={props.busy}
              onClick={() => props.onNotNow()}
            >
              Not now
            </Button>
            <Button
              disabled={props.busy}
              aria-busy={props.busy || undefined}
              onClick={() => props.onAllow()}
            >
              Allow
            </Button>
          </div>
        </DialogContent>
      </DialogPortal>
    </Dialog>
  )
}
