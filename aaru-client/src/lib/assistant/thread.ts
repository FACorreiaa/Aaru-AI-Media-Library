import type { components } from '../api/schema'
import { FrameParser } from './frames'
import {
  applyFrame,
  cancelReply,
  failReply,
  newReply,
  streamEnded,
} from './reply'
import type { Reply } from './reply'

// One chat with Aaru (AaruAPI's ChatThread, on the web). A chat continues for 15 minutes after
// its last turn; then the next question starts a new one. Holds no UI state.

export type ChatHint = components['schemas']['ChatHint']

export const IDLE_MS = 15 * 60_000
export const BUSY_TRIES = 3
export const UNREACHABLE =
  'Aaru could not reach the server. Try again in a moment.'

export type ThreadDeps = {
  createChat: () => Promise<string>
  fetch: typeof fetch
  now: () => number
  delay: (ms: number) => Promise<void>
  busyRetryMs: number
}

export class ChatThread {
  private chatId: string | null = null
  private lastUsed: number
  /** Bumped by `reset()`; a send that started before it must not touch the chat afterwards. */
  private generation = 0

  constructor(private deps: ThreadDeps) {
    this.lastUsed = deps.now()
  }

  /** On opening the card. False: over 15 minutes idle, so the next send starts a new chat. */
  reopen(): boolean {
    if (this.chatId === null) return true
    if (this.deps.now() - this.lastUsed > IDLE_MS) {
      this.chatId = null
      return false
    }
    return true
  }

  /** Forgets the chat: Delete my chats. */
  reset() {
    this.generation += 1
    this.chatId = null
  }

  /** One Chat turn. `onUpdate` gets the reply after every frame. Never throws. */
  async send(
    body: string,
    hint: ChatHint | undefined,
    signal: AbortSignal,
    onUpdate: (reply: Reply) => void,
  ): Promise<Reply> {
    this.lastUsed = this.deps.now()
    let reply = newReply()
    const started = this.generation
    const stale = () => signal.aborted || this.generation !== started
    let recreated = false
    let busy = 0
    for (;;) {
      if (stale()) return cancelReply(reply)
      if (this.chatId === null) {
        try {
          const created = await this.deps.createChat()
          if (stale()) return cancelReply(reply)
          this.chatId = created
        } catch (error) {
          return failReply(
            reply,
            error instanceof Error ? error.message : UNREACHABLE,
          )
        }
      }
      const chat = this.chatId
      let response: Response
      try {
        response = await this.deps.fetch(
          `/app/assistant/turn?chat=${encodeURIComponent(chat)}`,
          {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ body, hint }),
            signal,
          },
        )
      } catch {
        return stale() ? cancelReply(reply) : failReply(reply, UNREACHABLE)
      }
      if (stale()) return cancelReply(reply)
      if (response.ok && response.body) {
        reply = await this.read(response.body, reply, signal, onUpdate)
        this.lastUsed = this.deps.now()
        return reply
      }
      const message = await messageOf(response)
      if (response.status === 404 && !recreated) {
        recreated = true
        if (this.chatId === chat) this.chatId = null
        continue
      }
      if (response.status === 409) {
        busy += 1
        if (busy >= BUSY_TRIES)
          return failReply(
            reply,
            'Aaru is still finishing the last answer. Try again in a moment.',
          )
        await this.deps.delay(this.deps.busyRetryMs)
        continue
      }
      return failReply(reply, message)
    }
  }

  private async read(
    stream: ReadableStream<Uint8Array>,
    start: Reply,
    signal: AbortSignal,
    onUpdate: (reply: Reply) => void,
  ): Promise<Reply> {
    let reply = start
    const parser = new FrameParser()
    const decoder = new TextDecoder()
    const reader = stream.getReader()
    try {
      for (;;) {
        const { done, value } = await reader.read()
        if (done) break
        for (const frame of parser.consume(
          decoder.decode(value, { stream: true }),
        )) {
          reply = applyFrame(reply, frame)
          onUpdate(reply)
        }
        if (reply.state !== 'working') {
          await reader.cancel().catch(() => undefined)
          return reply
        }
      }
    } catch {
      return signal.aborted ? cancelReply(reply) : streamEnded(reply)
    }
    return signal.aborted ? cancelReply(reply) : streamEnded(reply)
  }
}

async function messageOf(response: Response): Promise<string> {
  try {
    const json = await response.json<{ message?: unknown }>()
    if (typeof json.message === 'string' && json.message) return json.message
  } catch {
    // Not JSON: the plain line below.
  }
  return UNREACHABLE
}
