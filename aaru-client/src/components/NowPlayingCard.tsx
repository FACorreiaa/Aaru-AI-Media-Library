import { Link } from '@tanstack/solid-router'
import { For, Match, Show, Switch, createSignal } from 'solid-js'
import type { JSX } from 'solid-js'
import {
  eyebrow,
  itemLine,
  progress,
  serviceLabel,
  timeLabel,
} from '../lib/nowplaying/model'
import type { NowPlayingItem, NowPlayingKind } from '../lib/nowplaying/model'
import { Art } from './HomeRows'
import { Badge, Button, buttonVariants } from '~/components/ui'

// VIEWS.md `NowPlayingCard` (DESIGN.md §15, SCR-008, SCR-009): everything playing now, across
// the top of the Field, in the server's order. The first item gets the full card: art, the
// episode or artist, a bar and "17m left", which a tap flips to "Ends at 10:12 PM". Anything
// else playing at once (a film in another tab, a YouTube video, a track) is a compact row
// under it, with art in its own shape: a 2:3 poster, a 16:9 thumbnail, a square cover. Values
// refresh with the poll and a half-minute clock; nothing animates (Mindspace).
export function NowPlayingCard(props: {
  items: NowPlayingItem[]
  now: Date
  busy: boolean
  onWatched?: () => void
  timeZone?: string
}) {
  const [showEnd, setShowEnd] = createSignal(false)
  const lead = () => props.items[0]
  const rest = () => props.items.slice(1)
  const itemId = () => lead().libraryItemId
  const fraction = () => progress(lead(), props.now)
  const time = () =>
    timeLabel(lead(), props.now, showEnd(), undefined, props.timeZone)

  return (
    <section class="mt-8" aria-labelledby="now-playing">
      <article class="edge-lit overflow-hidden rounded-card bg-surface">
        <div class="md:grid md:grid-cols-[minmax(0,2fr)_minmax(0,3fr)]">
          <div class="relative aspect-[21/9] md:aspect-auto md:min-h-48">
            <LeadArt item={lead()} />
            <span class="veil absolute inset-x-0 bottom-0 h-1/3 md:hidden" />
          </div>
          <div class="flex min-w-0 flex-col p-5 md:p-6">
            <h2 id="now-playing" class="eyebrow">
              {eyebrow(lead())}
            </h2>
            <h3 class="mt-2 line-clamp-2 font-display text-3xl leading-tight font-medium text-balance">
              <ItemLink item={lead()} class="hover:text-accent">
                {lead().name}
              </ItemLink>
            </h3>
            <Show when={lead().subtitle}>
              {(line) => (
                <p class="mt-1 text-sm font-medium tabular-nums">{line()}</p>
              )}
            </Show>

            <Show when={fraction() !== null}>
              <div class="mt-4 flex items-center gap-3">
                <Bar item={lead()} fraction={fraction() ?? 0} class="h-1.5" />
                <Button
                  variant="ghost"
                  size="bare"
                  class="shrink-0 font-normal tabular-nums"
                  disabled={lead().state === 'paused'}
                  onClick={() => setShowEnd((on) => !on)}
                  aria-label={
                    showEnd() ? 'Show time left' : 'Show when it ends'
                  }
                >
                  {time()}
                </Button>
              </div>
            </Show>

            <Switch>
              <Match when={itemId()}>
                {(id) => (
                  <div class="mt-auto flex flex-wrap gap-2 pt-5">
                    <Show when={props.onWatched && lead().episode}>
                      <Button
                        variant="default"
                        disabled={props.busy}
                        onClick={() => props.onWatched?.()}
                        aria-label={`Mark ${lead().name} ${lead().subtitle ?? ''} watched`}
                      >
                        Mark watched
                      </Button>
                    </Show>
                    <Link
                      to="/app/title/$id"
                      params={{ id: id() }}
                      class={buttonVariants({ variant: 'outline' })}
                    >
                      Open
                    </Link>
                  </div>
                )}
              </Match>
              <Match when={lead().originUrl}>
                {(url) => (
                  <div class="mt-auto flex flex-wrap gap-2 pt-5">
                    <a
                      href={url()}
                      target="_blank"
                      rel="noopener noreferrer"
                      class={buttonVariants({ variant: 'outline' })}
                      aria-label={`Open ${lead().name} in ${serviceLabel(lead())}`}
                    >
                      Open
                    </a>
                  </div>
                )}
              </Match>
            </Switch>
          </div>
        </div>

        <Show when={rest().length > 0}>
          <ul
            class="divide-y divide-line border-t border-line"
            aria-label="Also playing"
          >
            <For each={rest()}>
              {(item) => <PlayingRow item={item} now={props.now} />}
            </For>
          </ul>
        </Show>
      </article>
    </section>
  )
}

/** The lead's art: a backdrop or poster for a library title, the thumbnail for a video, and a
 * track's square cover whole on a quiet ground, never cropped to the card's width. */
function LeadArt(props: { item: NowPlayingItem }) {
  const title = () => props.item.title
  return (
    <Switch
      fallback={
        <span class="absolute inset-0">
          <Art
            sources={[
              title()?.backdropUrl,
              title()?.posterUrl,
              props.item.artworkUrl,
            ]}
            title={props.item.name}
          />
        </span>
      }
    >
      <Match when={props.item.kind === 'video'}>
        <span class="absolute inset-0">
          <Art sources={[props.item.artworkUrl]} title={props.item.name} />
        </span>
      </Match>
      <Match when={props.item.kind === 'track'}>
        <span class="absolute inset-0 flex items-center justify-center bg-linear-135 from-accent/20 to-gold/20 p-4 md:p-6">
          <span class="aspect-square h-full overflow-hidden rounded-field">
            <Art sources={[props.item.artworkUrl]} title={props.item.name} />
          </span>
        </span>
      </Match>
    </Switch>
  )
}

/** Anything else playing at once: art, name, what and where, and a bar while its length is known.
 * The whole row is the link. */
function PlayingRow(props: { item: NowPlayingItem; now: Date }) {
  const fraction = () => progress(props.item, props.now)
  return (
    <li class="relative flex items-center gap-3 px-5 py-3 md:px-6">
      <Thumb item={props.item} />
      <div class="min-w-0 flex-1">
        <p class="truncate text-sm font-medium">
          <ItemLink
            item={props.item}
            class="after:absolute after:inset-0 hover:text-accent"
          >
            {props.item.name}
          </ItemLink>
        </p>
        <p class="flex min-w-0 items-center gap-1.5 text-xs text-muted">
          <KindGlyph kind={props.item.kind} class="size-3.5 shrink-0" />
          <span class="sr-only">{KIND_LABELS[props.item.kind]}: </span>
          <span class="truncate">{itemLine(props.item)}</span>
        </p>
        <Show when={fraction() !== null}>
          <div class="mt-2 flex items-center gap-3">
            <Bar item={props.item} fraction={fraction() ?? 0} class="h-1" />
            <span class="shrink-0 text-xs text-muted tabular-nums">
              {timeLabel(props.item, props.now, false)}
            </span>
          </div>
        </Show>
      </div>
      <Show when={props.item.state === 'paused'}>
        <Badge variant="soft" size="xs">
          Paused
        </Badge>
      </Show>
    </li>
  )
}

const KIND_LABELS: Record<NowPlayingKind, string> = {
  episode: 'Episode',
  movie: 'Film',
  track: 'Track',
  video: 'Video',
}

/** A row's art at a fixed width in its own shape; the kind's glyph while there is none. */
const THUMB_SHAPES: Record<NowPlayingKind, string> = {
  episode: 'w-10 aspect-[2/3]',
  movie: 'w-10 aspect-[2/3]',
  track: 'w-12 aspect-square',
  video: 'w-20 aspect-video',
}

function Thumb(props: { item: NowPlayingItem }) {
  const [failed, setFailed] = createSignal(false)
  const url = () =>
    failed()
      ? undefined
      : (props.item.artworkUrl ?? props.item.title?.posterUrl)
  return (
    <span
      class={`grid shrink-0 place-items-center overflow-hidden rounded-thumb bg-ink/10 text-muted ${THUMB_SHAPES[props.item.kind]}`}
    >
      <Show
        when={url()}
        keyed
        fallback={<KindGlyph kind={props.item.kind} class="size-5" />}
      >
        {(src) => (
          <img
            src={src}
            alt=""
            loading="lazy"
            decoding="async"
            class="h-full w-full object-cover"
            onError={() => setFailed(true)}
          />
        )}
      </Show>
    </span>
  )
}

function Bar(props: { item: NowPlayingItem; fraction: number; class: string }) {
  return (
    <div
      class={`flex-1 overflow-hidden rounded-full bg-line ${props.class}`}
      role="progressbar"
      aria-label={
        props.item.kind === 'track' ? 'Listened so far' : 'Watched so far'
      }
      aria-valuemin="0"
      aria-valuemax="100"
      aria-valuenow={Math.round(props.fraction * 100)}
    >
      <div
        class="h-full rounded-full bg-gold"
        style={{ width: `${props.fraction * 100}%` }}
      />
    </div>
  )
}

/** Where an item leads: a library title's room, else the page it plays on (a new tab), else
 * nowhere. */
function ItemLink(props: {
  item: NowPlayingItem
  class: string
  children: JSX.Element
}) {
  return (
    <Switch fallback={props.children}>
      <Match when={props.item.libraryItemId}>
        {(id) => (
          <Link to="/app/title/$id" params={{ id: id() }} class={props.class}>
            {props.children}
          </Link>
        )}
      </Match>
      <Match when={props.item.originUrl}>
        {(url) => (
          <a
            href={url()}
            target="_blank"
            rel="noopener noreferrer"
            class={props.class}
          >
            {props.children}
          </a>
        )}
      </Match>
    </Switch>
  )
}

/** The kind at a glance, in the shell's line style (24px grid, 1.75 stroke). Decorative: the
 * row names its kind to screen readers beside it. */
function KindGlyph(props: { kind: NowPlayingKind; class: string }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.75"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      class={props.class}
    >
      <Switch>
        <Match when={props.kind === 'episode'}>
          <rect x="3.5" y="5" width="17" height="12" rx="2" />
          <path d="M9 20h6" />
        </Match>
        <Match when={props.kind === 'movie'}>
          <rect x="4" y="4" width="16" height="16" rx="2" />
          <path d="M8 4v16M16 4v16M4 9h4M4 15h4M16 9h4M16 15h4" />
        </Match>
        <Match when={props.kind === 'track'}>
          <path d="M9 17.5V6l10-2v11.5" />
          <circle cx="6.5" cy="17.5" r="2.5" />
          <circle cx="16.5" cy="15.5" r="2.5" />
        </Match>
        <Match when={props.kind === 'video'}>
          <rect x="3" y="5.5" width="18" height="13" rx="3" />
          <path d="m10.5 9.5 4 2.5-4 2.5z" />
        </Match>
      </Switch>
    </svg>
  )
}
