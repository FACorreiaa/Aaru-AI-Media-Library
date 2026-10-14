import { For } from 'solid-js'

/** Import sources in the order CLAUDE.md applies them. Vendors are sources, not domain terms. */
export const IMPORT_SOURCES = [
  'Trakt',
  'IMDb',
  'Letterboxd',
  'Goodreads',
  'Pogdesign CAT',
  'TV Time',
  'MyAnimeList',
  'AniList',
] as const

export function ImportSources(props: { sources?: readonly string[] }) {
  return (
    <ul class="flex flex-wrap gap-2.5" aria-label="Import sources">
      <For each={props.sources ?? IMPORT_SOURCES}>
        {(source) => (
          <li class="rounded-full border border-line bg-paper px-4 py-2 text-sm font-medium tracking-tight text-ink">
            {source}
          </li>
        )}
      </For>
    </ul>
  )
}
