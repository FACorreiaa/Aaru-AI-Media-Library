import { createSignal } from 'solid-js'
import { createChat } from './server'
import { ChatThread } from './thread'

// One chat thread for the page's life, so a chat continues across openings of the card for 15
// minutes. Settings resets it after Delete my chats.

let thread: ChatThread | null = null
const [cleared, setCleared] = createSignal(0)

/** Bumped when the chats are deleted, so the card empties too. */
export const chatsCleared = cleared

export function chatThread(): ChatThread {
  thread ??= new ChatThread({
    createChat: () => createChat(),
    fetch: (input, init) => fetch(input, init),
    now: () => Date.now(),
    delay: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    busyRetryMs: 1000,
  })
  return thread
}

const [wanted, setWanted] = createSignal<{ id: string; n: number } | null>(null)

/** A chat someone asked to open from outside the card (Settings); the card loads it. */
export const chatWanted = wanted

/** Asks the card to show this stored chat the next time it is open (ASK-011). */
export function wantAssistantChat(id: string) {
  setWanted((was) => ({ id, n: (was?.n ?? 0) + 1 }))
}

/** Forgets the chat and empties the card: New chat, or after Delete my chats. */
export function resetAssistantChat() {
  thread?.reset()
  setCleared((n) => n + 1)
}

/** One chat was deleted: the card empties only if it was showing that one. */
export function forgetAssistantChat(chatId: string) {
  if (thread?.current()?.toLowerCase() === chatId.toLowerCase())
    resetAssistantChat()
}
