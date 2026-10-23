import { Link } from '@tanstack/solid-router'
import { For, Show } from 'solid-js'
import { kindOf } from '../lib/library/model'
import { favoriteRows } from '../lib/favorites/model'
import type { Favorites } from '../lib/favorites/model'
import { Poster } from './Poster'

/**
 * FAV-001: a person's top 10s, one numbered row of covers per kind they filled. On your own
 * profile it links to Settings to edit them; on a friend's it only shows them.
 */
export function FavoritesRows(props: {
  favorites: Favorites | undefined
  /** Your own profile: an Edit link, and a line inviting you to pick some when there are none. */
  own?: boolean
}) {
  const rows = () => favoriteRows(props.favorites)
  return (
    <Show when={props.own || rows().length > 0}>
      <section class="mt-10" aria-labelledby="favorites-heading">
        <div class="flex items-baseline gap-3">
          <h2
            id="favorites-heading"
            class="font-display text-2xl font-medium tracking-tight"
          >
            Favorites
          </h2>
          <Show when={props.own}>
            <Link
              to="/app/settings/account"
              hash="favorites"
              class="text-sm font-semibold text-accent hover:underline"
            >
              Edit
            </Link>
          </Show>
        </div>
        <Show
          when={rows().length > 0}
          fallback={
            <p class="mt-2 text-sm text-muted">
              Pick up to 10 favorite films, shows, anime, manga, books and
              albums in Settings.
            </p>
          }
        >
          <For each={rows()}>
            {(row) => (
              <div>
                <h3 class="mt-6 text-sm font-semibold">{row.label}</h3>
                <ol class="mt-3 flex gap-4 overflow-x-auto pb-2 md:flex-wrap md:overflow-visible">
                  <For each={row.titles}>
                    {(title, index) => (
                      <li class="w-24 shrink-0">
                        <Poster
                          url={title.posterUrl}
                          kind={kindOf(title.type, title.isAnime)}
                          frame
                        />
                        <p class="mt-2 line-clamp-2 text-sm leading-snug font-medium">
                          <span class="text-muted tabular-nums">
                            {index() + 1}.
                          </span>{' '}
                          {title.title}
                        </p>
                      </li>
                    )}
                  </For>
                </ol>
              </div>
            )}
          </For>
        </Show>
      </section>
    </Show>
  )
}
