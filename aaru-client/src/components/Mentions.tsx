import { For, Show, createSignal } from 'solid-js'
import type { JSX } from 'solid-js'
import { suggestMentions, suggestionHandle } from '../lib/groups/agent'
import type { MentionSuggestion } from '../lib/groups/agent'
import { applyMention, mentionQuery } from '../lib/groups/model'
import type { MentionPerson } from '../lib/groups/model'
import { monogram } from '../lib/social/model'
import { Monogram } from './groups/Monogram'

/**
 * `@` suggestions for a text box (GRP-005, shared with the Board since BOARD-002): the box's own
 * listbox, a combobox, so focus never leaves the box and neither a Popover nor a Command fits.
 * The caller owns the box and its text; this tracks the `@` word at the caret, the highlighted
 * suggestion, the arrow / Enter / Tab / Escape keys, and writes the picked handle in.
 */
export function createMentions(options: {
  /** Who can be tagged. */
  people: () => MentionPerson[]
  meId: () => string
  /** Offers @aaru first when true. The Board never does (BOARD-004). */
  agent?: () => boolean
  /** The listbox's id, for the box's `aria-controls`; options are `${id}-${index}`. The box
   *  itself carries `role="combobox"` and `aria-autocomplete="list"`. */
  id: string
  box: () => HTMLTextAreaElement | undefined
  text: () => string
  /** The text after a pick, before the caret moves and focus returns. */
  onPick: (text: string) => void
}) {
  const [query, setQuery] = createSignal<{
    start: number
    query: string
  } | null>(null)
  const [highlight, setHighlight] = createSignal(0)

  const suggestions = (): MentionSuggestion[] => {
    const q = query()
    return q
      ? suggestMentions(
          options.people(),
          q.query,
          options.meId(),
          options.agent?.() ?? false,
        )
      : []
  }

  /** After typing: where the `@` word is, with the first suggestion highlighted. */
  function track(value: string, caret: number) {
    setQuery(mentionQuery(value, caret))
    setHighlight(0)
  }

  /** After a click moved the caret. */
  function sync() {
    const box = options.box()
    if (box) setQuery(mentionQuery(box.value, box.selectionStart))
  }

  function close() {
    setQuery(null)
  }

  function pick(suggestion: MentionSuggestion) {
    const q = query()
    const box = options.box()
    if (!q || !box) return
    const next = applyMention(
      options.text(),
      q.start,
      box.selectionStart,
      suggestionHandle(suggestion),
    )
    setQuery(null)
    box.value = next.text
    options.onPick(next.text)
    box.setSelectionRange(next.caret, next.caret)
    box.focus()
  }

  /** Handles the key when suggestions are open; true when it did, so the box does nothing. */
  function onKeyDown(event: KeyboardEvent): boolean {
    const list = suggestions()
    if (list.length === 0) return false
    if (event.key === 'ArrowDown') {
      event.preventDefault()
      setHighlight((highlight() + 1) % list.length)
      return true
    }
    if (event.key === 'ArrowUp') {
      event.preventDefault()
      setHighlight((highlight() - 1 + list.length) % list.length)
      return true
    }
    if (event.key === 'Enter' || event.key === 'Tab') {
      event.preventDefault()
      pick(list[highlight()])
      return true
    }
    if (event.key === 'Escape') {
      event.preventDefault()
      setQuery(null)
      return true
    }
    return false
  }

  /** For the box's `aria-expanded`: whether the list is open. */
  const expanded = () => suggestions().length > 0
  /** For the box's `aria-activedescendant`. */
  const activeId = () =>
    expanded() ? `${options.id}-${highlight()}` : undefined

  return {
    id: options.id,
    suggestions,
    highlight,
    setHighlight,
    track,
    sync,
    close,
    pick,
    onKeyDown,
    expanded,
    activeId,
  }
}

export type Mentions = ReturnType<typeof createMentions>

/**
 * The suggestion list under or over the box. `class` places it; `agentRow` draws Aaru's row
 * (groups only), so the Board never loads the owl's parts.
 */
export function MentionList(props: {
  mentions: Mentions
  class: string
  agentRow?: () => JSX.Element
}) {
  return (
    <Show when={props.mentions.suggestions().length > 0}>
      <ul
        id={props.mentions.id}
        role="listbox"
        aria-label="Who to tag"
        class={`absolute animate-in overflow-hidden rounded-2xl border border-line bg-paper py-1 shadow-xl duration-150 fade-in-0 ${props.class}`}
      >
        <For each={props.mentions.suggestions()}>
          {(suggestion, index) => (
            <li
              id={`${props.mentions.id}-${index()}`}
              role="option"
              aria-selected={index() === props.mentions.highlight()}
              onPointerDown={(e) => {
                e.preventDefault()
                props.mentions.pick(suggestion)
              }}
              onPointerEnter={() => props.mentions.setHighlight(index())}
              class={`flex cursor-pointer items-center gap-3 px-3 py-2 text-sm ${index() === props.mentions.highlight() ? 'bg-surface' : ''}`}
            >
              <Show
                when={suggestion.kind === 'member' && suggestion.member}
                fallback={props.agentRow?.()}
              >
                {(member) => (
                  <>
                    <Monogram text={monogram(member().user)} size="sm" />
                    <span class="font-medium">
                      {member().user.displayName ?? `@${member().user.handle}`}
                    </span>
                    <Show when={member().user.displayName}>
                      <span class="text-muted">@{member().user.handle}</span>
                    </Show>
                  </>
                )}
              </Show>
            </li>
          )}
        </For>
      </ul>
    </Show>
  )
}
