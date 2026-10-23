import { Link, createFileRoute, useNavigate } from '@tanstack/solid-router'
import { For, Show, Suspense, createMemo, createSignal, lazy } from 'solid-js'
import {
  Button,
  Popover,
  PopoverContent,
  PopoverPortal,
  PopoverTrigger,
  TextField,
  TextFieldLabel,
  TextFieldTextArea,
  buttonVariants,
  toast,
} from '~/components/ui'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { CommentThread } from '../components/board/CommentThread'
import { PostCard } from '../components/board/PostCard'
import { Menu, MenuItem } from '../components/groups/shell'
import { Monogram } from '../components/groups/Monogram'
import { BackLink } from '../components/shell/BackLink'
import { upvotersLine } from '../lib/board/model'
import type { BoardPost, UpvoteState } from '../lib/board/model'
import { loadPost } from '../lib/board/post'
import { deletePost, editPost } from '../lib/board/server'
import { MAX_MESSAGE_LENGTH, remainingLabel } from '../lib/groups/model'
import { inviterName, monogram } from '../lib/social/model'
import type { SocialUser } from '../lib/social/server'

// Reporting is rare: its dialog loads when someone first asks for it.
const ReportPostDialog = lazy(
  () => import('../components/board/ReportPostDialog'),
)

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

// BOARD-002 on the web: one post on its own page (owner, 2026-10-23). The post, who upvoted
// it, its thread (one level of replies) and a reply box. Your own post can be edited (its words
// only) or deleted; a friend's can be reported. A post that is not there for you (deleted, its
// author no longer your friend, or blocked) says so in place, like a friend's profile does.
export const Route = createFileRoute('/_shell/app_/friends/posts/$postId')({
  loader: ({ params }) =>
    UUID.test(params.postId)
      ? loadPost({ data: { postId: params.postId } })
      : Promise.resolve(null),
  head: ({ loaderData }) => ({
    meta: [
      {
        title: loaderData
          ? `Post by ${inviterName(loaderData.post.author)} · Aaru`
          : 'Post · Aaru',
      },
    ],
  }),
  component: PostPage,
})

function PostPage() {
  const loaded = Route.useLoaderData()
  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <BackLink to="/app/friends" label="Friends" class="-ml-1" />
        <Show
          when={loaded()}
          keyed
          fallback={
            <div class="max-w-2xl">
              <h1 class="mt-4 font-display text-4xl font-medium tracking-tight">
                This post isn’t here
              </h1>
              <p class="mt-3 text-muted">
                It was deleted, or you and its author are no longer friends.
              </p>
              <Link
                to="/app/friends"
                class="mt-6 inline-block font-semibold text-accent"
              >
                Back to Friends
              </Link>
            </div>
          }
        >
          {(page) => <PostView page={page} />}
        </Show>
      </div>
    </div>
  )
}

type Page = NonNullable<Awaited<ReturnType<typeof loadPost>>>

function PostView(props: { page: Page }) {
  const navigate = useNavigate()
  let article: HTMLDivElement | undefined
  const [post, setPost] = createSignal<BoardPost>(props.page.post)
  const [upvoters, setUpvoters] = createSignal<SocialUser[]>(
    props.page.upvoters,
  )
  const [editing, setEditing] = createSignal(false)
  const [asking, setAsking] = createSignal<'delete' | 'report' | null>(null)
  const [deleting, setDeleting] = createSignal(false)
  const reported = createMemo<boolean>(
    (seen) => seen || asking() === 'report',
    false,
  )
  const me = () => props.page.me
  // Edit was picked: the closing menu leaves focus to the edit box instead of its trigger.
  let toEditor = false

  /** Mentions read and suggest: you, your friends, and the post's author. */
  const people = createMemo(() => {
    const author = post().author
    const friends = props.page.friends
    return friends.some((f) => f.userId === author.userId)
      ? friends
      : [author, ...friends]
  })
  const handles = createMemo(
    () =>
      new Set(
        [me().handle, ...people().map((p) => p.handle)].map((h) =>
          h.toLowerCase(),
        ),
      ),
  )

  /** Your upvote shows at once among the names, first, as "You". */
  function upvoted(state: UpvoteState) {
    const others = upvoters().filter((u) => u.userId !== me().userId)
    setUpvoters(state.upvotedByMe ? [me(), ...others] : others)
  }

  function stopEditing() {
    setEditing(false)
    article?.focus()
  }

  async function confirmDelete() {
    if (deleting()) return
    setDeleting(true)
    try {
      await deletePost({ data: { postId: post().id } })
      toast('Post deleted.')
      // Replaces this page in history, so Back does not return to a post that is gone.
      void navigate({ to: '/app/friends', replace: true })
    } catch (error) {
      toast(
        error instanceof Error ? error.message : 'That post was not deleted.',
      )
      setDeleting(false)
    }
  }

  const menu = (
    <Menu
      label="Post actions"
      onCloseAutoFocus={(event) => {
        if (!toEditor) return
        toEditor = false
        event.preventDefault()
      }}
      trigger={<span aria-hidden="true">⋯</span>}
      triggerClass={`${buttonVariants({ variant: 'ghost', size: 'icon-sm' })} size-8 rounded-full text-muted hover:text-ink`}
    >
      <Show
        when={post().mine}
        fallback={
          <MenuItem onSelect={() => setAsking('report')}>Report post</MenuItem>
        }
      >
        <MenuItem
          onSelect={() => {
            toEditor = true
            setEditing(true)
          }}
        >
          Edit post
        </MenuItem>
        <MenuItem danger onSelect={() => setAsking('delete')}>
          Delete post
        </MenuItem>
      </Show>
    </Menu>
  )

  return (
    <div class="mt-4 max-w-2xl">
      <h1 class="sr-only">Post by {inviterName(post().author)}</h1>
      {/* Focus returns here after an edit, so a screen reader reads the post again. */}
      <div ref={article} tabindex="-1" class="outline-none">
        <PostCard
          post={post()}
          handles={handles()}
          myHandle={me().handle.toLowerCase()}
          standalone
          menu={menu}
          editor={
            editing() ? (
              <PostEditor
                post={post()}
                onSaved={(saved) => {
                  setPost({
                    ...post(),
                    body: saved.body,
                    editedAt: saved.editedAt,
                  })
                  stopEditing()
                }}
                onCancel={stopEditing}
              />
            ) : undefined
          }
          beside={<Upvoters people={upvoters()} me={me()} />}
          onUpvote={upvoted}
        />
      </div>

      <CommentThread
        postId={post().id}
        postMine={post().mine}
        initial={props.page.comments}
        me={me()}
        people={people()}
        handles={handles()}
        commentCount={post().commentCount}
        onCount={(delta) =>
          setPost({
            ...post(),
            commentCount: Math.max(0, post().commentCount + delta),
          })
        }
      />

      <ConfirmDialog
        open={asking() === 'delete'}
        title="Delete this post?"
        description="Its comments and upvotes go with it."
        confirmLabel={deleting() ? 'Deleting…' : 'Delete post'}
        busy={deleting()}
        onConfirm={() => void confirmDelete()}
        onCancel={() => {
          if (!deleting()) setAsking(null)
        }}
      />
      {/* Loaded on the first Report and kept, so it closes with its exit like any dialog. */}
      <Show when={reported()}>
        <Suspense>
          <ReportPostDialog
            open={asking() === 'report'}
            post={post()}
            onClose={() => setAsking(null)}
          />
        </Suspense>
      </Show>
    </div>
  )
}

/**
 * Who upvoted, after the Upvote button: "Ana, Ben and 10 others". A tap lists them all, each
 * opening their profile (yours goes nowhere: it is you).
 */
function Upvoters(props: { people: SocialUser[]; me: SocialUser }) {
  const names = () =>
    props.people.map((p) =>
      p.userId === props.me.userId ? 'You' : inviterName(p),
    )
  return (
    <Show when={upvotersLine(names())}>
      {(line) => (
        <Popover placement="bottom-start">
          <PopoverTrigger
            aria-label={`Upvoted by ${line()}. Show everyone`}
            class="min-h-8 min-w-0 cursor-pointer truncate rounded-full px-2 text-left text-xs text-muted hover:text-ink"
          >
            {line()}
          </PopoverTrigger>
          <PopoverPortal>
            <PopoverContent class="w-64 rounded-panel border-line bg-paper p-1 text-sm text-ink shadow-lift">
              <p class="px-3 pt-2 pb-1 text-xs text-muted">
                <span aria-hidden="true" class="text-accent">
                  ▲{' '}
                </span>
                {props.people.length}{' '}
                {props.people.length === 1 ? 'upvote' : 'upvotes'}
              </p>
              <ul class="max-h-72 overflow-y-auto">
                <For each={props.people}>
                  {(person) => (
                    <li>
                      <Show
                        when={person.userId !== props.me.userId}
                        fallback={
                          <span class="flex items-center gap-3 px-3 py-2">
                            <Monogram text={monogram(person)} size="sm" />
                            <span class="font-medium">You</span>
                          </span>
                        }
                      >
                        <Link
                          to="/app/friends/$handle"
                          params={{ handle: person.handle }}
                          class="flex items-center gap-3 rounded-xl px-3 py-2 hover:bg-surface"
                        >
                          <Monogram text={monogram(person)} size="sm" />
                          <span class="min-w-0 truncate font-medium">
                            {inviterName(person)}
                          </span>
                          <Show when={person.displayName}>
                            <span class="truncate text-muted">
                              @{person.handle}
                            </span>
                          </Show>
                        </Link>
                      </Show>
                    </li>
                  )}
                </For>
              </ul>
            </PopoverContent>
          </PopoverPortal>
        </Popover>
      )}
    </Show>
  )
}

/** The post's words in a box, in place (body only). Escape cancels; ⌘/Ctrl+Enter saves. */
function PostEditor(props: {
  post: BoardPost
  onSaved: (post: BoardPost) => void
  onCancel: () => void
}) {
  const [text, setText] = createSignal(props.post.body)
  const [saving, setSaving] = createSignal(false)
  const tooLong = () => text().length > MAX_MESSAGE_LENGTH
  const canSave = () =>
    text().trim().length > 0 &&
    text().trim() !== props.post.body &&
    !tooLong() &&
    !saving()

  async function save() {
    if (!canSave()) return
    setSaving(true)
    try {
      props.onSaved(
        await editPost({
          data: { postId: props.post.id, body: text().trim() },
        }),
      )
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Your edit was not saved.')
      setSaving(false)
    }
  }

  function size(box: HTMLTextAreaElement) {
    box.style.height = 'auto'
    box.style.height = `${Math.min(box.scrollHeight, 320)}px`
  }

  return (
    <div class="rounded-panel bg-surface p-3">
      <TextField value={text()} onChange={setText} class="flex">
        <TextFieldLabel class="sr-only">Edit your post</TextFieldLabel>
        <TextFieldTextArea
          ref={(box: HTMLTextAreaElement) =>
            queueMicrotask(() => {
              size(box)
              box.focus()
              box.setSelectionRange(box.value.length, box.value.length)
            })
          }
          onInput={(e) => size(e.currentTarget)}
          onKeyDown={(e: KeyboardEvent) => {
            if (e.key === 'Escape') {
              e.preventDefault()
              props.onCancel()
            } else if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
              e.preventDefault()
              void save()
            }
          }}
          class="max-h-80 min-h-16 flex-1 resize-none rounded-none border-0 bg-transparent px-0 py-1 text-md leading-relaxed focus-visible:ring-0"
        />
      </TextField>
      <div class="mt-2 flex items-center justify-end gap-1">
        <Show when={remainingLabel(text())}>
          {(left) => (
            <span
              class={`mr-auto text-xs tabular-nums ${tooLong() ? 'text-danger' : 'text-muted'}`}
              aria-live="polite"
            >
              {left()}
            </span>
          )}
        </Show>
        <Button variant="ghost" size="sm" onClick={() => props.onCancel()}>
          Cancel
        </Button>
        <Button
          variant="ink"
          size="sm"
          disabled={!canSave()}
          onClick={() => void save()}
        >
          {saving() ? 'Saving…' : 'Save'}
        </Button>
      </div>
    </div>
  )
}
