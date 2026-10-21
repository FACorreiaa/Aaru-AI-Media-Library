import { Link } from '@tanstack/solid-router'
import { For, Show, createMemo, createSignal } from 'solid-js'
import { nowSections } from '../../lib/library/now'
import type { NowItem } from '../../lib/library/now'
import type { LibraryEntry, MediaKind } from '../../lib/library/model'
import { setEpisode, updateItem } from '../../lib/title/server'
import { pop } from '../../lib/motion'
import { Poster } from '../Poster'
import { Alert } from '../ui/alert'
import { Button, buttonVariants } from '../ui/button'
import { cardClass } from '../ui/card'
import { cn } from '../../lib/cn'

// APP-017 · "Now" at the top of Library: what the user is in the middle of, as big cards with a
// progress bar and the one next step — tick the next episode, move a book's page, finish. Each
// write is optimistic about nothing: the card waits for the server's entry and the shelf below
// takes the same entry, so both always agree.

export function NowSection(props: {
  entries: LibraryEntry[]
  kind: MediaKind | null
  onEntry: (entry: LibraryEntry) => void
}) {
  const sections = createMemo(() => nowSections(props.entries, props.kind))
  const [pending, setPending] = createSignal<ReadonlySet<string>>(new Set())
  const [problem, setProblem] = createSignal<string | null>(null)

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
        <Show when={problem()}>{(message) => <Alert>{message()}</Alert>}</Show>
        <For each={sections()}>
          {(section) => (
            <section aria-labelledby={`now-${section.group}`}>
              <div class="flex items-baseline justify-between gap-4">
                <h2
                  id={`now-${section.group}`}
                  class="font-display text-2xl font-medium tracking-tight"
                >
                  {section.title}
                </h2>
                <span class="text-sm text-muted">{section.items.length}</span>
              </div>
              <ul class="-mx-5 mt-3 flex snap-x snap-mandatory scroll-px-5 gap-4 overflow-x-auto px-5 pb-2 md:mx-0 md:grid md:grid-cols-2 md:overflow-visible md:px-0 xl:grid-cols-3">
                <For each={section.items}>
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
          )}
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
        when={!isBook()}
        fallback={
          <div class="flex gap-4 p-4 pb-0">
            <Poster
              url={e().title.posterUrl}
              kind="book"
              class="w-20 shrink-0 shadow-md"
            />
            <div class="min-w-0">
              <Link
                to="/app/title/$id"
                params={{ id: e().id }}
                class="line-clamp-3 font-display text-xl leading-tight font-medium hover:underline"
              >
                {e().title.title}
              </Link>
              <Show when={e().title.year}>
                <p class="mt-1 text-sm text-muted">{e().title.year}</p>
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
          <span class="absolute inset-0 bg-gradient-to-t from-black/75 via-black/15 to-transparent" />
          <span class="absolute inset-x-4 bottom-3 font-display text-xl leading-tight font-medium text-white">
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
                    variant="primary"
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
                  variant="primary"
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
                  size="sm"
                  class="min-h-11"
                  disabled={props.pending}
                  onClick={() => props.onFinish()}
                >
                  {isBook() ? 'Finished' : 'Mark watched'}
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
            <label class="sr-only" for={`page-${e().id}`}>
              Page
            </label>
            <input
              id={`page-${e().id}`}
              name="page"
              type="number"
              min="0"
              inputmode="numeric"
              value={e().bookProgress?.page ?? ''}
              placeholder="Page"
              class="min-h-11 w-24 rounded-field border border-line bg-paper px-3 text-sm"
              autofocus
            />
            <Button variant="primary" size="sm" class="min-h-11" type="submit">
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
