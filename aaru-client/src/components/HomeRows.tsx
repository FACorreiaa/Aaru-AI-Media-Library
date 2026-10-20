import { Link } from '@tanstack/solid-router'
import { Show, createSignal, createUniqueId } from 'solid-js'
import type { JSX } from 'solid-js'
import { badge, metaLine, shortCode } from '../lib/calendar/model'
import type { CalendarEntry } from '../lib/calendar/model'
import { kindOf } from '../lib/library/model'
import {
  nextLine,
  remainingLabel,
  resumeLine,
  runtimeLabel,
  unfinishedLabel,
} from '../lib/home/model'
import type {
  ContinueEntry,
  StartEntry,
  UnfinishedEntry,
} from '../lib/home/model'
import { Poster } from './Poster'

// APP-009: Home's rows (DESIGN.md §13). Each row scrolls sideways and snaps; it takes focus so
// the arrow keys scroll it, and on desktop it has its own back / forward buttons.

/** A horizontal row: a heading, an optional action, and cards that snap as they scroll. */
export function Row(props: {
  title: string
  action?: JSX.Element
  children: JSX.Element
}) {
  const id = createUniqueId()
  let scroller: HTMLDivElement | undefined
  const scroll = (direction: 1 | -1) =>
    scroller?.scrollBy({
      left: direction * scroller.clientWidth * 0.85,
      behavior: 'smooth',
    })
  const arrow =
    'grid h-8 w-8 place-items-center rounded-full border border-line text-ink hover:bg-surface focus-visible:outline-2 focus-visible:outline-accent'
  return (
    <section class="mt-10" aria-labelledby={id}>
      <div class="flex items-end justify-between gap-4">
        <h2 id={id} class="font-display text-2xl font-medium tracking-tight">
          {props.title}
        </h2>
        <div class="flex items-center gap-3">
          {props.action}
          <div class="hidden gap-1 md:flex">
            <button
              type="button"
              class={arrow}
              aria-label={`Scroll ${props.title} back`}
              onClick={() => scroll(-1)}
            >
              <Chevron flip />
            </button>
            <button
              type="button"
              class={arrow}
              aria-label={`Scroll ${props.title} forward`}
              onClick={() => scroll(1)}
            >
              <Chevron />
            </button>
          </div>
        </div>
      </div>
      <div
        ref={scroller}
        role="region"
        aria-labelledby={id}
        tabindex="0"
        class="-mx-4 mt-4 flex snap-x snap-mandatory scroll-px-4 gap-4 overflow-x-auto px-4 pb-3 focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent md:mx-0 md:scroll-px-0 md:px-0"
      >
        {props.children}
      </div>
    </section>
  )
}

function Chevron(props: { flip?: boolean }) {
  return (
    <svg
      viewBox="0 0 20 20"
      class="h-4 w-4"
      classList={{ 'rotate-180': props.flip }}
      aria-hidden="true"
    >
      <path
        d="M7.5 4.5 13 10l-5.5 5.5"
        fill="none"
        stroke="currentColor"
        stroke-width="1.8"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
  )
}

/** Wide art: the show's backdrop, then its poster, then a tint with the title. */
function Art(props: { sources: (string | undefined)[]; title: string }) {
  const urls = () => props.sources.filter((u): u is string => !!u)
  const [failed, setFailed] = createSignal(0)
  const url = () => urls()[failed()]
  return (
    <Show
      when={url()}
      keyed
      fallback={
        <div class="grid h-full place-items-center bg-accent/15 px-4 text-center font-display text-lg leading-tight text-accent">
          {props.title}
        </div>
      }
    >
      {(src) => (
        <img
          src={src}
          alt=""
          loading="lazy"
          decoding="async"
          class="h-full w-full object-cover"
          onError={() => setFailed((n) => n + 1)}
        />
      )}
    </Show>
  )
}

/** Text on art: a dark scrim chip, legible on any image in either theme. */
const chip =
  'rounded-full bg-black/65 px-2 py-0.5 text-xs font-semibold text-white'

/** Continue watching: the next episode of an in-progress show, with a check to mark it. */
export function ContinueCard(props: {
  entry: ContinueEntry
  busy: boolean
  onWatched: (entry: ContinueEntry) => void
}) {
  const e = () => props.entry
  const runtime = () => runtimeLabel(e().nextRuntimeMinutes)
  return (
    <article class="w-[min(78vw,22rem)] shrink-0 snap-start">
      <Link
        to="/app/title/$id"
        params={{ id: e().libraryItemId }}
        tabindex="-1"
        aria-hidden="true"
        class="relative block aspect-video overflow-hidden rounded-[14px]"
      >
        <Art
          sources={[e().title.backdropUrl, e().title.posterUrl]}
          title={e().title.title}
        />
        <Show when={e().isFinale}>
          <span class="absolute top-2 right-2 rounded-full bg-ink px-2 py-0.5 text-xs font-semibold text-paper">
            Finale
          </span>
        </Show>
        <div class="absolute inset-x-2 bottom-2 flex items-end justify-between gap-2">
          <Show when={runtime()} fallback={<span />}>
            <span class={chip}>{runtime()}</span>
          </Show>
          <span class={chip}>
            {remainingLabel(e().remainingCount, e().remainingMinutes)}
          </span>
        </div>
      </Link>
      <div class="mt-2 flex items-start gap-3">
        <div class="min-w-0 flex-1">
          <Link
            to="/app/title/$id"
            params={{ id: e().libraryItemId }}
            class="block truncate font-semibold hover:underline"
          >
            {e().title.title}
          </Link>
          <p class="truncate text-sm text-muted">{nextLine(e())}</p>
        </div>
        <button
          type="button"
          disabled={props.busy}
          onClick={() => props.onWatched(e())}
          aria-label={`Mark ${e().title.title} ${shortCode(e().next.season, e().next.number)} watched`}
          class="grid h-9 w-9 shrink-0 place-items-center rounded-full border border-line text-accent transition-colors hover:bg-accent hover:text-on-accent focus-visible:outline-2 focus-visible:outline-accent disabled:opacity-50"
        >
          <svg viewBox="0 0 20 20" class="h-4 w-4" aria-hidden="true">
            <path
              d="m4.5 10.5 3.5 3.5 7.5-8"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>
        </button>
      </div>
    </article>
  )
}

/** Start watching: a wishlist title and how long it takes. */
export function StartCard(props: { entry: StartEntry }) {
  const e = () => props.entry
  return (
    <Link
      to="/app/title/$id"
      params={{ id: e().libraryItemId }}
      class="block w-32 shrink-0 snap-start md:w-36"
    >
      <Poster
        url={e().title.posterUrl}
        kind={kindOf(e().title.type, e().title.isAnime)}
      />
      <p class="mt-2 line-clamp-2 text-sm font-medium">{e().title.title}</p>
      <Show when={runtimeLabel(e().runtimeMinutes)}>
        {(runtime) => <p class="text-xs text-muted">{runtime()}</p>}
      </Show>
    </Link>
  )
}

/** Unfinished business: a dropped or long-paused title, why it is here, and where to resume. */
export function UnfinishedCard(props: {
  entry: UnfinishedEntry
  now: Date | null
}) {
  const e = () => props.entry
  const reason = () => {
    const now = props.now
    if (e().reason === 'dropped') return 'Dropped'
    return now ? unfinishedLabel(e(), now) : null
  }
  return (
    <Link
      to="/app/title/$id"
      params={{ id: e().libraryItemId }}
      class="block w-32 shrink-0 snap-start md:w-36"
    >
      <div class="relative">
        <Poster
          url={e().title.posterUrl}
          kind={kindOf(e().title.type, e().title.isAnime)}
        />
        <Show when={reason()}>
          {(text) => (
            <span class={`absolute top-2 left-2 ${chip}`}>{text()}</span>
          )}
        </Show>
      </div>
      <p class="mt-2 line-clamp-2 text-sm font-medium">{e().title.title}</p>
      <Show when={resumeLine(e())}>
        {(line) => <p class="text-xs text-muted">{line()}</p>}
      </Show>
    </Link>
  )
}

/** Calendar row: one coming airing, badged "Tomorrow", "In 3 hours"… */
export function AiringCard(props: {
  entry: CalendarEntry
  when: string | null
}) {
  const e = () => props.entry
  const kind = () => badge(e())
  const meta = () => metaLine(e())
  return (
    <Link
      to="/app/title/$id"
      params={{ id: e().libraryItemId }}
      class="block w-56 shrink-0 snap-start transition-opacity"
      classList={{ 'opacity-60': e().watched }}
    >
      <div class="relative aspect-[2/1] overflow-hidden rounded-[12px]">
        <Art
          sources={[e().title.backdropUrl, e().title.posterUrl]}
          title={e().title.title}
        />
        <Show when={props.when}>
          {(text) => (
            <span class={`absolute top-2 left-2 ${chip}`}>{text()}</span>
          )}
        </Show>
        <Show when={kind()}>
          {(text) => (
            <span
              class="absolute top-2 right-2 rounded-full px-2 py-0.5 text-xs font-semibold"
              classList={{
                'bg-accent text-on-accent': e().kind === 'premiere',
                'bg-ink text-paper': e().kind === 'finale',
              }}
            >
              {text()}
            </span>
          )}
        </Show>
      </div>
      <p class="mt-2 truncate text-sm font-semibold">{e().title.title}</p>
      <p class="truncate text-xs text-muted">
        {[shortCode(e().season, e().number), e().episodeName]
          .filter(Boolean)
          .join(' · ')}
      </p>
      <Show when={meta()}>
        <p class="truncate text-xs text-muted">{meta()}</p>
      </Show>
    </Link>
  )
}
