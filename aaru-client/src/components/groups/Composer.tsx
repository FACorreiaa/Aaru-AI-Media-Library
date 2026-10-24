import { Show, createSignal } from 'solid-js'
import type { JSX } from 'solid-js'
import {
  Button,
  TextField,
  TextFieldLabel,
  TextFieldTextArea,
} from '~/components/ui'
import { MAX_MESSAGE_LENGTH, remainingLabel } from '../../lib/groups/model'
import type { GroupMember } from '../../lib/groups/server'
import { MentionList, createMentions } from '../Mentions'
import { AaruAvatar, AssistantTag } from './AgentParts'

/**
 * The channel's composer: one box that grows, Enter sends and Shift+Enter adds a line, `@`
 * suggests members, with Aaru first, wearing the medallion, when it answers in this group. The
 * suggestions are the box's own listbox (a combobox): focus never leaves the box, so neither a
 * Popover nor a Command fits. Its entrance is CSS, off under reduced motion.
 */
export function Composer(props: {
  channelName: string
  members: GroupMember[]
  /** Whether @aaru answers in this group (GroupDetail.agent). */
  agent: boolean
  meId: string
  onSend: (body: string) => void
  /** Called as the user types; the socket throttles what it sends. */
  onTyping?: () => void
  /** A control above the box, such as a title channel's spoiler marker. */
  accessory?: JSX.Element
}) {
  let box: HTMLTextAreaElement | undefined
  const [text, setText] = createSignal('')
  const mentions = createMentions({
    people: () => props.members,
    meId: () => props.meId,
    agent: () => props.agent,
    id: 'group-composer-mentions',
    box: () => box,
    text,
    onPick: (value) => {
      setText(value)
      resize()
    },
  })

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
    mentions.track(value, caret)
    resize()
  }

  function send() {
    if (!canSend()) return
    props.onSend(text().trim())
    setText('')
    mentions.close()
    if (box) box.value = ''
    resize()
  }

  function onKeyDown(event: KeyboardEvent) {
    if (mentions.onKeyDown(event)) return
    if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
      event.preventDefault()
      send()
    }
  }

  return (
    <div class="relative px-3 pt-1 pb-3 md:px-4 md:pb-4">
      <MentionList
        mentions={mentions}
        class="right-3 bottom-full left-3 mb-1 slide-in-from-bottom-1 md:right-4 md:left-4"
        agentRow={() => (
          <>
            <AaruAvatar size="sm" />
            <span class="font-medium">Aaru</span>
            <span class="text-muted">@aaru</span>
            <AssistantTag />
          </>
        )}
      />
      <Show when={props.accessory}>
        <div class="mb-1.5 flex">{props.accessory}</div>
      </Show>
      <div
        class={`flex items-end gap-2 rounded-2xl bg-surface px-3 py-2 focus-within:ring-2 ${tooLong() ? 'ring-2 ring-danger' : 'focus-within:ring-accent'}`}
      >
        <TextField
          value={text()}
          onChange={setText}
          class="flex min-w-0 flex-1"
        >
          <TextFieldLabel class="sr-only">
            Write in #{props.channelName}
          </TextFieldLabel>
          <TextFieldTextArea
            id="group-composer"
            ref={box}
            rows={1}
            placeholder={`Write in #${props.channelName}`}
            role="combobox"
            aria-autocomplete="list"
            aria-expanded={mentions.expanded()}
            aria-controls={mentions.id}
            aria-activedescendant={mentions.activeId()}
            onInput={(e) => {
              update(e.currentTarget.value, e.currentTarget.selectionStart)
              if (e.currentTarget.value.trim()) props.onTyping?.()
            }}
            onClick={() => mentions.sync()}
            onKeyDown={onKeyDown}
            onBlur={() => mentions.close()}
            class="max-h-[220px] min-h-7 flex-1 resize-none rounded-none border-0 bg-transparent px-0 py-1 text-base leading-6 placeholder:text-muted focus-visible:ring-0 md:text-base"
          />
        </TextField>
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
        <Button
          size="icon-sm"
          onClick={send}
          disabled={!canSend()}
          aria-label="Send"
          class="shrink-0 disabled:opacity-30"
        >
          <svg
            viewBox="0 0 20 20"
            class="size-4"
            fill="currentColor"
            aria-hidden="true"
          >
            <path d="M3.1 2.6a.75.75 0 0 1 .82-.1l13 6.75a.75.75 0 0 1 0 1.33l-13 6.75A.75.75 0 0 1 2.86 16.5L4.6 10 2.86 3.5a.75.75 0 0 1 .24-.9ZM6 10.75 4.8 15.1 14.9 10 4.8 4.9 6 9.25h4.25a.75.75 0 0 1 0 1.5z" />
          </svg>
        </Button>
      </div>
    </div>
  )
}
