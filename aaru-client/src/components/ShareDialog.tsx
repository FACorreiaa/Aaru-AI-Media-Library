import { Show, createEffect, createSignal, on } from 'solid-js'
import {
  Button,
  Dialog,
  DialogContent,
  DialogPortal,
  DialogTitle,
  TextField,
  TextFieldDescription,
  TextFieldInput,
  TextFieldLabel,
} from '~/components/ui'
import type { ShareLink, ShareTarget } from '../lib/shares/model'
import { createShare } from '../lib/shares/server'

/**
 * SHR-002: makes a share link for one title, sport event or concert. Two steps, so the share
 * sheet opens from a tap of its own (Safari drops the tap that waited on the server): an optional
 * note only friends see, then the link with Share (where the device has a share sheet) and Copy.
 * The caller keeps it mounted after the first open and passes `open`, so the exit plays (WEB-011);
 * each opening starts fresh.
 */
export function ShareDialog(props: {
  open: boolean
  target: ShareTarget
  name: string
  onClose: () => void
}) {
  const [note, setNote] = createSignal('')
  const [link, setLink] = createSignal<ShareLink | null>(null)
  const [busy, setBusy] = createSignal(false)
  const [notice, setNotice] = createSignal<string | null>(null)
  const [problem, setProblem] = createSignal<string | null>(null)

  createEffect(
    on(
      () => props.open,
      (open) => {
        if (!open) return
        setNote('')
        setLink(null)
        setNotice(null)
        setProblem(null)
      },
      { defer: true },
    ),
  )

  async function make() {
    if (busy()) return
    setBusy(true)
    setProblem(null)
    try {
      setLink(
        await createShare({
          data: { target: props.target, note: note().trim() || undefined },
        }),
      )
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'The link was not made.',
      )
    } finally {
      setBusy(false)
    }
  }

  const canShare = () =>
    typeof navigator !== 'undefined' && typeof navigator.share === 'function'

  async function share(url: string) {
    try {
      await navigator.share({ title: props.name, url })
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') return
      setProblem('The share sheet did not open. Copy the link instead.')
    }
  }

  async function copy(url: string) {
    try {
      await navigator.clipboard.writeText(url)
      setNotice('Link copied.')
    } catch {
      setProblem('The link could not be copied. Select it and copy it instead.')
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
          showCloseButton={false}
          class="block w-[min(28rem,calc(100vw-2rem))] gap-0 p-0 sm:max-w-none"
        >
          <div class="flex items-center justify-between gap-4 border-b border-line px-5 py-4">
            <DialogTitle class="min-w-0 truncate text-xl">
              Share {props.name}
            </DialogTitle>
            <Button
              variant="ghost"
              size="bare"
              class="text-sm"
              onClick={() => props.onClose()}
            >
              {link() ? 'Done' : 'Cancel'}
            </Button>
          </div>
          <div class="px-5 py-4">
            <Show
              when={link()}
              fallback={
                <>
                  <TextField class="gap-1" value={note()} onChange={setNote}>
                    <TextFieldLabel class="text-sm font-semibold">
                      Note{' '}
                      <span class="font-normal text-muted">(optional)</span>
                    </TextFieldLabel>
                    <TextFieldInput
                      maxLength={140}
                      placeholder="Why it’s worth it"
                    />
                    <TextFieldDescription class="text-xs text-muted">
                      Only your friends see this note
                    </TextFieldDescription>
                  </TextField>
                  <Button
                    class="mt-5 w-full"
                    disabled={busy()}
                    onClick={() => void make()}
                  >
                    {busy() ? 'Making the link…' : 'Create link'}
                  </Button>
                </>
              }
            >
              {(made) => (
                <>
                  <TextField value={made().url} readOnly>
                    <TextFieldLabel class="sr-only">Link</TextFieldLabel>
                    <TextFieldInput
                      readOnly
                      onFocus={(event) => event.currentTarget.select()}
                    />
                  </TextField>
                  <div class="mt-4 flex gap-2">
                    <Show when={canShare()}>
                      <Button
                        class="flex-1"
                        onClick={() => void share(made().url)}
                      >
                        Share…
                      </Button>
                    </Show>
                    <Button
                      variant="outline"
                      class="flex-1"
                      onClick={() => void copy(made().url)}
                    >
                      Copy link
                    </Button>
                  </div>
                  <p class="mt-4 text-sm leading-relaxed text-muted">
                    Anyone with the link can see {props.name}. Only your friends
                    see that you sent it.
                  </p>
                  <Show when={notice()}>
                    {(message) => (
                      <p role="status" class="mt-2 text-sm font-medium">
                        {message()}
                      </p>
                    )}
                  </Show>
                </>
              )}
            </Show>
            <Show when={problem()}>
              {(message) => (
                <p role="alert" class="mt-3 text-sm text-danger">
                  {message()}
                </p>
              )}
            </Show>
          </div>
        </DialogContent>
      </DialogPortal>
    </Dialog>
  )
}
