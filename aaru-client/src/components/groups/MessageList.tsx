import { Link } from '@tanstack/solid-router'
import {
  For,
  Match,
  Show,
  Switch,
  createEffect,
  createMemo,
  createSignal,
  on,
  onMount,
} from 'solid-js'
import {
  buildTimeline,
  dayLabel,
  failPending,
  mergeMessages,
  newLineIndex,
  retryPending,
  settlePending,
  splitMentions,
  timeLabel,
} from '../../lib/groups/model'
import type { PendingMessage } from '../../lib/groups/model'
import {
  deleteMessage,
  editMessage,
  listMessages,
  markChannelRead,
  postMessage,
} from '../../lib/groups/server'
import type { Channel, GroupMessage } from '../../lib/groups/server'
import { monogram } from '../../lib/social/model'
import { Composer } from './Composer'
import { Monogram, useGroup, useShell, useVisiblePoll } from './shell'

export const PAGE_SIZE = 50

/**
 * MessageList (GRP-005): one channel's conversation and its composer. Flat rows grouped into
 * runs, day dividers, a "New" line where you stopped reading, pinned to the bottom with "Jump
 * to present". Until the realtime gateway (M3) it polls while the page is visible.
 */
export function MessageList(props: {
  channel: Channel
  initial: GroupMessage[]
  onOpenMembers: () => void
}) {
  const shell = useShell()
  const scope = useGroup()
  const meId = () => shell.me().userId
  const groupId = () => scope.detail().group.id
  const ref = () => ({ groupId: groupId(), channelId: props.channel.id })

  const [messages, setMessages] = createSignal<GroupMessage[]>(props.initial)
  const [pending, setPending] = createSignal<PendingMessage[]>([])
  const [hasOlder, setHasOlder] = createSignal(
    props.initial.length >= PAGE_SIZE,
  )
  const [loadingOlder, setLoadingOlder] = createSignal(false)
  const [atBottom, setAtBottom] = createSignal(true)
  const [missed, setMissed] = createSignal(0)
  const [problem, setProblem] = createSignal<string | null>(null)
  const [revealed, setRevealed] = createSignal<Set<string>>(new Set())
  const [editing, setEditing] = createSignal<string | null>(null)
  const [confirmDelete, setConfirmDelete] = createSignal<string | null>(null)
  let scroller: HTMLDivElement | undefined
  let markedId: string | null = null

  // The "New" line stays on the message it was first drawn above, even as pages load.
  const firstUnread = (() => {
    const at = newLineIndex(props.initial, props.channel.unread, meId())
    return at >= 0 ? props.initial[at].id : null
  })()

  const handles = createMemo(
    () => new Set(scope.detail().members.map((m) => m.user.handle)),
  )
  const myHandle = () => shell.me().handle
  const manages = () => scope.detail().group.role !== 'member'
  const timeline = createMemo(() => {
    const list = messages()
    const at = firstUnread ? list.findIndex((m) => m.id === firstUnread) : -1
    return buildTimeline(list, pending(), {
      meId: meId(),
      newLineAt: at >= 0 ? at : undefined,
    })
  })
  const lastId = () => messages().at(-1)?.id

  function distanceFromBottom() {
    if (!scroller) return 0
    return scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight
  }

  function scrollToBottom(smooth = false) {
    if (!scroller) return
    scroller.scrollTo({
      top: scroller.scrollHeight,
      behavior: smooth ? 'smooth' : 'auto',
    })
    setMissed(0)
  }

  onMount(() => {
    const line = scroller?.querySelector('[data-new-line]')
    if (line && scroller) {
      line.scrollIntoView({ block: 'center' })
      setAtBottom(distanceFromBottom() < 80)
    } else {
      scrollToBottom()
    }
    void markRead()
  })

  // Stay pinned to the bottom as messages arrive, unless the reader scrolled up.
  createEffect(
    on(
      () => [messages().length, pending().length],
      () => {
        if (atBottom()) requestAnimationFrame(() => scrollToBottom())
      },
      { defer: true },
    ),
  )

  async function markRead() {
    const id = lastId()
    if (!id || id === markedId || document.visibilityState !== 'visible') return
    if (!atBottom()) return
    markedId = id
    try {
      await markChannelRead({ data: { ...ref(), messageId: id } })
      scope.setDetail((detail) => ({
        ...detail,
        channels: detail.channels.map((c) =>
          c.id === props.channel.id ? { ...c, unread: 0, mentions: 0 } : c,
        ),
      }))
      await shell.refresh()
    } catch {
      markedId = null
    }
  }

  createEffect(on([atBottom, lastId], () => void markRead(), { defer: true }))

  useVisiblePoll(async () => {
    const after = lastId()
    const page = await listMessages({
      data: after ? { ...ref(), after } : { ...ref(), limit: PAGE_SIZE },
    })
    if (page.length === 0) return
    const fresh = page.filter((m) => !messages().some((x) => x.id === m.id))
    setMessages(mergeMessages(messages(), page))
    if (!atBottom()) setMissed(missed() + fresh.length)
    void markRead()
  }, 5000)

  async function loadOlder() {
    const first = messages()[0] as GroupMessage | undefined
    if (!first || loadingOlder() || !hasOlder() || !scroller) return
    setLoadingOlder(true)
    const box = scroller
    const before = box.scrollHeight - box.scrollTop
    try {
      const page = await listMessages({
        data: { ...ref(), before: first.id, limit: PAGE_SIZE },
      })
      setHasOlder(page.length >= PAGE_SIZE)
      setMessages(mergeMessages(page, messages()))
      requestAnimationFrame(() => {
        box.scrollTop = box.scrollHeight - before
      })
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'Older messages did not load.',
      )
    } finally {
      setLoadingOlder(false)
    }
  }

  function onScroll() {
    const bottom = distanceFromBottom() < 80
    setAtBottom(bottom)
    if (bottom) setMissed(0)
    if (scroller && scroller.scrollTop < 200) void loadOlder()
  }

  async function deliver(item: PendingMessage) {
    try {
      const saved = await postMessage({
        data: { ...ref(), body: item.body, clientNonce: item.nonce },
      })
      setMessages(mergeMessages(messages(), [saved]))
      setPending(settlePending(pending(), item.nonce))
    } catch {
      setPending(failPending(pending(), item.nonce))
    }
  }

  function send(body: string) {
    const item: PendingMessage = {
      nonce: crypto.randomUUID(),
      body,
      createdAt: new Date().toISOString(),
      state: 'sending',
    }
    setPending([...pending(), item])
    setAtBottom(true)
    void deliver(item)
  }

  async function run(action: () => Promise<void>) {
    setProblem(null)
    try {
      await action()
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'That change was not saved.',
      )
    }
  }

  async function saveEdit(message: GroupMessage, body: string) {
    if (!body.trim() || body.trim() === message.body) {
      setEditing(null)
      return
    }
    await run(async () => {
      const saved = await editMessage({
        data: { ...ref(), messageId: message.id, body },
      })
      setMessages(mergeMessages(messages(), [saved]))
      setEditing(null)
    })
  }

  async function remove(message: GroupMessage) {
    setConfirmDelete(null)
    await run(async () => {
      await deleteMessage({ data: { ...ref(), messageId: message.id } })
      setMessages(
        mergeMessages(messages(), [
          { ...message, body: '', deleted: true, mentions: [] },
        ]),
      )
    })
  }

  function authorMonogram(message: GroupMessage) {
    return message.author ? monogram(message.author) : '·'
  }

  function authorName(message: GroupMessage) {
    const author = message.author
    if (!author) return 'Deleted account'
    return author.displayName ?? `@${author.handle}`
  }

  function Body(bodyProps: { text: string }) {
    return (
      <p class="text-[15px] leading-6 break-words whitespace-pre-wrap">
        <For each={splitMentions(bodyProps.text, handles(), myHandle())}>
          {(segment) =>
            segment.kind === 'text' ? (
              segment.text
            ) : (
              <span
                class={`rounded px-0.5 font-medium ${segment.me ? 'bg-accent/20 text-accent' : 'bg-accent/10 text-accent'}`}
              >
                {segment.text}
              </span>
            )
          }
        </For>
      </p>
    )
  }

  function Header(headerProps: { starts: boolean; name: string; at: string }) {
    return (
      <Show when={headerProps.starts}>
        <div class="flex items-baseline gap-2">
          <span class="truncate text-[15px] font-semibold">
            {headerProps.name}
          </span>
          <time
            datetime={headerProps.at}
            title={new Date(headerProps.at).toLocaleString()}
            class="shrink-0 text-xs text-muted"
          >
            {timeLabel(headerProps.at)}
          </time>
        </div>
      </Show>
    )
  }

  const unreadSummary = () =>
    missed() > 0
      ? `${missed()} new ${missed() === 1 ? 'message' : 'messages'}`
      : 'Jump to present'

  return (
    <section
      aria-label={`#${props.channel.name}`}
      class="flex min-h-0 min-w-0 flex-1 flex-col bg-paper"
    >
      <header class="flex h-14 shrink-0 items-center gap-2 border-b border-line px-3 md:px-4">
        <Link
          to="/app/groups/$groupId"
          params={{ groupId: groupId() }}
          aria-label="Channels"
          class="-ml-1 grid size-9 place-items-center rounded-full text-muted hover:bg-surface hover:text-ink md:hidden"
        >
          <svg
            viewBox="0 0 20 20"
            class="size-5"
            fill="currentColor"
            aria-hidden="true"
          >
            <path d="M12.5 4.2a.75.75 0 0 1 0 1.06L7.8 10l4.7 4.74a.75.75 0 1 1-1.06 1.06l-5.24-5.27a.75.75 0 0 1 0-1.06l5.24-5.27a.75.75 0 0 1 1.06 0Z" />
          </svg>
        </Link>
        <button
          type="button"
          aria-label="Groups and channels"
          onClick={() => shell.setDrawer(true)}
          class="-ml-1 hidden size-9 place-items-center rounded-full text-muted hover:bg-surface hover:text-ink md:max-lg:grid"
        >
          <svg
            viewBox="0 0 20 20"
            class="size-5"
            fill="currentColor"
            aria-hidden="true"
          >
            <path d="M3 5.75A.75.75 0 0 1 3.75 5h12.5a.75.75 0 0 1 0 1.5H3.75A.75.75 0 0 1 3 5.75Zm0 4.25a.75.75 0 0 1 .75-.75h12.5a.75.75 0 0 1 0 1.5H3.75A.75.75 0 0 1 3 10Zm.75 3.5a.75.75 0 0 0 0 1.5h12.5a.75.75 0 0 0 0-1.5z" />
          </svg>
        </button>
        <h1 class="flex min-w-0 items-baseline gap-1 font-semibold">
          <span aria-hidden="true" class="text-muted">
            #
          </span>
          <span class="truncate">{props.channel.name}</span>
        </h1>
        <Show when={props.channel.topic}>
          {(topic) => (
            <p class="hidden min-w-0 flex-1 truncate border-l border-line pl-3 text-sm text-muted md:block">
              {topic()}
            </p>
          )}
        </Show>
        <span class="flex-1 md:hidden" />
        <Show when={!props.channel.topic}>
          <span class="hidden flex-1 md:block" />
        </Show>
        <details class="group/e2e relative shrink-0">
          <summary class="flex cursor-pointer list-none items-center gap-1 rounded-full border border-line px-2.5 py-1 text-xs font-medium text-muted hover:text-ink [&::-webkit-details-marker]:hidden">
            {/* An open lock: a closed one would read as "encrypted". */}
            <svg
              viewBox="0 0 20 20"
              class="size-3.5"
              fill="none"
              stroke="currentColor"
              stroke-width="1.6"
              stroke-linecap="round"
              aria-hidden="true"
            >
              <rect x="4" y="9" width="12" height="8" rx="1.5" />
              <path d="M7 9V6a3 3 0 0 1 5.8-1.1" />
            </svg>
            <span class="hidden sm:inline">Not end-to-end</span>
            <span class="sm:hidden">Not E2E</span>
          </summary>
          <div class="group-pop absolute top-full right-0 z-30 mt-2 w-72 rounded-2xl border border-line bg-paper p-4 text-sm leading-relaxed shadow-xl">
            Group messages are stored readable on Aaru's server so the group
            works on every device, and every member can read them. Nobody
            outside the group can see this channel.
          </div>
        </details>
        <button
          type="button"
          aria-label="Members"
          title="Members"
          aria-pressed={scope.membersOpen()}
          onClick={() => props.onOpenMembers()}
          class={`grid size-9 shrink-0 place-items-center rounded-full text-muted hover:bg-surface hover:text-ink ${scope.membersOpen() ? 'lg:bg-surface lg:text-ink' : ''}`}
        >
          <svg
            viewBox="0 0 20 20"
            class="size-5"
            fill="currentColor"
            aria-hidden="true"
          >
            <path d="M7 9a3 3 0 1 0 0-6 3 3 0 0 0 0 6Zm6.5 0a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5ZM1.6 15.6C2.3 12.9 4.4 11 7 11s4.7 1.9 5.4 4.6a1 1 0 0 1-1 1.4H2.6a1 1 0 0 1-1-1.4Zm12.2 1.4h2.6a1 1 0 0 0 1-1.3c-.6-2.1-2.2-3.7-4.3-3.7-.6 0-1.1.1-1.6.3 1 1 1.8 2.3 2.3 3.8.1.3.1.6 0 .9Z" />
          </svg>
        </button>
      </header>

      <div class="relative min-h-0 flex-1">
        <div
          ref={scroller}
          onScroll={onScroll}
          class="h-full overflow-y-auto overscroll-contain pt-4 pb-2"
          role="log"
          aria-live="polite"
          aria-relevant="additions"
        >
          <Show when={loadingOlder()}>
            <p class="py-2 text-center text-xs text-muted">Loading earlier…</p>
          </Show>
          <Show when={!hasOlder()}>
            <div class="px-4 pt-6 pb-4 md:px-6">
              <span class="grid size-14 place-items-center rounded-full bg-surface font-display text-2xl text-muted">
                #
              </span>
              <h2 class="mt-3 font-display text-3xl font-medium">
                {props.channel.isDefault
                  ? `Welcome to ${scope.detail().group.name}`
                  : `#${props.channel.name}`}
              </h2>
              <p class="mt-1 text-muted">
                This is the start of #{props.channel.name}.
                <Show when={props.channel.topic}> {props.channel.topic}</Show>
              </p>
              <Show when={scope.detail().members.length < 2}>
                <button
                  type="button"
                  onClick={() => scope.openInvite()}
                  class="mt-4 rounded-full bg-accent px-4 py-2 text-sm font-semibold text-on-accent"
                >
                  Invite friends
                </button>
              </Show>
            </div>
          </Show>
          <For each={timeline()}>
            {(item) => (
              <Switch>
                <Match when={item.kind === 'day' && item}>
                  {(day) => (
                    <div
                      role="separator"
                      class="my-3 flex items-center gap-3 px-4 md:px-6"
                    >
                      <span class="h-px flex-1 bg-line" />
                      <span class="text-xs font-semibold text-muted">
                        {dayLabel(day().date)}
                      </span>
                      <span class="h-px flex-1 bg-line" />
                    </div>
                  )}
                </Match>
                <Match when={item.kind === 'new'}>
                  <div
                    data-new-line
                    role="separator"
                    aria-label="New messages"
                    class="relative my-2 flex items-center px-4 md:px-6"
                  >
                    <span class="h-px flex-1 bg-accent" />
                    <span class="ml-2 rounded-full bg-accent px-2 text-[11px] leading-5 font-semibold text-on-accent">
                      New
                    </span>
                  </div>
                </Match>
                <Match when={item.kind === 'message' && item}>
                  {(row) => {
                    const m = () => row().message
                    const mine = () => m().author?.userId === meId()
                    const mentionsMe = () => m().mentions.includes(meId())
                    const hidden = () =>
                      m().fromBlocked && !revealed().has(m().id)
                    return (
                      <article
                        class={`group/msg relative flex gap-3 px-4 md:px-6 ${row().startsRun ? 'mt-3 pt-0.5' : ''} ${mentionsMe() && !m().deleted ? 'border-l-2 border-accent bg-accent/[0.06] pl-[14px] md:pl-[22px]' : 'hover:bg-surface/50'}`}
                      >
                        <div class="w-10 shrink-0">
                          <Show
                            when={row().startsRun}
                            fallback={
                              <time
                                datetime={m().createdAt}
                                class="block pt-1 text-right text-[10px] text-muted opacity-0 group-hover/msg:opacity-100"
                              >
                                {timeLabel(m().createdAt)}
                              </time>
                            }
                          >
                            <Monogram text={authorMonogram(m())} />
                          </Show>
                        </div>
                        <div class="min-w-0 flex-1 pb-0.5">
                          <Header
                            starts={row().startsRun}
                            name={authorName(m())}
                            at={m().createdAt}
                          />
                          <Switch
                            fallback={
                              <>
                                <Body text={m().body} />
                                <Show when={m().editedAt}>
                                  <span class="text-[11px] text-muted">
                                    (edited)
                                  </span>
                                </Show>
                              </>
                            }
                          >
                            <Match when={m().deleted}>
                              <p class="text-sm text-muted italic">
                                Message deleted
                              </p>
                            </Match>
                            <Match when={hidden()}>
                              <p class="text-sm text-muted">
                                Message from someone you blocked ·{' '}
                                <button
                                  type="button"
                                  class="font-medium text-accent hover:underline"
                                  onClick={() =>
                                    setRevealed(
                                      new Set([...revealed(), m().id]),
                                    )
                                  }
                                >
                                  Show
                                </button>
                              </p>
                            </Match>
                            <Match when={editing() === m().id}>
                              <EditBox
                                initial={m().body}
                                onSave={(body) => void saveEdit(m(), body)}
                                onCancel={() => setEditing(null)}
                              />
                            </Match>
                          </Switch>
                          <Show when={confirmDelete() === m().id}>
                            <p class="mt-1 flex items-center gap-3 text-sm">
                              <span class="text-muted">
                                Delete this message?
                              </span>
                              <button
                                type="button"
                                class="font-semibold text-danger"
                                onClick={() => void remove(m())}
                              >
                                Delete
                              </button>
                              <button
                                type="button"
                                class="text-muted hover:text-ink"
                                onClick={() => setConfirmDelete(null)}
                              >
                                Cancel
                              </button>
                            </p>
                          </Show>
                        </div>
                        <Show
                          when={
                            !m().deleted &&
                            editing() !== m().id &&
                            (mine() || manages())
                          }
                        >
                          <div class="absolute -top-3 right-4 flex overflow-hidden rounded-lg border border-line bg-paper text-xs shadow-sm opacity-0 group-hover/msg:opacity-100 focus-within:opacity-100 md:right-6 [@media(hover:none)]:static [@media(hover:none)]:self-start [@media(hover:none)]:opacity-100">
                            <Show when={mine()}>
                              <button
                                type="button"
                                class="px-2.5 py-1 hover:bg-surface"
                                onClick={() => setEditing(m().id)}
                              >
                                Edit
                              </button>
                            </Show>
                            <button
                              type="button"
                              class="px-2.5 py-1 text-danger hover:bg-surface"
                              onClick={() => setConfirmDelete(m().id)}
                            >
                              Delete
                            </button>
                          </div>
                        </Show>
                      </article>
                    )
                  }}
                </Match>
                <Match when={item.kind === 'pending' && item}>
                  {(row) => {
                    const p = () => row().pending
                    return (
                      <article
                        class={`flex gap-3 px-4 md:px-6 ${row().startsRun ? 'mt-3 pt-0.5' : ''}`}
                      >
                        <div class="w-10 shrink-0">
                          <Show when={row().startsRun}>
                            <Monogram
                              text={
                                shell.me().handle
                                  ? monogram({
                                      userId: meId(),
                                      handle: shell.me().handle ?? '?',
                                      displayName: shell.me().displayName,
                                    })
                                  : '·'
                              }
                            />
                          </Show>
                        </div>
                        <div class="min-w-0 flex-1">
                          <Header
                            starts={row().startsRun}
                            name={
                              shell.me().displayName ??
                              `@${shell.me().handle ?? ''}`
                            }
                            at={p().createdAt}
                          />
                          <div
                            class={p().state === 'sending' ? 'opacity-55' : ''}
                          >
                            <Body text={p().body} />
                          </div>
                          <Show when={p().state === 'failed'}>
                            <p class="mt-0.5 flex items-center gap-3 text-xs">
                              <span class="text-danger">Not sent.</span>
                              <button
                                type="button"
                                class="font-semibold text-accent"
                                onClick={() => {
                                  setPending(retryPending(pending(), p().nonce))
                                  void deliver(p())
                                }}
                              >
                                Retry
                              </button>
                              <button
                                type="button"
                                class="text-muted hover:text-ink"
                                onClick={() =>
                                  setPending(
                                    settlePending(pending(), p().nonce),
                                  )
                                }
                              >
                                Discard
                              </button>
                            </p>
                          </Show>
                        </div>
                      </article>
                    )
                  }}
                </Match>
              </Switch>
            )}
          </For>
          <div class="h-2" />
        </div>
        <Show when={!atBottom()}>
          <button
            type="button"
            onClick={() => scrollToBottom(true)}
            class="group-pop absolute bottom-3 left-1/2 -translate-x-1/2 rounded-full bg-ink px-4 py-1.5 text-sm font-medium text-paper shadow-lg"
          >
            {unreadSummary()} ↓
          </button>
        </Show>
      </div>

      <Show when={problem()}>
        {(text) => (
          <p role="alert" class="px-4 pb-1 text-sm text-danger md:px-6">
            {text()}
          </p>
        )}
      </Show>
      <Composer
        channelName={props.channel.name}
        members={scope.detail().members}
        meId={meId()}
        onSend={send}
      />
    </section>
  )
}

function EditBox(props: {
  initial: string
  onSave: (body: string) => void
  onCancel: () => void
}) {
  let box: HTMLTextAreaElement | undefined
  const [text, setText] = createSignal(props.initial)
  onMount(() => {
    if (!box) return
    box.focus()
    box.setSelectionRange(box.value.length, box.value.length)
    box.style.height = `${Math.min(box.scrollHeight, 220)}px`
  })
  return (
    <div class="mt-1">
      <textarea
        ref={box}
        value={text()}
        maxLength={4000}
        aria-label="Edit message"
        onInput={(e) => {
          setText(e.currentTarget.value)
          e.currentTarget.style.height = 'auto'
          e.currentTarget.style.height = `${Math.min(e.currentTarget.scrollHeight, 220)}px`
        }}
        onKeyDown={(e) => {
          if (e.key === 'Escape') {
            e.preventDefault()
            props.onCancel()
          } else if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
            e.preventDefault()
            props.onSave(text())
          }
        }}
        class="w-full resize-none rounded-xl border-0 bg-surface px-3 py-2 text-[15px] leading-6 focus:ring-2 focus:ring-accent"
      />
      <p class="text-xs text-muted">
        Enter to save · Esc to cancel ·{' '}
        <button
          type="button"
          class="font-medium text-accent"
          onClick={() => props.onSave(text())}
        >
          Save
        </button>
      </p>
    </div>
  )
}
