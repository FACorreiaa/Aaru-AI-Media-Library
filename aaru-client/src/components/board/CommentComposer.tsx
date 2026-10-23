import { Show, createSignal } from 'solid-js'
import {
  Button,
  TextField,
  TextFieldLabel,
  TextFieldTextArea,
  toast,
} from '~/components/ui'
import type { BoardComment } from '../../lib/board/model'
import { addComment } from '../../lib/board/server'
import { MAX_MESSAGE_LENGTH, remainingLabel } from '../../lib/groups/model'
import { inviterName, monogram } from '../../lib/social/model'
import type { SocialUser } from '../../lib/social/server'
import { MentionList, createMentions } from '../Mentions'
import { Monogram } from '../groups/Monogram'

/** The comment a reply answers: always a top-level one, since threads are one level deep. */
export type ReplyTarget = { id: string; author?: SocialUser }

/**
 * CommentComposer (BOARD-002): the reply box under a post's thread. One line that grows to
 * 160px; `@` suggests the post's author and your friends, never Aaru (BOARD-004). Replying
 * names who above the box with a ✕ to drop it; Escape drops it too. ⌘/Ctrl+Enter sends.
 */
export function CommentComposer(props: {
  postId: string
  me: SocialUser
  /** Who `@` suggests: the post's author and your friends. */
  people: SocialUser[]
  replyTo: ReplyTarget | null
  onCancelReply: () => void
  onPosted: (comment: BoardComment) => void
  /** The box, so the page can focus it after Reply. */
  ref?: (box: HTMLTextAreaElement) => void
}) {
  let box: HTMLTextAreaElement | undefined
  const [text, setText] = createSignal('')
  const [sending, setSending] = createSignal(false)
  const mentions = createMentions({
    people: () => props.people.map((user) => ({ user })),
    meId: () => props.me.userId,
    id: 'comment-composer-mentions',
    box: () => box,
    text,
    onPick: (value) => {
      setText(value)
      resize()
    },
  })

  const remaining = () => remainingLabel(text())
  const tooLong = () => text().length > MAX_MESSAGE_LENGTH
  const canSend = () => text().trim().length > 0 && !tooLong() && !sending()
  const replyName = () => {
    const author = props.replyTo?.author
    return author ? `@${author.handle}` : 'a deleted comment'
  }

  function resize() {
    if (!box) return
    box.style.height = 'auto'
    box.style.height = `${Math.min(box.scrollHeight, 160)}px`
  }

  async function send() {
    if (!canSend()) return
    setSending(true)
    try {
      const created = await addComment({
        data: {
          postId: props.postId,
          body: text().trim(),
          replyTo: props.replyTo?.id,
        },
      })
      setText('')
      if (box) box.value = ''
      mentions.close()
      resize()
      props.onPosted(created)
    } catch (error) {
      toast(
        error instanceof Error ? error.message : 'Your comment was not posted.',
      )
    } finally {
      setSending(false)
    }
  }

  return (
    <section
      aria-label="Write a comment"
      class={`rounded-card bg-surface px-3 py-3 sm:px-4 ${tooLong() ? 'ring-2 ring-danger' : 'focus-within:ring-2 focus-within:ring-accent/60'}`}
    >
      <Show when={props.replyTo}>
        <p class="mb-2 ml-11 flex items-center gap-1 text-xs text-muted">
          <span>
            Replying to{' '}
            <span class="font-semibold text-ink">{replyName()}</span>
          </span>
          <Button
            variant="ghost"
            size="icon-sm"
            class="size-6 rounded-full text-muted hover:text-ink"
            aria-label="Stop replying"
            onClick={() => {
              props.onCancelReply()
              box?.focus()
            }}
          >
            <span aria-hidden="true">✕</span>
          </Button>
        </p>
      </Show>
      <div class="flex gap-3">
        <Monogram text={monogram(props.me)} size="sm" class="mt-0.5" />
        <div class="min-w-0 flex-1">
          <TextField value={text()} onChange={setText} class="relative flex">
            <TextFieldLabel class="sr-only">
              {props.replyTo ? `Reply to ${replyName()}` : 'Write a comment'}
            </TextFieldLabel>
            <TextFieldTextArea
              ref={(el: HTMLTextAreaElement) => {
                box = el
                props.ref?.(el)
              }}
              rows={1}
              placeholder={
                props.replyTo?.author
                  ? `Reply to ${inviterName(props.replyTo.author)}…`
                  : 'Add a comment…'
              }
              role="combobox"
              aria-autocomplete="list"
              aria-expanded={mentions.expanded()}
              aria-controls={mentions.id}
              aria-activedescendant={mentions.activeId()}
              onInput={(e) => {
                setText(e.currentTarget.value)
                mentions.track(
                  e.currentTarget.value,
                  e.currentTarget.selectionStart,
                )
                resize()
              }}
              onClick={() => mentions.sync()}
              onBlur={() => mentions.close()}
              onKeyDown={(e: KeyboardEvent) => {
                if (mentions.onKeyDown(e)) return
                if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
                  e.preventDefault()
                  void send()
                } else if (e.key === 'Escape' && props.replyTo) {
                  e.preventDefault()
                  props.onCancelReply()
                }
              }}
              class="max-h-[160px] min-h-8 flex-1 resize-none rounded-none border-0 bg-transparent px-0 py-1 text-base leading-6 placeholder:text-muted focus-visible:ring-0 md:text-base"
            />
            {/* Over the box: it sits at the foot of the thread. */}
            <MentionList
              mentions={mentions}
              class="right-0 bottom-full left-0 z-20 mb-2 slide-in-from-bottom-1"
            />
          </TextField>
          <div class="mt-2 flex items-center justify-end gap-3">
            <Show when={remaining()}>
              {(left) => (
                <span
                  class={`mr-auto text-xs tabular-nums ${tooLong() ? 'text-danger' : 'text-muted'}`}
                  aria-live="polite"
                >
                  {left()}
                </span>
              )}
            </Show>
            <Button
              variant="ink"
              size="sm"
              disabled={!canSend()}
              onClick={() => void send()}
            >
              {sending() ? 'Posting…' : props.replyTo ? 'Reply' : 'Comment'}
            </Button>
          </div>
        </div>
      </div>
    </section>
  )
}
