import { For, Show } from 'solid-js'
import type { JSX } from 'solid-js'
import { APP_STORE_URL, PLAY_STORE_URL } from '../lib/site'

type Store = {
  name: string
  url: string | undefined
  class: string
  icon: () => JSX.Element
}

const stores: Store[] = [
  {
    name: 'App Store',
    url: APP_STORE_URL,
    class: 'bg-ink text-paper',
    icon: () => (
      <svg
        viewBox="0 0 24 24"
        class="h-5 w-5"
        fill="currentColor"
        aria-hidden="true"
      >
        <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701" />
      </svg>
    ),
  },
  {
    name: 'Google Play',
    url: PLAY_STORE_URL,
    class: 'border border-line bg-surface text-ink',
    icon: () => (
      <svg
        viewBox="0 0 24 24"
        class="h-[18px] w-[18px]"
        fill="currentColor"
        aria-hidden="true"
      >
        <path d="M22.018 13.298l-3.919 2.218-3.515-3.493 3.543-3.521 3.891 2.202a1.49 1.49 0 0 1 0 2.594zM1.337.924a1.486 1.486 0 0 0-.112.568v21.017c0 .217.045.419.124.6l11.155-11.087L1.337.924zm12.207 10.065l3.258-3.238L3.45.195a1.466 1.466 0 0 0-.946-.179l11.04 10.973zm0 2.067l-11 10.933c.298.036.612-.016.906-.183l13.324-7.54-3.23-3.21z" />
      </svg>
    ),
  },
]

const base =
  'inline-flex min-w-40 items-center justify-center gap-2.5 rounded-panel px-6 py-3 text-md font-semibold whitespace-nowrap'

/**
 * App Store and Google Play, at equal weight. Until a listing exists the button is plain
 * text, not a link, and the caption says so.
 */
export function StoreButtons(props: {
  class?: string
  align?: 'start' | 'center'
}) {
  const pending = stores.some((store) => !store.url)
  return (
    <div class={props.class}>
      <div
        class={`flex flex-col gap-3 sm:flex-row ${props.align === 'center' ? 'sm:justify-center' : ''}`}
      >
        <For each={stores}>
          {(store) => (
            <Show
              when={store.url}
              fallback={
                <span
                  class={`${base} ${store.class} cursor-default`}
                  aria-label={`${store.name}, coming soon`}
                >
                  {store.icon()}
                  {store.name}
                </span>
              }
            >
              {(url) => (
                <a
                  href={url()}
                  rel="noopener"
                  class={`${base} ${store.class} transition-transform hover:-translate-y-0.5 active:translate-y-0 active:scale-[0.98]`}
                >
                  {store.icon()}
                  {store.name}
                </a>
              )}
            </Show>
          )}
        </For>
      </div>
      <Show when={pending}>
        <p
          class={`mt-3 text-sm text-muted ${props.align === 'center' ? 'text-center' : ''}`}
        >
          Coming soon to the App Store and Google Play.
        </p>
      </Show>
    </div>
  )
}
