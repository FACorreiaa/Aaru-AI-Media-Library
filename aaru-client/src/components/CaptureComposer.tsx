import { useNavigate } from '@tanstack/solid-router'
import { Show, createSignal, onCleanup } from 'solid-js'
import {
  Button,
  TextField,
  TextFieldLabel,
  TextFieldTextArea,
} from '~/components/ui'
import { captureSend } from '../lib/capture/model'
import { startCapture } from '../lib/capture/server'
import type { CaptureResult } from '../lib/capture/server'

// DESIGN §1 and §11: the Field's one composer. Paste a list, a link or a screenshot (or drop
// one on it); Aaru reads it into an import the user reviews before anything is added. Plus is
// bought in the Apple apps, so past the free captures the web only says so.
export function CaptureComposer() {
  const navigate = useNavigate()
  const [text, setText] = createSignal('')
  const [picture, setPicture] = createSignal<File | null>(null)
  const [preview, setPreview] = createSignal<string | null>(null)
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  const [quota, setQuota] = createSignal<string | null>(null)
  const [over, setOver] = createSignal(false)

  function choose(file: File | null | undefined) {
    if (!file?.type.startsWith('image/')) return
    const old = preview()
    if (old) URL.revokeObjectURL(old)
    setPicture(file)
    setPreview(URL.createObjectURL(file))
    setProblem(null)
  }

  function clearPicture() {
    const old = preview()
    if (old) URL.revokeObjectURL(old)
    setPicture(null)
    setPreview(null)
  }

  /** The system's picker, opened from the picture button; nothing lives in the page. */
  function pick() {
    const input = document.createElement('input')
    input.type = 'file'
    input.accept = 'image/jpeg,image/png,image/gif,image/webp,image/heic'
    input.onchange = () => choose(input.files?.[0])
    input.click()
  }
  onCleanup(clearPicture)

  const ready = () =>
    !busy() && (picture() !== null || captureSend(text()) !== null)

  async function send(event: SubmitEvent) {
    event.preventDefault()
    if (!ready()) return
    setBusy(true)
    setProblem(null)
    setQuota(null)
    try {
      const file = picture()
      let result: CaptureResult
      if (file) {
        const { shrinkImage } = await import('../lib/capture/image')
        result = await startCapture({ data: await shrinkImage(file) })
      } else {
        const typed = captureSend(text())
        if (!typed) return
        result = await startCapture({ data: typed })
      }
      if ('quota' in result) {
        setQuota(result.quota)
        return
      }
      setText('')
      clearPicture()
      await navigate({ to: '/app/imports/$id', params: { id: result.job.id } })
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : 'Aaru could not take that capture.',
      )
    } finally {
      setBusy(false)
    }
  }

  return (
    <form
      class="mt-6"
      aria-label="Capture"
      onSubmit={(event) => void send(event)}
      onDragOver={(event) => {
        if (!event.dataTransfer?.types.includes('Files')) return
        event.preventDefault()
        setOver(true)
      }}
      onDragLeave={() => setOver(false)}
      onDrop={(event) => {
        event.preventDefault()
        setOver(false)
        choose(event.dataTransfer?.files[0])
      }}
    >
      <div
        class="flex items-end gap-2 rounded-card border bg-surface p-2 pl-4 transition-colors focus-within:border-line-strong"
        classList={{ 'border-accent': over(), 'border-line': !over() }}
      >
        <Show when={preview()}>
          {(url) => (
            <span class="relative my-1 shrink-0">
              <img
                src={url()}
                alt="The picture to send"
                class="size-12 rounded-[10px] object-cover"
              />
              <Button
                variant="ink"
                size="bare"
                aria-label="Remove the picture"
                class="absolute -top-1.5 -right-1.5 size-5 rounded-full text-xs"
                onClick={clearPicture}
              >
                ×
              </Button>
            </span>
          )}
        </Show>
        <TextField
          class="min-w-0 flex-1 gap-0"
          value={text()}
          onChange={setText}
          disabled={busy() || picture() !== null}
        >
          <TextFieldLabel class="sr-only">
            Paste titles, a link or a screenshot
          </TextFieldLabel>
          <TextFieldTextArea
            rows={1}
            placeholder={
              picture()
                ? 'Aaru reads the titles in the picture'
                : 'Paste titles, a link or a screenshot'
            }
            class="field-sizing-content max-h-40 min-h-11 resize-none rounded-none border-0 bg-transparent px-0 py-2.5 focus-visible:ring-0"
            onPaste={(event) => {
              const file = [...(event.clipboardData?.files ?? [])].find((f) =>
                f.type.startsWith('image/'),
              )
              if (!file) return
              event.preventDefault()
              choose(file)
            }}
            onKeyDown={(event) => {
              if (event.key === 'Enter' && (event.metaKey || event.ctrlKey))
                event.currentTarget.form?.requestSubmit()
            }}
          />
        </TextField>
        <Button
          type="button"
          variant="soft"
          size="icon"
          class="shrink-0 rounded-full text-muted"
          aria-label="Add a screenshot"
          disabled={busy()}
          onClick={pick}
        >
          <PictureIcon class="size-5" />
        </Button>
        <Button type="submit" class="shrink-0" disabled={!ready()}>
          {busy() ? 'Sending…' : 'Send'}
        </Button>
      </div>
      <p class="mt-2 text-sm text-muted">
        Nothing is added until you approve what Aaru found.
      </p>
      <Show when={problem()}>
        {(message) => (
          <p role="alert" class="mt-1 text-sm text-danger">
            {message()}
          </p>
        )}
      </Show>
      <Show when={quota()}>
        {(message) => (
          <p role="status" class="mt-1 text-sm">
            {message()} Aaru Plus is bought in the Aaru app on iPhone, iPad or
            Mac, and works here too.
          </p>
        )}
      </Show>
    </form>
  )
}

/** The picture button's icon, drawn like the shell's line icons. */
function PictureIcon(props: { class?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.75"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      class={props.class}
    >
      <rect x="3.5" y="5" width="17" height="14" rx="2" />
      <circle cx="9" cy="10" r="1.5" />
      <path d="m20.5 16-4.5-4.5L7 19" />
    </svg>
  )
}
