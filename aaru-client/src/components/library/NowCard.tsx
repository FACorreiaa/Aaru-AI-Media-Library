import { Link } from '@tanstack/solid-router'
import { For, Show, createSignal } from 'solid-js'
import type { NowItem } from '../../lib/library/now'
import { pop } from '../../lib/motion'
import { Poster } from '../Poster'
import {
  Button,
  buttonVariants,
  cardClass,
  TextField,
  TextFieldInput,
  TextFieldLabel,
} from '~/components/ui'
import { cn } from '~/lib/utils'

/**
 * APP-017 · one title the user is in the middle of, as a big card: the backdrop (or a cover), how
 * far along it is, and the one next step. Library's Now and the group pages' grid (APP-018).
 */
export function NowCard(props: {
  item: NowItem
  pending: boolean
  /** In a Home row: the same width at every size (the Library's grid lets it stretch). */
  inRow?: boolean
  /** Facts under the progress bar, one line each (the Watching page, APP-018). */
  lines?: string[]
  onTickNext: (next: { season: number; number: number }) => void
  onPage: (page: number) => void
  onChapter: (chapter: number) => void
  onFinish: () => void
}) {
  const e = () => props.item.entry
  const isBook = () => props.item.kind === 'book'
  const isManga = () => props.item.kind === 'manga'
  const isAlbum = () => props.item.kind === 'album'
  /** Books, manga and albums lead with their cover; video with its backdrop. */
  const hasCover = () => isBook() || isManga() || isAlbum()
  /** The chapter one tap logs: the one after the last read. */
  const nextChapter = () => (e().mangaProgress?.chapter ?? 0) + 1
  const art = () => e().title.backdropUrl ?? e().title.posterUrl
  const [editing, setEditing] = createSignal(false)
  return (
    <li
      class={cn(
        cardClass,
        'flex w-[18rem] shrink-0 snap-start flex-col overflow-hidden',
        !props.inRow && 'md:w-auto',
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

        <Show when={props.lines?.length}>
          <ul class="flex flex-col gap-0.5 text-sm text-muted">
            <For each={props.lines}>{(line) => <li>{line}</li>}</For>
          </ul>
        </Show>

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
              <Show when={isManga()}>
                <Button
                  variant="default"
                  size="sm"
                  class="min-h-11"
                  disabled={props.pending}
                  onClick={(event) => {
                    void pop(event.currentTarget)
                    props.onChapter(nextChapter())
                  }}
                >
                  ✓ Read ch. {nextChapter()}
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
                  {isBook() || isManga()
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
