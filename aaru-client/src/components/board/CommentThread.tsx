import { Link } from '@tanstack/solid-router'
import { For, Show, createMemo, createSignal, onMount } from 'solid-js'
import { Button, buttonVariants, toast } from '~/components/ui'
import {
  dropComment,
  mergeComments,
  replyTarget,
  shouldLoadMore,
  threadComments,
} from '../../lib/board/model'
import type { BoardComment, ReplyTarget, Thread } from '../../lib/board/model'
import { deleteComment, loadComments } from '../../lib/board/server'
import type { BoardCommentPage } from '../../lib/board/server'
import { splitMentions } from '../../lib/groups/model'
import { leave, play } from '../../lib/motion'
import { inviterName, monogram } from '../../lib/social/model'
import type { SocialUser } from '../../lib/social/server'
import { ConfirmDialog } from '../ConfirmDialog'
import { Monogram } from '../groups/Monogram'
import { Menu, MenuItem } from '../groups/shell'
import { CommentComposer } from './CommentComposer'
import { postedLabel } from './PostCard'

/** Empty pages followed in a row before the thread stops and offers the button again. */
const MAX_SKIPS = 5

/**
 * CommentThread (BOARD-002): a post's comments, oldest first, one level of replies hung under
 * the comment they answer on a thin spine. A deleted comment that still has replies stays as a
 * muted "Comment deleted" with no author. Reply answers the top-level comment; Delete is yours,
 * or anyone's on your post. More comes by "Show more comments", never by scrolling, and an
 * empty page with more behind it is followed at once, so "No comments yet" only shows at the end.
 */
export function CommentThread(props: {
  postId: string
  /** The post is yours: you may delete any comment on it. */
  postMine: boolean
  initial: BoardCommentPage
  me: SocialUser
  /** Who `@` suggests in the reply box: the post's author and your friends. */
  people: SocialUser[]
  /** Handles that read as mentions, lowercased. */
  handles: ReadonlySet<string>
  commentCount: number
  /** A comment was added (+1) or deleted (-1). */
  onCount: (delta: 1 | -1) => void
}) {
  let heading: HTMLHeadingElement | undefined
  let box: HTMLTextAreaElement | undefined
  let list: HTMLOListElement | undefined
  const [comments, setComments] = createSignal<BoardComment[]>(
    props.initial.items,
  )
  const [next, setNext] = createSignal(props.initial.next ?? null)
  const [loading, setLoading] = createSignal(false)
  const [replyTo, setReplyTo] = createSignal<ReplyTarget | null>(null)
  const [pending, setPending] = createSignal<BoardComment | null>(null)
  const [deleting, setDeleting] = createSignal(false)
  // Set when a delete went through, so the closing dialog leaves focus to `confirmDelete`.
  let landing = false

  const threads = createMemo(() => threadComments(comments()))
  // Rows are keyed by the top-level comment's id, so a new reply or a later page keeps every
  // thread's element (and its focus) instead of redrawing the list.
  const byRoot = createMemo(
    () => new Map(threads().map((t) => [t.comment.id, t])),
  )
  const rootIds = createMemo(() => threads().map((t) => t.comment.id))
  const handles = createMemo(() => {
    const all = new Set(props.handles)
    for (const c of comments())
      if (c.author) all.add(c.author.handle.toLowerCase())
    return all
  })

  const element = (id: string) =>
    list?.querySelector<HTMLElement>(`[data-comment="${id}"]`) ?? null

  /** Follows `next` once on a tap, then on through empty pages, so a tap always shows more. */
  async function more() {
    if (loading()) return
    setLoading(true)
    try {
      for (let skips = 0; skips < MAX_SKIPS; skips++) {
        const after = next()
        if (!after) break
        const page = await loadComments({
          data: { postId: props.postId, after },
        })
        setComments(mergeComments(comments(), page.items))
        setNext(shouldLoadMore(page) ? (page.next ?? null) : null)
        if (page.items.length > 0) break
      }
    } catch (error) {
      toast(
        error instanceof Error
          ? error.message
          : 'The comments could not be loaded.',
      )
    } finally {
      setLoading(false)
    }
  }

  // A first page the server emptied (deleted or blocked rows) with more behind it.
  onMount(() => {
    if (props.initial.items.length === 0 && next()) void more()
  })

  function reply(comment: BoardComment) {
    setReplyTo(replyTarget(comment))
    box?.focus()
    box?.scrollIntoView({ block: 'nearest' })
  }

  function posted(comment: BoardComment) {
    setComments(mergeComments(comments(), [comment]))
    setReplyTo(null)
    props.onCount(1)
    const el = element(comment.id)
    if (el) {
      el.scrollIntoView({ block: 'nearest' })
      void play(el, {
        opacity: [0, 1],
        transform: ['translateY(6px)', 'translateY(0)'],
      })
    }
  }

  async function confirmDelete() {
    const target = pending()
    if (!target || deleting()) return
    setDeleting(true)
    try {
      await deleteComment({
        data: { postId: props.postId, commentId: target.id },
      })
      const stays = dropComment(comments(), target.id).some(
        (c) => c.id === target.id,
      )
      const el = element(target.id)
      // The dialog closes now; this places focus, not the dialog (its opener may be gone).
      landing = true
      setPending(null)
      if (!stays && el) await leave(el)
      // From the comments as they are now: a page may have landed during the exit.
      setComments(dropComment(comments(), target.id))
      if (replyTo()?.id === target.id && !stays) setReplyTo(null)
      props.onCount(-1)
      // Focus lands where the comment was: its blank row, its parent, or the heading.
      const land =
        (stays && element(target.id)) ||
        (target.replyTo && element(target.replyTo)) ||
        heading
      land?.focus()
    } catch (error) {
      toast(
        error instanceof Error
          ? error.message
          : 'That comment was not deleted.',
      )
    } finally {
      setDeleting(false)
    }
  }

  return (
    <section id="comments" aria-labelledby="comments-heading" class="mt-8">
      <h2
        ref={heading}
        id="comments-heading"
        tabindex="-1"
        class="flex items-baseline gap-2 font-display text-xl font-medium outline-none"
      >
        Comments
        <Show when={props.commentCount > 0}>
          <span class="font-sans text-sm font-normal text-muted tabular-nums">
            {props.commentCount}
          </span>
        </Show>
      </h2>

      <Show when={threads().length === 0 && !next()}>
        <p class="mt-3 text-sm text-muted">No comments yet. Start one below.</p>
      </Show>

      <ol ref={list} aria-label="Comments" class="mt-2">
        <For each={rootIds()}>
          {(id) => (
            <Show when={byRoot().get(id)}>
              {(thread) => (
                <ThreadRow
                  thread={thread()}
                  postMine={props.postMine}
                  handles={handles()}
                  myHandle={props.me.handle.toLowerCase()}
                  onReply={reply}
                  onDelete={setPending}
                />
              )}
            </Show>
          )}
        </For>
      </ol>

      <Show when={next()}>
        <Button
          variant="quiet"
          size="sm"
          class="mt-2"
          disabled={loading()}
          aria-busy={loading()}
          onClick={() => void more()}
        >
          {loading() ? 'Loading…' : 'Show more comments'}
        </Button>
      </Show>

      <div class="mt-6">
        <CommentComposer
          postId={props.postId}
          me={props.me}
          people={props.people}
          replyTo={replyTo()}
          onCancelReply={() => setReplyTo(null)}
          onPosted={posted}
          ref={(el) => (box = el)}
        />
      </div>

      <ConfirmDialog
        open={pending() !== null}
        title="Delete this comment?"
        description={
          (byRoot().get(pending()?.id ?? '')?.replies.length ?? 0) > 0
            ? 'Replies to it stay, under “Comment deleted”.'
            : undefined
        }
        confirmLabel={deleting() ? 'Deleting…' : 'Delete comment'}
        busy={deleting()}
        onConfirm={() => void confirmDelete()}
        onCancel={() => {
          if (!deleting()) setPending(null)
        }}
        onCloseAutoFocus={(event) => {
          if (!landing) return
          landing = false
          event.preventDefault()
        }}
      />
    </section>
  )
}

/** One top-level comment and the replies under it. */
function ThreadRow(props: {
  thread: Thread
  postMine: boolean
  handles: ReadonlySet<string>
  myHandle: string
  onReply: (comment: BoardComment) => void
  onDelete: (comment: BoardComment) => void
}) {
  return (
    <li class="border-b border-line/60 py-4 last:border-b-0">
      <CommentRow {...props} comment={props.thread.comment} />
      <Show when={props.thread.replies.length > 0}>
        {/* The spine: a hairline from under the parent's monogram, replies hung off it. */}
        <ol
          aria-label={`Replies to ${commentAuthor(props.thread.comment)}`}
          class="mt-3 ml-4 space-y-4 border-l border-line pl-5"
        >
          <For each={props.thread.replies}>
            {(comment) => (
              <li>
                <CommentRow {...props} comment={comment} />
              </li>
            )}
          </For>
        </ol>
      </Show>
    </li>
  )
}

function commentAuthor(comment: BoardComment): string {
  if (comment.deleted) return 'a deleted comment'
  if (comment.mine) return 'you'
  if (comment.author) return inviterName(comment.author)
  return comment.fromAgent ? 'Aaru' : 'someone'
}

function CommentRow(props: {
  comment: BoardComment
  postMine: boolean
  handles: ReadonlySet<string>
  myHandle: string
  onReply: (comment: BoardComment) => void
  onDelete: (comment: BoardComment) => void
}) {
  const canDelete = () => props.comment.mine === true || props.postMine
  const name = () =>
    props.comment.mine
      ? 'You'
      : props.comment.author
        ? inviterName(props.comment.author)
        : 'Aaru'
  const segments = () =>
    splitMentions(props.comment.body, props.handles, props.myHandle)

  return (
    <Show
      when={!props.comment.deleted}
      fallback={
        <article
          data-comment={props.comment.id}
          tabindex="-1"
          aria-label="Comment deleted"
          class="flex items-center gap-3 outline-none"
        >
          {/* No author: an empty ring where the monogram was. */}
          <span
            aria-hidden="true"
            class="size-8 shrink-0 rounded-full border border-dashed border-line"
          />
          <p class="text-sm text-muted italic">Comment deleted</p>
        </article>
      }
    >
      <article
        data-comment={props.comment.id}
        tabindex="-1"
        aria-label={`Comment by ${commentAuthor(props.comment)}`}
        class="flex gap-3 outline-none"
      >
        <Show
          when={props.comment.author}
          fallback={<Monogram text="A" size="sm" />}
        >
          {(author) => (
            <Show
              when={!props.comment.mine}
              fallback={
                <span class="shrink-0 self-start">
                  <Monogram
                    text={monogram(author())}
                    avatarUrl={author().avatarUrl}
                    size="sm"
                  />
                </span>
              }
            >
              <Link
                to="/app/friends/$handle"
                params={{ handle: author().handle }}
                aria-label={inviterName(author())}
                class="shrink-0 self-start rounded-full"
              >
                <Monogram
                  text={monogram(author())}
                  avatarUrl={author().avatarUrl}
                  size="sm"
                />
              </Link>
            </Show>
          )}
        </Show>
        <div class="min-w-0 flex-1">
          <p class="flex flex-wrap items-baseline gap-x-2 text-sm leading-tight">
            <span class="font-semibold">{name()}</span>
            <Show when={props.comment.author && !props.comment.mine}>
              <Show when={props.comment.author!.displayName}>
                <span class="text-muted">@{props.comment.author!.handle}</span>
              </Show>
            </Show>
            <time
              datetime={props.comment.createdAt}
              title={new Date(props.comment.createdAt).toLocaleString()}
              class="text-xs text-muted tabular-nums"
            >
              {postedLabel(props.comment.createdAt)}
            </time>
          </p>
          <p class="mt-1 text-md leading-relaxed break-words whitespace-pre-wrap">
            <For each={segments()}>
              {(segment) =>
                segment.kind === 'text' || segment.handle === 'aaru' ? (
                  segment.text
                ) : (
                  <span
                    class={`rounded px-0.5 font-medium text-accent ${segment.me ? 'bg-accent/20' : 'bg-accent/10'}`}
                  >
                    {segment.text}
                  </span>
                )
              }
            </For>
          </p>
          <div class="mt-1 -ml-2 flex items-center gap-1">
            <Button
              variant="ghost"
              size="bare"
              class="min-h-8 rounded-full px-2 text-xs font-semibold text-muted hover:text-ink"
              onClick={() => props.onReply(props.comment)}
            >
              Reply
              <span class="sr-only"> to {commentAuthor(props.comment)}</span>
            </Button>
            <Show when={canDelete()}>
              <Menu
                label={`More for the comment by ${commentAuthor(props.comment)}`}
                trigger={<span aria-hidden="true">⋯</span>}
                triggerClass={`${buttonVariants({ variant: 'ghost', size: 'icon-sm' })} size-8 rounded-full text-muted hover:text-ink`}
                placement="bottom-start"
              >
                <MenuItem danger onSelect={() => props.onDelete(props.comment)}>
                  Delete comment
                </MenuItem>
              </Menu>
            </Show>
          </div>
        </div>
      </article>
    </Show>
  )
}
