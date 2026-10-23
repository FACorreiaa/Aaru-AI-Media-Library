import { Link } from '@tanstack/solid-router'
import { For, Show, createSignal } from 'solid-js'
import { ratingWords, spoilerLabel, starsLabel } from '../../lib/board/model'
import type { BoardPost } from '../../lib/board/model'
import { splitMentions, timeLabel } from '../../lib/groups/model'
import { kindOf } from '../../lib/library/model'
import { activityDay, inviterName, monogram } from '../../lib/social/model'
import { AddToLibrary } from '../AddToLibrary'
import { Poster } from '../Poster'
import { SpoilerVeil } from '../groups/SpoilerVeil'
import { Monogram } from '../groups/Monogram'
import { UpvoteButton } from './UpvoteButton'

/** "14:05" today, then "Yesterday", then "Wed 21 Oct": Lately's days, with today's time. */
function postedLabel(iso: string): string {
  const day = activityDay(iso.slice(0, 10))
  return day === 'Today' ? timeLabel(iso) : day
}

/** Where a post's comments live (Task 4's route, `/app/friends/posts/$postId`). */
export function postHref(id: string): string {
  return `/app/friends/posts/${id}`
}

/**
 * PostCard (BOARD-002): one post on the Board. Who and when, the title it is about with its
 * stars and "Add to my library", the words, then Upvote and the comment count. The card is not
 * a link, so its words stay selectable; the comment count and Open are. The poster is not a
 * link: the title page opens a library item, and a friend's title may not be one of yours. A
 * post that may spoil what the reader has not watched folds its words and stars behind the veil
 * until asked; the author never sees one, and only the author sees how it is marked.
 */
export function PostCard(props: {
  post: BoardPost
  /** Handles that read as mentions: you, your friends and authors here, lowercased. */
  handles: ReadonlySet<string>
  myHandle?: string
}) {
  const [shown, setShown] = createSignal(false)
  const veiled = () => props.post.veiled && !props.post.mine && !shown()
  const name = () => (props.post.mine ? 'You' : inviterName(props.post.author))
  const segments = () =>
    splitMentions(props.post.body, props.handles, props.myHandle)

  return (
    <article
      aria-label={`Post by ${inviterName(props.post.author)}`}
      class="flex gap-3 py-5"
    >
      <Link
        to="/app/friends/$handle"
        params={{ handle: props.post.author.handle }}
        aria-label={inviterName(props.post.author)}
        class="shrink-0 self-start rounded-full"
      >
        <Monogram text={monogram(props.post.author)} />
      </Link>
      <div class="min-w-0 flex-1">
        <p class="flex flex-wrap items-baseline gap-x-2 text-sm leading-tight">
          <span class="font-semibold">{name()}</span>
          <span class="text-muted">@{props.post.author.handle}</span>
          <time
            datetime={props.post.createdAt}
            title={new Date(props.post.createdAt).toLocaleString()}
            class="text-xs text-muted tabular-nums"
          >
            {postedLabel(props.post.createdAt)}
          </time>
          <Show when={props.post.editedAt}>
            <span class="text-xs text-muted">Edited</span>
          </Show>
        </p>

        <Show when={props.post.title}>
          {(t) => (
            <div class="mt-3 flex items-center gap-3">
              <Poster
                url={t().posterUrl}
                kind={kindOf(t().type, t().isAnime)}
                radius="thumb"
                class="w-12 shrink-0"
              />
              <div class="min-w-0 flex-1 leading-tight">
                <p class="truncate font-display text-base font-medium">
                  {t().title}
                  <Show when={t().year}>
                    <span class="ml-1.5 font-sans text-sm font-normal text-muted tabular-nums">
                      {t().year}
                    </span>
                  </Show>
                </p>
                <div class="mt-1 flex flex-wrap items-baseline gap-x-3 gap-y-0.5">
                  <Show when={props.post.rating !== undefined && !veiled()}>
                    <p class="text-base tracking-wide text-gold">
                      <span aria-hidden="true">
                        {starsLabel(props.post.rating!)}
                      </span>
                      <span class="sr-only">
                        {ratingWords(props.post.rating!)}
                      </span>
                    </p>
                  </Show>
                  <Show when={!props.post.mine}>
                    <AddToLibrary title={t()} look="inline" />
                  </Show>
                </div>
                <Show
                  when={props.post.mine && spoilerLabel(props.post.spoiler)}
                >
                  {(label) => (
                    <p
                      title="Friends who haven't watched this far see it veiled. Only you see the mark."
                      class="mt-1 text-xs text-muted"
                    >
                      <span aria-hidden="true">◐ </span>
                      {label()}
                    </p>
                  )}
                </Show>
              </div>
            </div>
          )}
        </Show>

        <Show
          when={!veiled()}
          fallback={
            <div class="mt-3">
              <SpoilerVeil onShow={() => setShown(true)} />
            </div>
          }
        >
          <p class="mt-2 text-[15px] leading-relaxed break-words whitespace-pre-wrap">
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
        </Show>

        <div class="mt-3 flex items-center gap-2">
          <UpvoteButton
            postId={props.post.id}
            upvotes={props.post.upvotes}
            upvotedByMe={props.post.upvotedByMe}
          />
          <a
            href={postHref(props.post.id)}
            aria-label={`${props.post.commentCount} ${props.post.commentCount === 1 ? 'comment' : 'comments'}`}
            class="inline-flex min-h-8 items-center gap-1.5 rounded-full bg-surface px-3 text-xs font-semibold text-muted tabular-nums hover:text-ink"
          >
            <span aria-hidden="true">💬</span>
            {props.post.commentCount}
          </a>
          <a
            href={postHref(props.post.id)}
            class="ml-auto rounded-full px-2 py-1 text-xs font-medium text-muted hover:text-ink"
          >
            Open<span class="sr-only"> post</span>
          </a>
        </div>
      </div>
    </article>
  )
}
