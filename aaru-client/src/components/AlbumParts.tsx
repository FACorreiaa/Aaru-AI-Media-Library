import { For, Show, createMemo } from 'solid-js'
import type { JSX } from 'solid-js'
import {
  albumSummary,
  discs,
  largeCover,
  trackLength,
} from '../lib/title/album'
import type { AlbumTrack } from '../lib/title/album'
import { Poster } from './Poster'
import { Badge } from '~/components/ui'

// MUS-001 on the web: an album's Title room. The cover is the room; the chrome stays out of its
// way. Read only: no playback, no ticks, no progress.

/** A big square cover, the name, the artist, the year and up to five genres. `children` are
 * the room's actions (Add to list, Discuss). */
export function AlbumHeader(props: {
  name: string
  posterUrl?: string
  byline?: string
  year?: number
  genres?: string[]
  children?: JSX.Element
}) {
  return (
    <section class="mt-4 flex flex-col gap-6 sm:flex-row sm:items-end">
      <Poster
        url={largeCover(props.posterUrl)}
        kind="album"
        class="w-56 shrink-0 sm:w-60 md:w-72"
      />
      <div class="min-w-0">
        <h1 class="font-display text-3xl leading-tight font-medium tracking-tight text-balance md:text-4xl">
          {props.name}
        </h1>
        <Show when={props.byline}>
          <p class="mt-1 text-lg text-muted">{props.byline}</p>
        </Show>
        <Show when={props.year || (props.genres?.length ?? 0) > 0}>
          <div class="mt-3 flex flex-wrap items-center gap-2">
            <Show when={props.year}>
              <span class="mr-1 text-sm text-muted tabular-nums">
                {props.year}
              </span>
            </Show>
            <For each={props.genres ?? []}>
              {(genre) => <Badge variant="soft">{genre}</Badge>}
            </For>
          </div>
        </Show>
        {props.children}
      </div>
    </section>
  )
}

/** Number, name and length per track; a "Disc 2" heading only on a multi-disc album. Without a
 * tracklist yet, one quiet line: it is not an error. */
export function Tracklist(props: { tracks?: AlbumTrack[] }) {
  const tracks = () => props.tracks ?? []
  const grouped = createMemo(() => discs(tracks()))
  return (
    <section class="mt-10" aria-labelledby="tracklist">
      <div class="flex items-baseline justify-between gap-4">
        <h2 id="tracklist" class="font-display text-xl font-medium">
          Tracklist
        </h2>
        <Show when={tracks().length > 0}>
          <p class="text-sm text-muted tabular-nums">
            {albumSummary(tracks())}
          </p>
        </Show>
      </div>
      <Show
        when={tracks().length > 0}
        fallback={
          <p class="mt-3 text-sm text-muted">Tracklist not available yet</p>
        }
      >
        <For each={grouped()}>
          {(disc, i) => (
            <div classList={{ 'mt-6': i() > 0, 'mt-2': i() === 0 }}>
              <Show when={grouped().length > 1}>
                <h3 class="pb-1 text-sm font-medium text-muted">
                  Disc {disc.number}
                </h3>
              </Show>
              <ol class="divide-y divide-line">
                <For each={disc.tracks}>
                  {(track) => (
                    <li class="flex items-baseline gap-4 py-2.5">
                      <span
                        class="w-6 shrink-0 text-right text-sm text-muted tabular-nums"
                        aria-hidden="true"
                      >
                        {track.position}
                      </span>
                      <span class="min-w-0 flex-1">{track.name}</span>
                      <span class="shrink-0 text-sm text-muted tabular-nums">
                        {trackLength(track.lengthMs)}
                      </span>
                    </li>
                  )}
                </For>
              </ol>
            </div>
          )}
        </For>
      </Show>
    </section>
  )
}
