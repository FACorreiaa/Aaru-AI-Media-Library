import {
  Show,
  Suspense,
  createEffect,
  createSignal,
  lazy,
  on,
  onCleanup,
  onMount,
} from 'solid-js'
import {
  Button,
  TextField,
  TextFieldLabel,
  TextFieldTextArea,
  toast,
} from '~/components/ui'
import type { BoardPost } from '../../lib/board/model'
import { createPost, loadComposerTitle } from '../../lib/board/server'
import { AUTO_SPOILER, hitRef, spoilerFields } from '../../lib/groups/kinds'
import type {
  CatalogHit,
  MediaRef,
  SpoilerChoice,
} from '../../lib/groups/kinds'
import { MAX_MESSAGE_LENGTH, remainingLabel } from '../../lib/groups/model'
import { kindOf } from '../../lib/library/model'
import type { MediaType } from '../../lib/media'
import { monogram } from '../../lib/social/model'
import type { SocialUser } from '../../lib/social/server'
import { MentionList, createMentions } from '../Mentions'
import { Poster } from '../Poster'
import { Monogram } from '../groups/Monogram'

// The catalog search and the review controls load when someone first asks for a title, not
// with the Board.
const loadPicker = () =>
  import('../groups/TitlePicker').then((m) => ({ default: m.TitlePicker }))
const loadReview = () => import('./TitleReview')
const TitlePicker = lazy(loadPicker)
const TitleReview = lazy(loadReview)

/** The title a post is about, as the composer shows and sends it. */
type Picked = {
  ref: MediaRef
  type: MediaType
  title: string
  year?: number
  posterUrl?: string
  isAnime: boolean
  libraryItemId?: string
}

function fromHit(hit: CatalogHit): Picked {
  return {
    ref: hitRef(hit),
    type: hit.type,
    title: hit.title,
    year: hit.year,
    posterUrl: hit.posterUrl,
    isAnime: hit.isAnime,
    libraryItemId: hit.libraryItemId,
  }
}

/**
 * PostComposer (BOARD-002): the inline box on top of the Board. One quiet line until it is
 * focused, then it grows like the groups composer (to 220px) and offers a title. With a title
 * come stars with halves, the spoiler mark, and one line saying what posting does to your
 * library. No dialog, no floating button (owner, 2026-10-23).
 */
export function PostComposer(props: {
  me: SocialUser
  /** Who `@` suggests: your friends. Never Aaru, until it answers on the Board (BOARD-004). */
  friends: SocialUser[]
  /** A title to start with: `?title=<id>` from a title page's "Write about this". */
  initialTitleId?: string
  /** The starting title was used or put aside, so the link can forget it. */
  onTitleDone?: () => void
  onPosted: (post: BoardPost) => void
}) {
  let section: HTMLElement | undefined
  let box: HTMLTextAreaElement | undefined
  const [text, setText] = createSignal('')
  const [open, setOpen] = createSignal(false)
  const [picking, setPicking] = createSignal(false)
  const [picked, setPicked] = createSignal<Picked | null>(null)
  const [loadingTitle, setLoadingTitle] = createSignal(false)
  const [rating, setRating] = createSignal<number | undefined>()
  const [spoiler, setSpoiler] = createSignal<SpoilerChoice>(AUTO_SPOILER)
  const [posting, setPosting] = createSignal(false)
  const mentions = createMentions({
    people: () => props.friends.map((user) => ({ user })),
    meId: () => props.me.userId,
    id: 'board-composer-mentions',
    box: () => box,
    text,
    onPick: (value) => {
      setText(value)
      resize()
    },
  })
  // Bumped by Cancel, so a starting title that arrives after it is dropped.
  let titleTicket = 0

  const expanded = () =>
    open() || text().length > 0 || !!picked() || picking() || loadingTitle()
  const remaining = () => remainingLabel(text())
  const tooLong = () => text().length > MAX_MESSAGE_LENGTH
  const canPost = () =>
    text().trim().length > 0 && !tooLong() && !posting() && !loadingTitle()

  function resize() {
    if (!box) return
    box.style.height = 'auto'
    box.style.height = `${Math.min(box.scrollHeight, 220)}px`
  }

  createEffect(
    on(
      () => props.initialTitleId,
      async (id) => {
        if (!id) return
        const mine = ++titleTicket
        setLoadingTitle(true)
        void loadReview()
        try {
          const t = await loadComposerTitle({ data: { id } })
          if (mine !== titleTicket) return
          setPicked({
            ref: { titleId: t.titleId, type: t.type },
            type: t.type,
            title: t.title,
            year: t.year,
            posterUrl: t.posterUrl,
            isAnime: t.isAnime,
            libraryItemId: t.libraryItemId,
          })
          setRating(t.rating)
          setPicking(false)
          box?.focus()
        } catch (error) {
          if (mine !== titleTicket) return
          toast(
            error instanceof Error
              ? error.message
              : 'That title could not be loaded.',
          )
          props.onTitleDone?.()
        } finally {
          if (mine === titleTicket) setLoadingTitle(false)
        }
      },
    ),
  )

  function pick(hit: CatalogHit) {
    setPicked(fromHit(hit))
    setPicking(false)
    box?.focus()
  }

  function removeTitle() {
    setPicked(null)
    setRating(undefined)
    setSpoiler(AUTO_SPOILER)
    props.onTitleDone?.()
    box?.focus()
  }

  function reset() {
    titleTicket++
    setLoadingTitle(false)
    setText('')
    mentions.close()
    if (box) box.value = ''
    setPicked(null)
    setPicking(false)
    setRating(undefined)
    setSpoiler(AUTO_SPOILER)
    setOpen(false)
    resize()
    if (props.initialTitleId) props.onTitleDone?.()
  }

  function cancel() {
    reset()
    box?.blur()
  }

  async function post() {
    if (!canPost()) return
    const p = picked()
    setPosting(true)
    try {
      const created = await createPost({
        data: {
          body: text().trim(),
          ...(p
            ? { title: p.ref, rating: rating(), ...spoilerFields(spoiler()) }
            : {}),
        },
      })
      props.onPosted(created)
      reset()
      box?.blur()
    } catch (error) {
      toast(
        error instanceof Error ? error.message : 'Your post was not shared.',
      )
    } finally {
      setPosting(false)
    }
  }

  /** Leaving an untouched box folds it back to one line. */
  function fold(target: EventTarget | null) {
    if (target instanceof Node && section?.contains(target)) return
    if (text().trim() || picked() || picking() || loadingTitle()) return
    setOpen(false)
  }

  // Tabbing away folds on focusout. A click folds on pointerdown outside: Safari does not focus
  // a clicked button, so a focusout alone would fold the box before "+ Title" got its click.
  onMount(() => {
    const down = (event: PointerEvent) => {
      if (open()) fold(event.target)
    }
    document.addEventListener('pointerdown', down)
    onCleanup(() => document.removeEventListener('pointerdown', down))
  })

  return (
    <section
      ref={section}
      aria-label="Write a post"
      onFocusOut={(e) => {
        if (e.relatedTarget) fold(e.relatedTarget)
      }}
      class={`rounded-card bg-surface px-3 py-3 transition-shadow sm:px-4 ${tooLong() ? 'ring-2 ring-danger' : 'focus-within:ring-2 focus-within:ring-accent/60'}`}
    >
      <div class="flex gap-3">
        <Monogram
          text={monogram(props.me)}
          avatarUrl={props.me.avatarUrl}
          size="sm"
          class="mt-0.5"
        />
        <div class="min-w-0 flex-1">
          <TextField value={text()} onChange={setText} class="relative flex">
            <TextFieldLabel class="sr-only">Write a post</TextFieldLabel>
            <TextFieldTextArea
              ref={box}
              rows={1}
              placeholder="Write something…"
              role="combobox"
              aria-autocomplete="list"
              aria-expanded={mentions.expanded()}
              aria-controls={mentions.id}
              aria-activedescendant={mentions.activeId()}
              onFocus={() => setOpen(true)}
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
                  void post()
                }
              }}
              class={`max-h-[220px] flex-1 resize-none rounded-none border-0 bg-transparent px-0 py-1 text-base leading-6 placeholder:text-muted focus-visible:ring-0 md:text-base ${expanded() ? 'min-h-[4.5rem]' : 'min-h-8'}`}
            />
            {/* Under the box: the composer sits at the top of the page. */}
            <MentionList
              mentions={mentions}
              class="top-full right-0 left-0 z-20 mt-1 slide-in-from-top-1"
            />
          </TextField>

          <Show when={expanded()}>
            <Show when={loadingTitle()}>
              <p class="mt-2 text-sm text-muted" aria-live="polite">
                Loading the title…
              </p>
            </Show>

            <Show when={picked()}>
              {(p) => (
                <div class="mt-3 rounded-panel bg-paper p-3">
                  <div class="flex items-center gap-3">
                    <Poster
                      url={p().posterUrl}
                      kind={kindOf(p().type, p().isAnime)}
                      radius="thumb"
                      class="w-10 shrink-0"
                    />
                    <p class="min-w-0 flex-1 leading-tight">
                      <span class="block truncate font-display text-base font-medium">
                        {p().title}
                      </span>
                      <Show when={p().year}>
                        <span class="text-sm text-muted tabular-nums">
                          {p().year}
                        </span>
                      </Show>
                    </p>
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      aria-label={`Remove ${p().title}`}
                      onClick={removeTitle}
                    >
                      <span aria-hidden="true">✕</span>
                    </Button>
                  </div>
                  <Suspense fallback={<div class="min-h-11" />}>
                    <TitleReview
                      title={p()}
                      rating={rating()}
                      onRating={setRating}
                      spoiler={spoiler()}
                      onSpoiler={setSpoiler}
                    />
                  </Suspense>
                </div>
              )}
            </Show>

            <Show when={picking() && !picked()}>
              <div class="mt-3 rounded-panel bg-paper p-3">
                <Suspense
                  fallback={<p class="text-sm text-muted">Loading search…</p>}
                >
                  <TitlePicker onPick={pick} />
                </Suspense>
              </div>
            </Show>

            <div class="mt-3 flex flex-wrap items-center gap-2">
              <Show when={!picked() && !loadingTitle()}>
                <Button
                  variant="ghost"
                  size="bare"
                  aria-expanded={picking()}
                  onClick={() => {
                    // A title is on its way: fetch the review controls alongside the search.
                    if (!picking()) void loadReview()
                    setPicking(!picking())
                  }}
                  class={`inline-flex min-h-8 items-center gap-1 rounded-full px-3 text-xs font-semibold ${picking() ? 'bg-ink text-paper hover:text-paper' : 'bg-paper text-ink'}`}
                >
                  <span aria-hidden="true">{picking() ? '✕' : '+'}</span>
                  Title
                </Button>
              </Show>
              <Show when={remaining()}>
                {(left) => (
                  <span
                    class={`text-xs tabular-nums ${tooLong() ? 'text-danger' : 'text-muted'}`}
                    aria-live="polite"
                  >
                    {left()}
                  </span>
                )}
              </Show>
              <div class="ml-auto flex items-center gap-1">
                <Button variant="ghost" size="sm" onClick={cancel}>
                  Cancel
                </Button>
                <Button
                  variant="ink"
                  size="sm"
                  disabled={!canPost()}
                  onClick={() => void post()}
                >
                  {posting() ? 'Posting…' : 'Post'}
                </Button>
              </div>
            </div>
          </Show>
        </div>
      </div>
    </section>
  )
}
