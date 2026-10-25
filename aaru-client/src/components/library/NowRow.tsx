import { Link } from '@tanstack/solid-router'
import { For, Show } from 'solid-js'
import type { NowItem } from '../../lib/library/now'
import { pop } from '../../lib/motion'
import { Poster } from '../Poster'
import { Button } from '~/components/ui'

/**
 * APP-018 · one title on a Now group page's list: a thumb, the title, its facts one per line, the
 * progress bar, and the one next step on the right. The grid's `NowCard` holds the same facts;
 * a book's page is moved there or on its page, so a row only finishes it.
 */
export function NowRow(props: {
  item: NowItem
  pending: boolean
  lines: string[]
  onTickNext: (next: { season: number; number: number }) => void
  onChapter: (chapter: number) => void
  onFinish: () => void
}) {
  const e = () => props.item.entry
  const isManga = () => props.item.kind === 'manga'
  const nextChapter = () => (e().mangaProgress?.chapter ?? 0) + 1
  const finishLabel = () =>
    props.item.kind === 'book' || isManga()
      ? 'Mark read'
      : props.item.kind === 'album'
        ? 'Mark listened'
        : 'Mark watched'
  return (
    <li class="flex items-center gap-4 py-3">
      <Link
        to="/app/title/$id"
        params={{ id: e().id }}
        class="flex min-w-0 flex-1 items-start gap-4"
      >
        <Poster
          url={e().title.posterUrl}
          kind={props.item.kind}
          class="w-12 shrink-0"
        />
        <div class="min-w-0 flex-1">
          <p class="line-clamp-2 font-medium">{e().title.title}</p>
          <div class="mt-1 flex items-center gap-3 text-sm">
            <span class="shrink-0 font-medium tabular-nums">
              {props.item.progressLabel}
            </span>
            <Show when={props.item.done !== undefined}>
              <div
                class="h-1.5 w-24 shrink-0 overflow-hidden rounded-full bg-ink/10"
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
          <ul class="mt-1 flex flex-col text-sm text-muted">
            <For each={props.lines}>
              {(line) => <li class="truncate">{line}</li>}
            </For>
          </ul>
        </div>
      </Link>
      <Show
        when={props.item.next}
        fallback={
          <Show
            when={isManga()}
            fallback={
              <Button
                variant="outline"
                size="sm"
                class="min-h-11 shrink-0"
                disabled={props.pending}
                onClick={() => props.onFinish()}
              >
                {finishLabel()}
              </Button>
            }
          >
            <Button
              variant="default"
              size="sm"
              class="min-h-11 shrink-0"
              disabled={props.pending}
              onClick={(event) => {
                void pop(event.currentTarget)
                props.onChapter(nextChapter())
              }}
            >
              ✓ Ch. {nextChapter()}
            </Button>
          </Show>
        }
      >
        {(next) => (
          <Button
            variant="default"
            size="sm"
            class="min-h-11 shrink-0"
            disabled={props.pending}
            aria-label={`Mark ${next().label} of ${e().title.title} watched`}
            onClick={(event) => {
              void pop(event.currentTarget)
              props.onTickNext(next())
            }}
          >
            ✓ {next().label}
          </Button>
        )}
      </Show>
    </li>
  )
}
