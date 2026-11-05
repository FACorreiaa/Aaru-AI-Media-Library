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
import { cancelReply, wrote } from '../../lib/assistant/reply'
import type { Reply } from '../../lib/assistant/reply'
import { chatThread, chatsCleared } from '../../lib/assistant/session'
import type { ChatHint } from '../../lib/assistant/thread'
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
import { PlanCard } from '../PlanCard'
import { AgentCards } from '../groups/AgentParts'
import { CloseIcon, MicIcon, SpeakerIcon, SpeakerOffIcon } from '../shell/icons'

// ASK-009 on the web (DESIGN.md "Assistant"): the card the owl opens over the current page. The
// page behind dims and takes no input; Esc, the close button or a swipe down closes it, and
// closing cancels the turn (a write already applied stays journaled). Chrome only: the reply
// fills it with catalog components (title cards, a PlanCard) and the Undo ribbon.

type Turn = {
  id: number
  question: string
  reply: Reply
  /** Spoken, so the reply is read aloud in this language. */
  language: string | null
  undone: boolean
}

type Mic = 'idle' | 'listening' | 'reading'

const MAX_QUESTION = 4000

export function AssistantCard(props: {
  open: boolean
  /** Opened by a long press or ⌥ with the shortcut: listening at once. */
  listen: boolean
  voice: boolean
  hint: () => ChatHint | undefined
  onOpenChange: (open: boolean) => void
  /** The library may have changed: the page behind loads again. */
  onWrote: () => void
}) {
  const [turns, setTurns] = createSignal<Turn[]>([])
  const [text, setText] = createSignal('')
  const [mic, setMic] = createSignal<Mic>('idle')
  const [level, setLevel] = createSignal(-160)
  const [problem, setProblem] = createSignal<string | null>(null)
  const [muted, setMuted] = createSignal(readAloudMuted())
  const [field, setField] = createSignal<HTMLTextAreaElement>()
  let list: HTMLOListElement | undefined
  let controller: AbortController | null = null
  let recorder: Recorder | null = null
  let nextID = 0
  let changed = false

  // Read fresh after an await: the card may have closed meanwhile.
  const isOpen = () => props.open
  const working = () => turns().some((t) => t.reply.state === 'working')
  const micOn = () => props.voice && canRecord()

  function update(id: number, change: (turn: Turn) => Turn) {
    setTurns((all) => all.map((t) => (t.id === id ? change(t) : t)))
    queueMicrotask(() =>
      list?.lastElementChild?.scrollIntoView({ block: 'end' }),
    )
  }

  async function ask(question: string, language: string | null) {
    const body = question.trim().slice(0, MAX_QUESTION)
    if (!body || working()) return
    setProblem(null)
    setText('')
    stopReading()
    const id = ++nextID
    controller = new AbortController()
    const signal = controller.signal
    setTurns((all) => [
      ...all,
      {
        id,
        question: body,
        reply: {
          text: '',
          status: null,
          titles: [],
          plan: null,
          importId: null,
          actionId: null,
          actionSummary: null,
          state: 'working',
          problem: null,
        },
        language,
        undone: false,
      },
    ])
    const reply = await chatThread().send(body, props.hint(), signal, (r) =>
      update(id, (t) => ({ ...t, reply: r })),
    )
    update(id, (t) => ({ ...t, reply }))
    if (wrote(reply)) changed = true
    if (language !== null && !muted() && reply.state === 'answered')
      readAloud(spokenText(reply.text), language)
  }

  async function listen() {
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

  function opened() {
    // Over 15 minutes away, the card starts clean, as a new chat does.
    if (!chatThread().reopen()) setTurns([])
    if (props.listen && micOn()) void listen()
  }

  // Delete my chats empties the card as well as the server.
  createEffect(on(chatsCleared, () => setTurns([]), { defer: true }))

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

        <div class="min-h-0 flex-1 overflow-y-auto px-5 py-4">
          <Show
            when={turns().length > 0}
            fallback={
              <p class="text-sm text-muted">
                Ask about your library, what's on, or what to add. "Recommend
                X-Men books in reading order" works too.
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

        <form
          class="flex items-end gap-2 border-t border-line px-5 pt-3 pb-[max(1rem,env(safe-area-inset-bottom))]"
          onSubmit={(event) => {
            event.preventDefault()
            void ask(text(), null)
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
            <Button
              type="submit"
              class="h-11 shrink-0"
              disabled={!text().trim() || working()}
            >
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
      <p class="ml-12 self-end rounded-2xl bg-accent/10 px-4 py-2 whitespace-pre-line">
        {props.turn.question}
      </p>
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
      <Show when={reply().importId}>
        {(id) => (
          <div>
            <Link
              to="/app/imports/$id"
              params={{ id: id() }}
              onClick={props.onClose}
              class="inline-flex h-10 items-center rounded-full bg-accent px-4 text-sm font-semibold text-on-accent"
            >
              Review the list
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
