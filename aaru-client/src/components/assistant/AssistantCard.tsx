import { Link } from '@tanstack/solid-router'
import { For, Show, createEffect, createSignal, on, onCleanup } from 'solid-js'
import {
  Button,
  Drawer,
  DrawerContent,
  DrawerDescription,
  DrawerLabel,
  TextField,
  TextFieldLabel,
  TextFieldTextArea,
} from '~/components/ui'
import {
  cancelReply,
  exchangesOf,
  newReply,
  wrote,
} from '../../lib/assistant/reply'
import type { Reply } from '../../lib/assistant/reply'
import { getChat } from '../../lib/assistant/server'
import {
  chatThread,
  chatWanted,
  chatsCleared,
  resetAssistantChat,
} from '../../lib/assistant/session'
import type { ChatAttachment, ChatHint } from '../../lib/assistant/thread'
import {
  ACCEPT,
  MAX_TURN_FILES,
  PASTE_AS_FILE,
  pastedText,
  piecesOf,
} from '../../lib/assistant/files'
import type { Piece } from '../../lib/assistant/files'
import {
  canRecord,
  readAloud,
  readAloudMuted,
  setReadAloudMuted,
  startRecording,
  stopReading,
  transcribe,
} from '../../lib/assistant/voice'
import type { Recorder } from '../../lib/assistant/voice'
import { spokenText } from '../../lib/assistant/silence'
import { parseInline } from '../../lib/markdown'
import { undoAction } from '../../lib/history/server'
import { OwlMark } from '../Brand'
import { useAppShell } from '../shell/context'
import { PlanCard } from '../PlanCard'
import { AgentCards } from '../groups/AgentParts'
import { ChatHistory } from './ChatHistory'
import { RoadmapCard } from './RoadmapCard'
import {
  CloseIcon,
  MicIcon,
  PaperclipIcon,
  SpeakerIcon,
  SpeakerOffIcon,
} from '../shell/icons'

// ASK-009 on the web (DESIGN.md "Assistant"): the card the owl opens over the current page. The
// page behind dims and takes no input; Esc, the close button or a swipe down closes it, and
// closing cancels the turn (a write already applied stays journaled). Chrome only: the reply
// fills it with catalog components (title cards, a PlanCard) and the Undo ribbon.

type Turn = {
  id: number
  question: string
  /** The names of the files it carried (ASK-010). */
  files: string[]
  reply: Reply
  /** Spoken, so the reply is read aloud in this language. */
  language: string | null
  undone: boolean
}

type Mic = 'idle' | 'listening' | 'reading'

/** A file on its way into the next turn: still being read by the server, or ready to send. */
type Chip = {
  key: number
  name: string
  attachment: ChatAttachment | null
  /** The chat it went into: a chip from a chat that has since ended is gone. */
  chat: string | null
}

const MAX_QUESTION = 4000

export function AssistantCard(props: {
  open: boolean
  /** Opened by a long press or ⌥ with the shortcut: listening at once. */
  listen: boolean
  /** A question a page asked for the person (the shell's `askAssistant`): sent once the card is open. */
  question: string | null
  onAsked: () => void
  voice: boolean
  hint: () => ChatHint | undefined
  onOpenChange: (open: boolean) => void
  /** The library may have changed: the page behind loads again. */
  onWrote: () => void
}) {
  const shell = useAppShell()
  const [turns, setTurns] = createSignal<Turn[]>([])
  const [text, setText] = createSignal('')
  const [mic, setMic] = createSignal<Mic>('idle')
  const [level, setLevel] = createSignal(-160)
  const [problem, setProblem] = createSignal<string | null>(null)
  const [muted, setMuted] = createSignal(readAloudMuted())
  const [chips, setChips] = createSignal<Chip[]>([])
  const [over, setOver] = createSignal(false)
  const [field, setField] = createSignal<HTMLTextAreaElement>()
  /** The chat, or the list of past chats (ASK-011). */
  const [view, setView] = createSignal<'chat' | 'history'>('chat')
  const [opening, setOpening] = createSignal(false)
  let list: HTMLOListElement | undefined
  let controller: AbortController | null = null
  let recorder: Recorder | null = null
  let nextID = 0
  let nextChip = 0
  let changed = false
  let attaching = new AbortController()

  // Read fresh after an await: the card may have closed meanwhile.
  const isOpen = () => props.open
  const working = () => turns().some((t) => t.reply.state === 'working')
  const micOn = () => props.voice && canRecord()
  const reading = () => chips().some((c) => c.attachment === null)
  const ready = () =>
    chips().filter(
      (c) => c.attachment !== null && c.chat === chatThread().current(),
    )
  const canAsk = () =>
    !working() && !reading() && (text().trim() !== '' || ready().length > 0)

  /** Files chosen, dropped or pasted: each sent to the chat as it is picked. */
  async function choose(files: Iterable<File> | null | undefined) {
    const picked = [...(files ?? [])]
    if (picked.length === 0) return
    if (!(await shell.ensureAiSharing())) return
    setProblem(null)
    try {
      const pieces = (await Promise.all(picked.map(piecesOf))).flat()
      await addPieces(pieces)
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'Aaru could not read that.',
      )
    }
  }

  async function addPieces(pieces: Piece[]) {
    if (chips().length + pieces.length > MAX_TURN_FILES) {
      setProblem(`Send up to ${MAX_TURN_FILES} files at a time.`)
      return
    }
    const signal = attaching.signal
    await Promise.all(
      pieces.map(async (piece) => {
        const key = ++nextChip
        setChips((all) => [
          ...all,
          {
            key,
            name: piece.name || 'Pasted text',
            attachment: null,
            chat: null,
          },
        ])
        try {
          const { chat, attachment } = await chatThread().attach(
            piece.blob,
            piece.name,
            signal,
          )
          setChips((all) =>
            all.map((c) =>
              c.key === key
                ? { ...c, attachment, chat, name: attachment.name }
                : c,
            ),
          )
        } catch (error) {
          setChips((all) => all.filter((c) => c.key !== key))
          if (!signal.aborted)
            setProblem(
              error instanceof Error
                ? `${piece.name || 'That text'}: ${error.message}`
                : 'Aaru could not read that file.',
            )
        }
      }),
    )
  }

  function removeChip(chip: Chip) {
    setChips((all) => all.filter((c) => c.key !== chip.key))
    if (chip.attachment && chip.chat)
      void chatThread().detach(chip.chat, chip.attachment.id)
  }

  function clearChips() {
    attaching.abort()
    attaching = new AbortController()
    setChips([])
  }

  /** The system's picker; nothing lives in the page. */
  function pick() {
    const input = document.createElement('input')
    input.type = 'file'
    input.multiple = true
    input.accept = ACCEPT
    input.onchange = () => void choose(input.files)
    input.click()
  }

  function update(id: number, change: (turn: Turn) => Turn) {
    setTurns((all) => all.map((t) => (t.id === id ? change(t) : t)))
    queueMicrotask(() =>
      list?.lastElementChild?.scrollIntoView({ block: 'end' }),
    )
  }

  async function ask(question: string, language: string | null) {
    const body = question.trim().slice(0, MAX_QUESTION)
    if ((!body && ready().length === 0) || working() || reading()) return
    // PRV-002: nothing goes to the AI provider without a yes; the question stays in the box.
    if (!(await shell.ensureAiSharing()) || !isOpen()) return
    const sent = ready()
    if ((!body && sent.length === 0) || working() || reading()) return
    setProblem(null)
    setText('')
    setChips([])
    stopReading()
    const id = ++nextID
    controller = new AbortController()
    const signal = controller.signal
    setTurns((all) => [
      ...all,
      {
        id,
        question: body,
        files: sent.map((c) => c.name),
        reply: newReply(),
        language,
        undone: false,
      },
    ])
    const reply = await chatThread().send(
      body,
      props.hint(),
      signal,
      (r) => update(id, (t) => ({ ...t, reply: r })),
      sent.flatMap((c) => (c.attachment ? [c.attachment.id] : [])),
    )
    update(id, (t) => ({ ...t, reply }))
    if (wrote(reply)) changed = true
    if (language !== null && !muted() && reply.state === 'answered')
      readAloud(spokenText(reply.text), language)
  }

  async function listen() {
    if (mic() !== 'idle' || working()) return
    if (!(await shell.ensureAiSharing()) || !isOpen()) return
    if (mic() !== 'idle' || working()) return
    setProblem(null)
    stopReading()
    try {
      recorder = await startRecording(setLevel)
    } catch {
      setProblem(
        'Aaru cannot use the microphone. Allow it in the browser, or type instead.',
      )
      return
    }
    setMic('listening')
    const recording = await recorder.done
    recorder = null
    if (!isOpen()) return setMic('idle')
    if (recording.kind === 'noSpeech') {
      setMic('idle')
      setProblem("I didn't catch that.")
      return
    }
    setMic('reading')
    try {
      const said = await transcribe(recording)
      setMic('idle')
      if (isOpen()) await ask(said.text, said.language)
    } catch (error) {
      setMic('idle')
      setProblem(
        error instanceof Error ? error.message : 'Aaru could not read that.',
      )
    }
  }

  /** Ends the chat on screen and starts an empty one (ASK-011). */
  function newChat() {
    controller?.abort()
    recorder?.cancel()
    stopReading()
    setProblem(null)
    setView('chat')
    // Empties the turns and the chips through `chatsCleared`.
    resetAssistantChat()
    field()?.focus()
  }

  /** Shows a chat from history; the next question continues it (ASK-011). */
  async function openStored(id: string) {
    if (opening()) return
    controller?.abort()
    recorder?.cancel()
    stopReading()
    setProblem(null)
    setOpening(true)
    try {
      const chat = await getChat({ data: { id } })
      if (!isOpen()) return
      clearChips()
      setTurns(
        exchangesOf(chat.turns).map((exchange) => ({
          id: ++nextID,
          question: exchange.question,
          files: [],
          reply: exchange.reply,
          language: null,
          undone: false,
        })),
      )
      chatThread().adopt(chat.id)
      setView('chat')
      queueMicrotask(() =>
        list?.lastElementChild?.scrollIntoView({ block: 'end' }),
      )
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : 'That chat could not be opened.',
      )
    } finally {
      setOpening(false)
    }
  }

  function close() {
    controller?.abort()
    recorder?.cancel()
    stopReading()
    setTurns((all) => all.map((t) => ({ ...t, reply: cancelReply(t.reply) })))
    if (changed) {
      changed = false
      props.onWrote()
    }
  }

  onCleanup(close)

  let shown = 0

  function opened() {
    setView('chat')
    // Over 15 minutes away, the card starts clean, as a new chat does.
    if (!chatThread().reopen()) {
      setTurns([])
      clearChips()
    }
    // A chat picked in Settings: shown once, then the card is its own again.
    const wanted = chatWanted()
    if (wanted && wanted.n !== shown) {
      shown = wanted.n
      void openStored(wanted.id)
      return
    }
    if (props.listen && micOn()) void listen()
  }

  // A chat picked while the card is already open is shown at once.
  createEffect(
    on(
      chatWanted,
      (wanted) => {
        if (!wanted || wanted.n === shown || !isOpen()) return
        shown = wanted.n
        void openStored(wanted.id)
      },
      { defer: true },
    ),
  )

  // Delete my chats empties the card as well as the server.
  createEffect(
    on(
      chatsCleared,
      () => {
        setTurns([])
        clearChips()
      },
      { defer: true },
    ),
  )

  // The shell opens and closes the card (the owl, ⌘J, a link inside it), so both are watched
  // here rather than in onOpenChange, which hears only the card's own Esc and swipe.
  createEffect(
    on(
      () => props.open,
      (open, was) => {
        if (open) opened()
        else if (was) close()
      },
    ),
  )

  createEffect(() => {
    const question = props.question
    if (!props.open || !question) return
    props.onAsked()
    void ask(question, null)
  })

  return (
    <Drawer
      side="bottom"
      open={props.open}
      initialFocusEl={field()}
      onOpenChange={props.onOpenChange}
    >
      <DrawerContent
        aria-label="Ask Aaru"
        class="mx-auto w-full max-w-2xl rounded-t-3xl border-line bg-surface shadow-lift"
      >
        <div class="flex items-center gap-3 px-5 pt-3">
          <OwlMark
            class="size-8"
            breathing={working() || mic() === 'reading'}
          />
          <DrawerLabel class="font-display text-lg font-semibold">
            Ask Aaru
          </DrawerLabel>
          <DrawerDescription class="sr-only">
            About your library and the catalog. Nothing changes without your
            yes, and every change can be undone.
          </DrawerDescription>
          <div class="ml-auto flex items-center gap-1">
            <Show when={turns().length > 0 && view() === 'chat'}>
              <Button variant="ghost" size="xs" onClick={newChat}>
                New chat
              </Button>
            </Show>
            <Button
              variant="ghost"
              size="xs"
              aria-pressed={view() === 'history'}
              onClick={() =>
                setView((was) => (was === 'history' ? 'chat' : 'history'))
              }
            >
              {view() === 'history' ? 'Back to chat' : 'History'}
            </Button>
            <Show when={turns().some((t) => t.language !== null)}>
              <Button
                variant="ghost"
                size="icon"
                aria-pressed={muted()}
                aria-label={
                  muted() ? 'Read replies aloud' : 'Stop reading replies aloud'
                }
                onClick={() => {
                  const next = !muted()
                  setMuted(next)
                  setReadAloudMuted(next)
                  if (next) stopReading()
                }}
              >
                <Show when={muted()} fallback={<SpeakerIcon class="size-5" />}>
                  <SpeakerOffIcon class="size-5" />
                </Show>
              </Button>
            </Show>
            <Button
              variant="ghost"
              size="icon"
              aria-label="Close"
              onClick={() => props.onOpenChange(false)}
            >
              <CloseIcon class="size-5" />
            </Button>
          </div>
        </div>

        <Show when={view() === 'history'}>
          <div class="min-h-0 flex-1 overflow-y-auto px-5 py-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
            <h3 class="mb-2 font-display font-semibold">Your chats</h3>
            <Show when={opening()}>
              <p role="status" class="mb-2 text-sm text-muted">
                Opening…
              </p>
            </Show>
            <ChatHistory onOpen={(chat) => void openStored(chat.id)} />
          </div>
        </Show>
        <div
          class="min-h-0 flex-1 overflow-y-auto px-5 py-4"
          classList={{ hidden: view() === 'history' }}
        >
          <Show
            when={turns().length > 0}
            fallback={
              <p class="text-sm text-muted">
                Ask about your library, what's on, or what to add. "Recommend
                X-Men books in reading order" works too, and so does a file: an
                export, a screenshot or a list someone sent you.
              </p>
            }
          >
            <ol ref={list} class="flex flex-col gap-6" aria-live="polite">
              <For each={turns()}>
                {(turn) => (
                  <TurnView
                    turn={turn}
                    onClose={() => props.onOpenChange(false)}
                    onUndone={() => {
                      update(turn.id, (t) => ({ ...t, undone: true }))
                      changed = true
                    }}
                    onDecided={() => {
                      changed = true
                    }}
                  />
                )}
              </For>
            </ol>
          </Show>
        </div>

        <Show when={chips().length > 0 && view() === 'chat'}>
          <ul
            aria-label="Files to send"
            class="flex flex-wrap gap-2 border-t border-line px-5 pt-3"
          >
            <For each={chips()}>
              {(chip) => (
                <li class="flex max-w-full items-center gap-2 rounded-full border border-line bg-paper py-1 pr-1 pl-3 text-sm">
                  <span class="min-w-0 truncate">
                    <span class="font-medium">{chip.name}</span>
                    <span class="text-muted">
                      {chip.attachment
                        ? ` · ${chip.attachment.summary}`
                        : ' · reading…'}
                    </span>
                  </span>
                  <Button
                    variant="ghost"
                    size="icon"
                    class="size-7 shrink-0 rounded-full"
                    aria-label={`Remove ${chip.name}`}
                    onClick={() => removeChip(chip)}
                  >
                    <CloseIcon class="size-4" />
                  </Button>
                </li>
              )}
            </For>
          </ul>
        </Show>
        <form
          class="flex items-end gap-2 border-t px-5 pt-3 pb-[max(1rem,env(safe-area-inset-bottom))] transition-colors"
          classList={{
            hidden: view() === 'history',
            'border-accent': over(),
            'border-line': !over(),
            'border-t-0': chips().length > 0 && !over(),
          }}
          onSubmit={(event) => {
            event.preventDefault()
            void ask(text(), null)
          }}
          onDragOver={(event) => {
            if (!event.dataTransfer?.types.includes('Files')) return
            event.preventDefault()
            setOver(true)
          }}
          onDragLeave={() => setOver(false)}
          onDrop={(event) => {
            event.preventDefault()
            setOver(false)
            void choose(event.dataTransfer?.files)
          }}
        >
          <Show
            when={mic() === 'idle'}
            fallback={
              <p
                role="status"
                class="flex min-h-11 flex-1 items-center gap-3 text-sm text-muted"
              >
                <Show
                  when={mic() === 'listening'}
                  fallback="Reading what you said…"
                >
                  <span>Listening…</span>
                  <LevelMeter level={level()} />
                </Show>
              </p>
            }
          >
            <TextField
              class="min-w-0 flex-1 gap-0"
              value={text()}
              onChange={setText}
            >
              <TextFieldLabel class="sr-only">Ask Aaru</TextFieldLabel>
              <TextFieldTextArea
                ref={setField}
                rows={1}
                maxLength={MAX_QUESTION}
                placeholder="Ask Aaru"
                class="field-sizing-content max-h-40 min-h-11 resize-none rounded-2xl bg-paper px-4 py-2.5"
                onPaste={(event: ClipboardEvent) => {
                  const files = [...(event.clipboardData?.files ?? [])]
                  if (files.length > 0) {
                    event.preventDefault()
                    void choose(files)
                    return
                  }
                  // A whole chat or list is longer than a question: it goes as a file.
                  const pasted =
                    event.clipboardData?.getData('text/plain') ?? ''
                  if (pasted.length > PASTE_AS_FILE) {
                    event.preventDefault()
                    void addPieces([pastedText(pasted)])
                  }
                }}
                onKeyDown={(
                  event: KeyboardEvent & { currentTarget: HTMLTextAreaElement },
                ) => {
                  if (event.key === 'Enter' && !event.shiftKey) {
                    event.preventDefault()
                    event.currentTarget.form?.requestSubmit()
                  }
                }}
              />
            </TextField>
          </Show>
          <Show when={mic() === 'idle'}>
            <Button
              type="button"
              variant="soft"
              size="icon"
              class="size-11 shrink-0 rounded-full"
              aria-label="Attach a file"
              disabled={working() || chips().length >= MAX_TURN_FILES}
              onClick={pick}
            >
              <PaperclipIcon class="size-5" />
            </Button>
          </Show>
          <Show when={micOn()}>
            <Button
              type="button"
              variant={mic() === 'listening' ? 'default' : 'soft'}
              size="icon"
              class="size-11 shrink-0 rounded-full"
              aria-label={
                mic() === 'listening' ? 'Done talking' : 'Ask by voice'
              }
              disabled={working() || mic() === 'reading'}
              onClick={() =>
                mic() === 'listening' ? recorder?.stop() : void listen()
              }
            >
              <MicIcon class="size-5" />
            </Button>
          </Show>
          <Show when={mic() === 'idle'}>
            <Button type="submit" class="h-11 shrink-0" disabled={!canAsk()}>
              Ask
            </Button>
          </Show>
        </form>
        <Show when={problem()}>
          {(line) => <p class="px-5 pb-4 text-sm text-muted">{line()}</p>}
        </Show>
      </DrawerContent>
    </Drawer>
  )
}

function TurnView(props: {
  turn: Turn
  onClose: () => void
  onUndone: () => void
  onDecided: () => void
}) {
  const reply = () => props.turn.reply
  const status = () =>
    reply().status ??
    (reply().state === 'working' && !reply().text ? 'Aaru is thinking…' : null)
  return (
    <li class="flex flex-col gap-3">
      <div class="ml-12 flex flex-col items-end gap-1 self-end">
        <Show when={props.turn.question}>
          <p class="rounded-2xl bg-accent/10 px-4 py-2 whitespace-pre-line">
            {props.turn.question}
          </p>
        </Show>
        <For each={props.turn.files}>
          {(name) => (
            <p class="rounded-full border border-line px-3 py-1 text-sm text-muted">
              <PaperclipIcon class="mr-1 inline size-4 align-text-bottom" />
              {name}
            </p>
          )}
        </For>
      </div>
      <Show when={reply().text}>
        <div class="whitespace-pre-line">
          <For each={parseInline(reply().text)}>
            {(part) =>
              part.kind === 'strong' ? (
                <strong>{part.text}</strong>
              ) : part.kind === 'em' ? (
                <em>{part.text}</em>
              ) : part.kind === 'link' && part.href.startsWith('/') ? (
                <a href={part.href} class="text-accent underline">
                  {part.text}
                </a>
              ) : (
                part.text
              )
            }
          </For>
        </div>
      </Show>
      <Show when={status()}>
        {(line) => <p class="text-sm text-muted">{line()}</p>}
      </Show>
      <Show when={reply().titles.length > 0}>
        <div onClick={(event) => event.target.closest('a') && props.onClose()}>
          <AgentCards
            cards={reply().titles.map((title) => ({
              type: 'title' as const,
              title,
            }))}
          />
        </div>
      </Show>
      <Show when={reply().plan}>
        {(plan) => <PlanCard plan={plan()} onDecided={props.onDecided} />}
      </Show>
      <Show when={reply().roadmap}>
        {(roadmap) => (
          <RoadmapCard
            roadmap={roadmap()}
            importId={reply().importId}
            onReview={props.onClose}
          />
        )}
      </Show>
      <Show when={reply().roadmap ? null : reply().importId}>
        {(id) => (
          <div>
            <Link
              to="/app/imports/$id"
              params={{ id: id() }}
              onClick={props.onClose}
              class="inline-flex h-10 items-center rounded-full bg-accent px-4 text-sm font-semibold text-on-accent"
            >
              Review the import
            </Link>
          </div>
        )}
      </Show>
      <Show when={reply().actionId}>
        {(id) => (
          <UndoRibbon
            actionId={id()}
            summary={reply().actionSummary}
            undone={props.turn.undone}
            onUndone={props.onUndone}
          />
        )}
      </Show>
      <Show when={reply().problem}>
        {(line) => (
          <p
            class={`text-sm ${reply().state === 'stopped' ? 'text-muted' : 'text-danger'}`}
          >
            {line()}
          </p>
        )}
      </Show>
    </li>
  )
}

/** What a turn changed, and its Undo. It stays until the card clears: not a timed toast. */
function UndoRibbon(props: {
  actionId: string
  summary: string | null
  undone: boolean
  onUndone: () => void
}) {
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  async function undo() {
    if (busy()) return
    setBusy(true)
    setProblem(null)
    try {
      await undoAction({ data: { id: props.actionId } })
      props.onUndone()
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'That could not be undone.',
      )
    } finally {
      setBusy(false)
    }
  }
  return (
    <div class="flex flex-wrap items-center gap-3 rounded-2xl border border-line bg-paper px-4 py-2 text-sm">
      <Show
        when={!props.undone}
        fallback={<span class="text-muted">Undone.</span>}
      >
        <span class="min-w-0 flex-1">
          {props.summary ?? 'Changed your library.'}
        </span>
        <Button
          variant="outline"
          size="sm"
          disabled={busy()}
          onClick={() => void undo()}
        >
          Undo
        </Button>
      </Show>
      <Show when={problem()}>
        {(line) => <p class="w-full text-danger">{line()}</p>}
      </Show>
    </div>
  )
}

/** Five bars that follow the microphone's level; still under reduced motion it only steps. */
function LevelMeter(props: { level: number }) {
  // -60 dBFS and below is no bars; -20 and above is all five.
  const lit = () => Math.max(0, Math.min(5, Math.round((props.level + 60) / 8)))
  return (
    <span aria-hidden="true" class="flex h-4 items-end gap-0.5">
      <For each={[1, 2, 3, 4, 5]}>
        {(bar) => (
          <span
            class={`w-1 rounded-full ${bar <= lit() ? 'bg-accent' : 'bg-line'}`}
            style={{ height: `${bar * 20}%` }}
          />
        )}
      </For>
    </span>
  )
}
