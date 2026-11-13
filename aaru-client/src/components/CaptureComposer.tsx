import { useNavigate } from '@tanstack/solid-router'
import { For, Show, createSignal, onCleanup } from 'solid-js'
import {
  Button,
  TextField,
  TextFieldLabel,
  TextFieldTextArea,
} from '~/components/ui'
import { MAX_CAPTURE_PICTURES, captureSend } from '../lib/capture/model'
import { startCapture } from '../lib/capture/server'
import type { CaptureResult } from '../lib/capture/server'
import { useAppShell } from './shell/context'

type Picture = { file: File; url: string }

// DESIGN §1 and §11: the Field's one composer. Paste a list, a link or up to five screenshots (or
// drop them on it); Aaru reads them into an import the user reviews before anything is added.
// The Books page passes its kind: only books are read, and the words say so (BOOK-001).
export function CaptureComposer(props: { kind?: 'book'; class?: string }) {
  const navigate = useNavigate()
  const shell = useAppShell()
  const books = () => props.kind === 'book'
  const [text, setText] = createSignal('')
  const [pictures, setPictures] = createSignal<Picture[]>([])
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  const [over, setOver] = createSignal(false)

  const placeholder = () => {
    if (pictures().length > 0)
      return books()
        ? 'Aaru reads the books in the picture'
        : 'Aaru reads the titles in the picture'
    return books()
      ? 'Paste a chat or a list of books, or ask for books'
      : 'Paste titles, a link or a screenshot'
  }

  function choose(files: Iterable<File> | null | undefined) {
    const images = [...(files ?? [])].filter((f) => f.type.startsWith('image/'))
    if (images.length === 0) return
    const room = MAX_CAPTURE_PICTURES - pictures().length
    setProblem(
      images.length > room
        ? `Aaru reads ${MAX_CAPTURE_PICTURES} pictures at a time.`
        : null,
    )
    setPictures((current) => [
      ...current,
      ...images
        .slice(0, Math.max(0, room))
        .map((file) => ({ file, url: URL.createObjectURL(file) })),
    ])
  }

  function remove(picture: Picture) {
    URL.revokeObjectURL(picture.url)
    setPictures((current) => current.filter((p) => p !== picture))
  }

  function clearPictures() {
    for (const picture of pictures()) URL.revokeObjectURL(picture.url)
    setPictures([])
  }

  /** The system's picker, opened from the picture button; nothing lives in the page. */
  function pick() {
    const input = document.createElement('input')
    input.type = 'file'
    input.multiple = true
    input.accept = 'image/jpeg,image/png,image/gif,image/webp,image/heic'
    input.onchange = () => choose(input.files)
    input.click()
  }
  onCleanup(clearPictures)

  const ready = () =>
    !busy() && (pictures().length > 0 || captureSend(text()) !== null)

  async function send(event: SubmitEvent) {
    event.preventDefault()
    if (!ready()) return
    // PRV-002: text and pictures go to the AI provider; a link alone is read by Aaru and does not.
    const typed = captureSend(text())
    const link = pictures().length === 0 && typed !== null && 'url' in typed
    if (!link && !(await shell.ensureAiSharing())) return
    setBusy(true)
    setProblem(null)
    try {
      let result: CaptureResult
      if (pictures().length > 0) {
        const { capturePieces } = await import('../lib/capture/image')
        const images = (
          await Promise.all(pictures().map((p) => capturePieces(p.file)))
        ).flat()
        if (images.length > MAX_CAPTURE_PICTURES)
          throw new Error("That's long. Paste the text instead.")
        result = await startCapture({ data: { images, kind: props.kind } })
      } else {
        if (!typed) return
        result = await startCapture({ data: { ...typed, kind: props.kind } })
      }
      setText('')
      clearPictures()
      await navigate({
        to: '/app/imports/$id',
        params: { id: result.job.id },
        search: { from: books() ? 'books' : undefined },
      })
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
      class={props.class ?? 'mt-6'}
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
        choose(event.dataTransfer?.files)
      }}
    >
      <div
        class="flex items-end gap-2 rounded-card border bg-surface p-2 pl-4 transition-colors focus-within:border-line-strong"
        classList={{ 'border-accent': over(), 'border-line': !over() }}
      >
        <For each={pictures()}>
          {(picture) => (
            <span class="relative my-1 shrink-0">
              <img
                src={picture.url}
                alt="A picture to send"
                class="size-12 rounded-field object-cover"
              />
              <Button
                variant="ink"
                size="bare"
                aria-label="Remove the picture"
                class="absolute -top-1.5 -right-1.5 size-5 rounded-full text-xs"
                onClick={() => remove(picture)}
              >
                ×
              </Button>
            </span>
          )}
        </For>
        <TextField
          class="min-w-0 flex-1 gap-0"
          value={text()}
          onChange={setText}
          disabled={busy() || pictures().length > 0}
        >
          <TextFieldLabel class="sr-only">{placeholder()}</TextFieldLabel>
          <TextFieldTextArea
            rows={1}
            placeholder={placeholder()}
            class="field-sizing-content max-h-40 min-h-11 resize-none rounded-none border-0 bg-transparent px-0 py-2.5 focus-visible:ring-0"
            onPaste={(event) => {
              const files = [...(event.clipboardData?.files ?? [])].filter(
                (f) => f.type.startsWith('image/'),
              )
              if (files.length === 0) return
              event.preventDefault()
              choose(files)
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
          disabled={busy() || pictures().length >= MAX_CAPTURE_PICTURES}
          onClick={pick}
        >
          <PictureIcon class="size-5" />
        </Button>
        <Button type="submit" class="shrink-0" disabled={!ready()}>
          {busy() ? 'Sending…' : 'Send'}
        </Button>
      </div>
      <p class="mt-2 text-sm text-muted">
        {books()
          ? 'A whole ChatGPT chat, screenshots, a photo of a list, or a request like “X-Men books in reading order”. Nothing is added until you approve.'
          : 'Nothing is added until you approve what Aaru found.'}
      </p>
      <Show when={problem()}>
        {(message) => (
          <p role="alert" class="mt-1 text-sm text-danger">
            {message()}
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
