import { Show, createEffect, createSignal, on } from 'solid-js'
import {
  Button,
  TextField,
  TextFieldLabel,
  TextFieldTextArea,
  toast,
} from '~/components/ui'
import { prefillReply } from '../../lib/board/model'
import type { BoardComment, ReplyTarget } from '../../lib/board/model'
import { addComment } from '../../lib/board/server'
import { MAX_MESSAGE_LENGTH, remainingLabel } from '../../lib/groups/model'
import { inviterName, monogram } from '../../lib/social/model'
import type { SocialUser } from '../../lib/social/server'
import { MentionList, createMentions } from '../Mentions'
import { Monogram } from '../groups/Monogram'

/**
 * CommentComposer (BOARD-002): the reply box under a post's thread. One line that grows to
 * 160px; `@` suggests the post's author and your friends, never Aaru (BOARD-004). Replying
 * names who above the box with a ✕ to drop it; Escape drops it too. Replying to a reply starts
 * the box with `@who `, so they are tagged though the reply hangs off the top-level comment.
 * ⌘/Ctrl+Enter sends; after a send, focus stays in the box for the next one.
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
    return author ? `@${author.handle}` : 'Aaru'
  }

  // A new reply target swaps its `@who ` in (or out), keeping anything typed after it.
  createEffect(
    on(
      () => props.replyTo,
      (next, prev) => {
        const value = prefillReply(
          text(),
          prev?.prefill ?? '',
          next?.prefill ?? '',
        )
        if (value === text()) return
        setText(value)
        if (!box) return
        box.value = value
        box.setSelectionRange(value.length, value.length)
        resize()
      },
      { defer: true },
    ),
  )

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
      // Whatever sent it: a clicked Comment button goes disabled, and focus would fall to the page.
      box?.focus({ preventScroll: true })
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
