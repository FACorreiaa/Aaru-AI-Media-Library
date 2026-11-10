import { For, Show, createSignal, onMount } from 'solid-js'
import { Button } from '~/components/ui'
import { deleteChat, listChats } from '../../lib/assistant/server'
import type { ChatSummary } from '../../lib/assistant/server'
import { forgetAssistantChat } from '../../lib/assistant/session'
import { whenLabel } from '../../lib/history/model'

// ASK-011: the user's chats with Aaru, latest first. A row opens the chat to read and continue;
// Delete asks once more on the row itself. Used in the owl's card and in Settings → Your data.
export function ChatHistory(props: {
  onOpen: (chat: ChatSummary) => void
  class?: string
}) {
  const [chats, setChats] = createSignal<ChatSummary[]>([])
  const [next, setNext] = createSignal<string | null>(null)
  const [loading, setLoading] = createSignal(true)
  const [problem, setProblem] = createSignal<string | null>(null)
  const [asking, setAsking] = createSignal<string | null>(null)
  const [busy, setBusy] = createSignal<string | null>(null)

  async function load(cursor?: string) {
    setLoading(true)
    setProblem(null)
    try {
      const page = await listChats({ data: cursor ? { cursor } : {} })
      setChats((all) => (cursor ? [...all, ...page.items] : page.items))
      setNext(page.page.nextCursor ?? null)
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : 'Your chats could not be loaded.',
      )
    } finally {
      setLoading(false)
    }
  }

  async function remove(chat: ChatSummary) {
    setBusy(chat.id)
    setProblem(null)
    try {
      await deleteChat({ data: { id: chat.id } })
      setChats((all) => all.filter((c) => c.id !== chat.id))
      forgetAssistantChat(chat.id)
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'That chat was not deleted.',
      )
    } finally {
      setBusy(null)
      setAsking(null)
    }
  }

  onMount(() => void load())

  return (
    <div class={props.class}>
      <Show when={problem()}>
        {(line) => (
          <p role="alert" class="mb-3 text-sm text-danger">
            {line()}
          </p>
        )}
      </Show>
      <Show
        when={chats().length > 0}
        fallback={
          <p class="text-sm text-muted">
            {loading() ? 'Loading your chats…' : 'No chats yet.'}
          </p>
        }
      >
        <ul class="divide-y divide-line">
          <For each={chats()}>
            {(chat) => (
              <li class="flex items-center gap-3 py-2">
                <Button
                  variant="soft"
                  size="bare"
                  class="min-w-0 flex-1 flex-col items-start rounded-lg py-1 text-left"
                  onClick={() => props.onOpen(chat)}
                >
                  <span class="line-clamp-2 w-full text-sm font-medium">
                    {chat.title ?? 'A chat with Aaru'}
                  </span>
                  <span class="text-xs font-normal text-muted">
                    {whenLabel(chat.updatedAt)}
                  </span>
                </Button>
                <Show
                  when={asking() === chat.id}
                  fallback={
                    <Button
                      variant="ghost"
                      size="xs"
                      class="shrink-0"
                      aria-label={`Delete the chat: ${chat.title ?? 'untitled'}`}
                      onClick={() => setAsking(chat.id)}
                    >
                      Delete
                    </Button>
                  }
                >
                  <Button
                    variant="danger-outline"
                    size="xs"
                    class="shrink-0"
                    disabled={busy() === chat.id}
                    onClick={() => void remove(chat)}
                  >
                    {busy() === chat.id ? 'Deleting…' : 'Delete chat'}
                  </Button>
                  <Button
                    variant="ghost"
                    size="xs"
                    class="shrink-0"
                    disabled={busy() === chat.id}
                    onClick={() => setAsking(null)}
                  >
                    Keep
                  </Button>
                </Show>
              </li>
            )}
          </For>
        </ul>
        <Show when={next()}>
          {(cursor) => (
            <Button
              variant="outline"
              size="sm"
              class="mt-3"
              disabled={loading()}
              onClick={() => void load(cursor())}
            >
              {loading() ? 'Loading…' : 'Show more'}
            </Button>
          )}
        </Show>
      </Show>
    </div>
  )
}
