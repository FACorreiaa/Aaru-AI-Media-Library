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

/** Forgets the chat, after Delete my chats. */
export function resetAssistantChat() {
  thread?.reset()
  setCleared((n) => n + 1)
}
