import { Link } from '@tanstack/solid-router'
import { For, Show } from 'solid-js'
import type { JSX } from 'solid-js'
import { playsLabel, topRowLines } from '../../lib/music/listening-model'
import type { TopBy } from '../../lib/music/listening-model'
import type { TopRow } from '../../lib/music/listening'

/** A square album cover, or a quiet note while the album is unknown. */
export function Cover(props: { url?: string }) {
  return (
    <Show
      when={props.url}
      fallback={
        <span
          aria-hidden="true"
          class="grid size-10 shrink-0 place-items-center rounded-md bg-surface text-muted"
        >
          ♪
        </span>
      }
    >
      {(url) => (
        <img
          src={url()}
          alt=""
          loading="lazy"
          decoding="async"
          class="size-10 shrink-0 rounded-md bg-surface object-cover"
        />
      )}
    </Show>
  )
}

/** Opens the album when it is in the catalog; otherwise the row is plain. */
export function AlbumLink(props: {
  titleId?: string
  class: string
  children: JSX.Element
}) {
  return (
    <Show
      when={props.titleId}
      fallback={<div class={props.class}>{props.children}</div>}
    >
      {(id) => (
        <Link
          to="/app/title/$id"
          params={{ id: id() }}
          class={`${props.class} rounded-lg hover:bg-surface`}
        >
          {props.children}
        </Link>
      )}
    </Show>
  )
}

// MUS-008: a ranked list of artists, tracks or albums with their plays.
export function TopList(props: { rows: TopRow[]; by: TopBy }) {
  return (
    <ol class="divide-y divide-line">
      <For each={props.rows}>
        {(row, i) => {
          const lines = () => topRowLines(row, props.by)
          return (
            <li>
              <AlbumLink
                titleId={row.albumRef?.titleId}
                class="flex items-center gap-4 py-3"
              >
                <span class="w-5 text-right font-display text-lg text-muted tabular-nums">
                  {i() + 1}
                </span>
                <Cover url={row.coverUrl} />
                <span class="min-w-0 flex-1">
                  <span class="block truncate font-medium">{lines()[0]}</span>
                  <Show when={lines()[1]}>
                    {(second) => (
                      <span class="block truncate text-sm text-muted">
                        {second()}
                      </span>
                    )}
                  </Show>
                </span>
                <span class="shrink-0 text-sm text-muted tabular-nums">
                  {playsLabel(row.count)}
                </span>
              </AlbumLink>
            </li>
          )
        }}
      </For>
    </ol>
  )
}
