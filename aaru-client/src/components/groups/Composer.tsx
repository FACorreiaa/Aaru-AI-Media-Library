import { For, Show, createSignal } from 'solid-js'
import {
  MAX_MESSAGE_LENGTH,
  applyMention,
  matchMembers,
  mentionQuery,
  remainingLabel,
} from '../../lib/groups/model'
import type { GroupMember } from '../../lib/groups/server'
import { monogram } from '../../lib/social/model'
import { Monogram } from './shell'

/**
 * The channel's composer: one box that grows, Enter sends and Shift+Enter adds a line, `@`
 * suggests members. Aaru joins the suggestions with M5; typing `@aaru` by hand already tags it.
 */
export function Composer(props: {
  channelName: string
  members: GroupMember[]
  meId: string
  onSend: (body: string) => void
}) {
  let box: HTMLTextAreaElement | undefined
  const [text, setText] = createSignal('')
  const [query, setQuery] = createSignal<{
    start: number
    query: string
  } | null>(null)
  const [highlight, setHighlight] = createSignal(0)

  const suggestions = () => {
    const q = query()
    return q ? matchMembers(props.members, q.query, props.meId) : []
  }
  const remaining = () => remainingLabel(text())
  const tooLong = () => text().length > MAX_MESSAGE_LENGTH
  const canSend = () => text().trim().length > 0 && !tooLong()

  function resize() {
    if (!box) return
    box.style.height = 'auto'
    box.style.height = `${Math.min(box.scrollHeight, 220)}px`
  }

  function update(value: string, caret: number) {
    setText(value)
    setQuery(mentionQuery(value, caret))
    setHighlight(0)
    resize()
  }

  function pick(member: GroupMember) {
    const q = query()
    if (!q || !box) return
    const next = applyMention(
      text(),
      q.start,
      box.selectionStart,
      member.user.handle,
    )
    setText(next.text)
    setQuery(null)
    box.value = next.text
    box.setSelectionRange(next.caret, next.caret)
    box.focus()
    resize()
  }

  function send() {
    if (!canSend()) return
    props.onSend(text().trim())
    setText('')
    setQuery(null)
    if (box) box.value = ''
    resize()
  }

  function onKeyDown(event: KeyboardEvent) {
    const list = suggestions()
    if (list.length > 0) {
      if (event.key === 'ArrowDown') {
        event.preventDefault()
        setHighlight((highlight() + 1) % list.length)
        return
      }
      if (event.key === 'ArrowUp') {
        event.preventDefault()
        setHighlight((highlight() - 1 + list.length) % list.length)
        return
      }
      if (event.key === 'Enter' || event.key === 'Tab') {
        event.preventDefault()
        pick(list[highlight()])
        return
      }
      if (event.key === 'Escape') {
        event.preventDefault()
        setQuery(null)
        return
      }
    }
    if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
      event.preventDefault()
      send()
    }
  }

  return (
    <div class="relative px-3 pt-1 pb-3 md:px-4 md:pb-4">
      <Show when={suggestions().length > 0}>
        <ul
          role="listbox"
          aria-label="Members to tag"
          class="group-pop absolute right-3 bottom-full left-3 mb-1 overflow-hidden rounded-2xl border border-line bg-paper py-1 shadow-xl md:right-4 md:left-4"
        >
          <For each={suggestions()}>
            {(member, index) => (
              <li
                role="option"
                aria-selected={index() === highlight()}
                onPointerDown={(e) => {
                  e.preventDefault()
                  pick(member)
                }}
                onPointerEnter={() => setHighlight(index())}
                class={`flex cursor-pointer items-center gap-3 px-3 py-2 text-sm ${index() === highlight() ? 'bg-surface' : ''}`}
              >
                <Monogram text={monogram(member.user)} size="sm" />
                <span class="font-medium">
                  {member.user.displayName ?? `@${member.user.handle}`}
                </span>
                <Show when={member.user.displayName}>
                  <span class="text-muted">@{member.user.handle}</span>
                </Show>
              </li>
            )}
          </For>
        </ul>
      </Show>
      <div
        class={`flex items-end gap-2 rounded-2xl bg-surface px-3 py-2 focus-within:ring-2 ${tooLong() ? 'ring-2 ring-danger' : 'focus-within:ring-accent'}`}
      >
        <label for="group-composer" class="sr-only">
          Message #{props.channelName}
        </label>
        <textarea
          id="group-composer"
          ref={box}
          rows={1}
          value={text()}
          placeholder={`Message #${props.channelName}`}
          onInput={(e) =>
            update(e.currentTarget.value, e.currentTarget.selectionStart)
          }
          onClick={(e) =>
            setQuery(
              mentionQuery(
                e.currentTarget.value,
                e.currentTarget.selectionStart,
              ),
            )
          }
          onKeyDown={onKeyDown}
          onBlur={() => setQuery(null)}
          class="max-h-[220px] min-h-7 flex-1 resize-none border-0 bg-transparent py-1 text-base leading-6 placeholder:text-muted focus:ring-0 focus:outline-none"
        />
        <Show when={remaining()}>
          {(left) => (
            <span
              class={`pb-1.5 text-xs tabular-nums ${tooLong() ? 'text-danger' : 'text-muted'}`}
              aria-live="polite"
            >
              {left()}
            </span>
          )}
        </Show>
        <button
          type="button"
          onClick={send}
          disabled={!canSend()}
          aria-label="Send"
          class="grid size-8 shrink-0 place-items-center rounded-full bg-accent text-on-accent transition-opacity disabled:opacity-30"
        >
          <svg
            viewBox="0 0 20 20"
            class="size-4"
            fill="currentColor"
            aria-hidden="true"
          >
            <path d="M3.1 2.6a.75.75 0 0 1 .82-.1l13 6.75a.75.75 0 0 1 0 1.33l-13 6.75A.75.75 0 0 1 2.86 16.5L4.6 10 2.86 3.5a.75.75 0 0 1 .24-.9ZM6 10.75 4.8 15.1 14.9 10 4.8 4.9 6 9.25h4.25a.75.75 0 0 1 0 1.5z" />
          </svg>
        </button>
      </div>
    </div>
  )
}
