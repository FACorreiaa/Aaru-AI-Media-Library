import { For, Show, createEffect, createSignal, on } from 'solid-js'
import { buttonVariants } from '~/components/ui'
import { viewerRegion } from '../lib/discover/onAir'
import type { MediaKind } from '../lib/library/model'
import { loadWatch } from '../lib/title/watchServer'
import { asksWhereToWatch, watchGroups } from '../lib/title/watch'
import type { TitleWatch as Places } from '../lib/title/watch'

// CAT-014: the title room's "Where to watch". Read in the browser after the room shows, for the
// region the browser's language names (sent per request, never stored). Nothing to show, a kind
// that is not watched and a failed read all leave the section out. Aaru plays nothing: "All
// options" opens TMDB's page.

export function TitleWatch(props: { titleId: string; kind: MediaKind }) {
  const [places, setPlaces] = createSignal<Places | null>(null)
  createEffect(
    on(
      () => [props.titleId, props.kind] as const,
      ([titleId, kind]) => {
        setPlaces(null)
        const region = viewerRegion(navigator.language)
        if (!asksWhereToWatch(kind, region)) return
        loadWatch({ data: { titleId, region } })
          .then((found) => {
            // A page that moved on to another title ignores a late answer for the last one.
            if (titleId === props.titleId) setPlaces(found)
          })
          .catch(() => undefined)
      },
    ),
  )
  const groups = () => watchGroups(places())

  return (
    <Show when={groups().length > 0}>
      <section aria-labelledby="where-to-watch">
        <div class="flex items-baseline justify-between gap-4">
          <h2 id="where-to-watch" class="eyebrow">
            Where to watch
          </h2>
          <Show when={places()?.link}>
            {(href) => (
              <a
                href={href()}
                rel="noopener"
                target="_blank"
                class={buttonVariants({ variant: 'outline', size: 'sm' })}
              >
                All options
                <span class="sr-only"> on TMDB, in a new tab</span>
              </a>
            )}
          </Show>
        </div>
        <dl class="mt-3 space-y-3">
          <For each={groups()}>
            {(group) => (
              <div>
                <dt class="text-xs font-semibold text-muted">{group.label}</dt>
                <dd class="mt-1.5">
                  <ul class="flex flex-wrap gap-2">
                    <For each={group.services}>
                      {(service) => (
                        <li class="flex items-center gap-2 rounded-full border border-line px-2.5 py-1 text-sm">
                          <Show when={service.logoUrl}>
                            {(src) => (
                              <img
                                src={src()}
                                alt=""
                                width="20"
                                height="20"
                                loading="lazy"
                                class="size-5 rounded"
                              />
                            )}
                          </Show>
                          {service.name}
                        </li>
                      )}
                    </For>
                  </ul>
                </dd>
              </div>
            )}
          </For>
        </dl>
        <p class="mt-3 text-xs text-muted">Streaming data from JustWatch</p>
      </section>
    </Show>
  )
}
