import { For, Show, createSignal } from 'solid-js'
import {
  Button,
  Dialog,
  DialogContent,
  DialogDescription,
  DialogPortal,
  DialogTitle,
  RadioGroup,
  RadioGroupItem,
  RadioGroupItemInput,
  RadioGroupItemLabel,
  TextField,
  TextFieldLabel,
  TextFieldTextArea,
  toast,
} from '~/components/ui'
import type { BoardPost } from '../../lib/board/model'
import { REPORT_NOTE_LENGTH, reportPost } from '../../lib/board/server'
import { inviterName } from '../../lib/social/model'

type Reason = 'spam' | 'harassment' | 'impersonation' | 'other'

const REASONS: { value: Reason; label: string }[] = [
  { value: 'spam', label: 'Spam' },
  { value: 'harassment', label: 'Harassment' },
  { value: 'impersonation', label: 'Pretending to be someone' },
  { value: 'other', label: 'Something else' },
]

/**
 * Report a friend's post (BOARD-002): why, from four reasons, and an optional note. It goes to
 * Aaru through the user-report route with the post named; the friend is not told.
 */
export default function ReportPostDialog(props: {
  open: boolean
  post: BoardPost
  onClose: () => void
}) {
  const [reason, setReason] = createSignal<Reason | null>(null)
  const [note, setNote] = createSignal('')
  const [sending, setSending] = createSignal(false)

  function close() {
    if (sending()) return
    props.onClose()
    setReason(null)
    setNote('')
  }

  async function send() {
    const why = reason()
    if (!why || sending()) return
    setSending(true)
    try {
      await reportPost({
        data: {
          authorId: props.post.author.userId,
          postId: props.post.id,
          reason: why,
          note: note().trim() || undefined,
        },
      })
      toast('Report sent. Aaru will look at it.')
      setSending(false)
      close()
    } catch (error) {
      toast(
        error instanceof Error ? error.message : 'That report was not sent.',
      )
      setSending(false)
    }
  }

  return (
    <Dialog
      open={props.open}
      onOpenChange={(open) => {
        if (!open) close()
      }}
    >
      <DialogPortal>
        <DialogContent
          placement="sheet"
          showCloseButton={false}
          class="block w-[min(26rem,calc(100vw-2rem))] gap-0 p-0 sm:max-w-none"
        >
          <div class="flex items-center justify-between gap-4 border-b border-line px-5 py-4">
            <DialogTitle class="text-xl">Report this post</DialogTitle>
            <Button variant="ghost" size="bare" class="text-sm" onClick={close}>
              Cancel
            </Button>
          </div>
          <div class="px-5 pt-4 pb-5">
            <DialogDescription class="text-sm text-muted">
              {inviterName(props.post.author)} won’t know you reported it.
            </DialogDescription>
            <RadioGroup
              aria-label="Why"
              class="mt-4 flex flex-col gap-1"
              value={reason() ?? ''}
              onChange={(next) => setReason(next as Reason)}
            >
              <For each={REASONS}>
                {(option) => (
                  <RadioGroupItem value={option.value}>
                    <RadioGroupItemInput />
                    <RadioGroupItemLabel class="flex min-h-11 w-full cursor-pointer items-center gap-3 rounded-field px-3 text-sm font-medium peer-focus-visible/radio-group:outline-2 peer-focus-visible/radio-group:outline-accent data-[checked]:bg-surface">
                      {/* The mark: an empty ring, filled in accent once chosen. */}
                      <span
                        aria-hidden="true"
                        class={`grid size-4 shrink-0 place-items-center rounded-full border ${reason() === option.value ? 'border-accent' : 'border-ink/30'}`}
                      >
                        <Show when={reason() === option.value}>
                          <span class="size-2 rounded-full bg-accent" />
                        </Show>
                      </span>
                      {option.label}
                    </RadioGroupItemLabel>
                  </RadioGroupItem>
                )}
              </For>
            </RadioGroup>
            <TextField class="mt-4 gap-1" value={note()} onChange={setNote}>
              <TextFieldLabel class="text-sm font-semibold">
                Note <span class="font-normal text-muted">(optional)</span>
              </TextFieldLabel>
              <TextFieldTextArea
                rows={3}
                maxLength={REPORT_NOTE_LENGTH}
                placeholder="What should Aaru know?"
                class="resize-none"
              />
            </TextField>
            <Button
              variant="destructive"
              class="mt-5 w-full"
              disabled={!reason() || sending()}
              onClick={() => void send()}
            >
              {sending() ? 'Sending…' : 'Send report'}
            </Button>
          </div>
        </DialogContent>
      </DialogPortal>
    </Dialog>
  )
}
