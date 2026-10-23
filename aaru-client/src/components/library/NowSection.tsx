import { Link } from '@tanstack/solid-router'
import { For, Show, createMemo, createSignal } from 'solid-js'
import { nowSections } from '../../lib/library/now'
import type { NowGroup, NowItem } from '../../lib/library/now'
import type { LibraryEntry, MediaKind } from '../../lib/library/model'
import { setEpisode, updateItem } from '../../lib/title/server'
import { pop } from '../../lib/motion'
import { Poster } from '../Poster'
import {
  Alert,
  AlertDescription,
  Button,
  buttonVariants,
  cardClass,
  TextField,
  TextFieldInput,
  TextFieldLabel,
} from '~/components/ui'
import { cn } from '~/lib/utils'

// APP-017 · "Now" at the top of Library: what the user is in the middle of, as big cards with a
// progress bar and the one next step — tick the next episode, move a book's page, finish. Each
// write is optimistic about nothing: the card waits for the server's entry and the shelf below
// takes the same entry, so both always agree.
//
// Each group shows its newest NOW_CAP cards; "Show all" opens the rest in place. A library with
// 150 shows in progress would otherwise push the shelf a page of cards down.

/** Fills two rows of the wide grid (three columns) and three of the medium one. */
export const NOW_CAP = 6

export function NowSection(props: {
  entries: LibraryEntry[]
  kind: MediaKind | null
  onEntry: (entry: LibraryEntry) => void
}) {
  const sections = createMemo(() => nowSections(props.entries, props.kind))
  const [pending, setPending] = createSignal<ReadonlySet<string>>(new Set())
  const [problem, setProblem] = createSignal<string | null>(null)
  // The groups opened past NOW_CAP.
  const [expanded, setExpanded] = createSignal<ReadonlySet<NowGroup>>(new Set())
  function toggle(group: NowGroup) {
    setExpanded((set) => {
      const next = new Set(set)
      if (!next.delete(group)) next.add(group)
      return next
    })
  }

  async function run(id: string, write: () => Promise<LibraryEntry>) {
    if (pending().has(id)) return
    setProblem(null)
    setPending((set) => new Set(set).add(id))
    try {
      props.onEntry(await write())
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'That change was not saved.',
      )
    } finally {
      setPending((set) => {
        const next = new Set(set)
        next.delete(id)
        return next
      })
    }
  }

  return (
    <Show when={sections().length > 0}>
      <div class="mt-6 flex flex-col gap-8" aria-label="Now">
        <Show when={problem()}>
          {(message) => (
            <Alert variant="destructive">
              <AlertDescription>{message()}</AlertDescription>
            </Alert>
          )}
        </Show>
        <For each={sections()}>
          {(section) => {
            const open = () => expanded().has(section.group)
            const shown = () =>
              open() ? section.items : section.items.slice(0, NOW_CAP)
            const listId = `now-${section.group}-items`
            return (
              <section aria-labelledby={`now-${section.group}`}>
                <div class="flex items-baseline justify-between gap-4">
                  <h2
                    id={`now-${section.group}`}
                    class="font-display text-2xl font-medium tracking-tight"
                  >
                    {section.title}
                  </h2>
                  <Show
                    when={section.items.length > NOW_CAP}
                    fallback={
                      <span class="text-sm text-muted">
                        {section.items.length}
                      </span>
                    }
                  >
                    <Button
                      variant="link"
                      size="bare"
                      class="text-sm font-medium"
                      aria-expanded={open()}
                      aria-controls={listId}
                      onClick={() => toggle(section.group)}
                    >
                      {open()
                        ? 'Show fewer'
                        : `Show all ${section.items.length}`}
                    </Button>
                  </Show>
                </div>
                <ul
                  id={listId}
                  class="-mx-5 mt-3 flex snap-x snap-mandatory scroll-px-5 gap-4 overflow-x-auto px-5 pb-2 md:mx-0 md:grid md:grid-cols-2 md:overflow-visible md:px-0 xl:grid-cols-3"
                >
                  <For each={shown()}>
                    {(item) => (
                      <NowCard
                        item={item}
                        pending={pending().has(item.entry.id)}
                        onTickNext={(next) =>
                          run(item.entry.id, () =>
                            setEpisode({
                              data: {
                                id: item.entry.id,
                                season: next.season,
                                episode: next.number,
                                watched: true,
                              },
                            }),
                          )
                        }
                        onPage={(page) =>
                          run(item.entry.id, () =>
                            updateItem({
                              data: {
                                id: item.entry.id,
                                patch: { bookPage: page },
                              },
                            }),
                          )
                        }
                        onFinish={() =>
                          run(item.entry.id, () =>
                            updateItem({
                              data: {
                                id: item.entry.id,
                                patch: { status: 'finished' },
                              },
                            }),
                          )
                        }
                      />
                    )}
                  </For>
                </ul>
              </section>
            )
          }}
        </For>
      </div>
    </Show>
  )
}

function NowCard(props: {
  item: NowItem
  pending: boolean
  onTickNext: (next: { season: number; number: number }) => void
  onPage: (page: number) => void
  onFinish: () => void
}) {
  const e = () => props.item.entry
  const isBook = () => props.item.kind === 'book'
  const isAlbum = () => props.item.kind === 'album'
  /** Books and albums lead with their cover; video with its backdrop. */
  const hasCover = () => isBook() || isAlbum()
  const art = () => e().title.backdropUrl ?? e().title.posterUrl
  const [editing, setEditing] = createSignal(false)
  return (
    <li
      class={cn(
        cardClass,
        'flex w-[18rem] shrink-0 snap-start flex-col overflow-hidden md:w-auto',
      )}
    >
      <Show
        when={!hasCover()}
        fallback={
          <div class="flex gap-4 p-4 pb-0">
            <Poster
              url={e().title.posterUrl}
              kind={props.item.kind}
              class="w-20 shrink-0"
            />
            <div class="min-w-0">
              <Link
                to="/app/title/$id"
                params={{ id: e().id }}
                class="line-clamp-3 font-display text-xl leading-tight font-medium hover:underline"
              >
                {e().title.title}
              </Link>
              <Show when={e().title.byline ?? e().title.year}>
                {(line) => <p class="mt-1 text-sm text-muted">{line()}</p>}
              </Show>
            </div>
          </div>
        }
      >
        <Link
          to="/app/title/$id"
          params={{ id: e().id }}
          class="relative block aspect-[16/9] overflow-hidden bg-accent/15"
        >
          <Show when={art()}>
            {(url) => (
              <img
                src={url()}
                alt=""
                loading="lazy"
                decoding="async"
                class="h-full w-full object-cover"
              />
            )}
          </Show>
          <span class="absolute inset-0 bg-gradient-to-t from-scrim via-scrim/20 to-transparent" />
          <span class="absolute inset-x-4 bottom-3 font-display text-xl leading-tight font-medium text-on-scrim">
            {e().title.title}
          </span>
        </Link>
      </Show>

      <div class="flex flex-1 flex-col gap-3 p-4">
        <div>
          <div class="flex items-baseline justify-between gap-3 text-sm">
            <span class="font-medium">{props.item.progressLabel}</span>
            <Show when={props.item.next}>
              {(next) => <span class="text-muted">Next {next().label}</span>}
            </Show>
          </div>
          <Show when={props.item.done !== undefined}>
            <div
              class="mt-2 h-1.5 overflow-hidden rounded-full bg-ink/10"
              role="progressbar"
              aria-valuemin={0}
              aria-valuemax={100}
              aria-valuenow={Math.round((props.item.done ?? 0) * 100)}
              aria-label={`${e().title.title} progress`}
            >
              <div
                class="h-full rounded-full bg-accent transition-[width] duration-300"
                style={{ width: `${(props.item.done ?? 0) * 100}%` }}
              />
            </div>
          </Show>
        </div>

        <Show
          when={editing()}
          fallback={
            <div class="mt-auto flex flex-wrap gap-2">
              <Show when={props.item.next}>
                {(next) => (
                  <Button
                    variant="default"
                    size="sm"
                    class="min-h-11"
                    disabled={props.pending}
                    onClick={(event) => {
                      void pop(event.currentTarget)
                      props.onTickNext(next())
                    }}
                  >
                    ✓ Watched {next().label}
                  </Button>
                )}
              </Show>
              <Show when={isBook()}>
                <Button
                  variant="default"
                  size="sm"
                  class="min-h-11"
                  disabled={props.pending}
                  onClick={() => setEditing(true)}
                >
                  Update page
                </Button>
              </Show>
              <Show when={!props.item.next}>
                <Button
                  variant="outline"
                  size="sm"
                  class="min-h-11"
                  disabled={props.pending}
                  onClick={() => props.onFinish()}
                >
                  {isBook()
                    ? 'Mark read'
                    : isAlbum()
                      ? 'Mark listened'
                      : 'Mark watched'}
                </Button>
              </Show>
              <Show when={props.item.next}>
                <Link
                  to="/app/title/$id"
                  params={{ id: e().id }}
                  class={cn(
                    buttonVariants({ variant: 'quiet', size: 'sm' }),
                    'min-h-11',
                  )}
                >
                  Episodes
                </Link>
              </Show>
            </div>
          }
        >
          <form
            class="mt-auto flex items-center gap-2"
            onSubmit={(event) => {
              event.preventDefault()
              const value = Number(
                new FormData(event.currentTarget).get('page'),
              )
              if (Number.isInteger(value) && value >= 0) {
                props.onPage(value)
                setEditing(false)
              }
            }}
          >
            <TextField
              name="page"
              defaultValue={String(e().bookProgress?.page ?? '')}
            >
              <TextFieldLabel class="sr-only">Page</TextFieldLabel>
              <TextFieldInput
                type="number"
                min="0"
                inputmode="numeric"
                placeholder="Page"
                class="w-24"
                autofocus
              />
            </TextField>
            <Button variant="default" size="sm" class="min-h-11" type="submit">
              Save
            </Button>
            <Button
              variant="ghost"
              size="sm"
              class="min-h-11"
              onClick={() => setEditing(false)}
            >
              Cancel
            </Button>
          </form>
        </Show>
      </div>
    </li>
  )
}
