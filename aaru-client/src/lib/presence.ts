import { createMemo } from 'solid-js'
import type { Accessor } from 'solid-js'

/**
 * WEB-011: a dialog opened for one thing (an episode, a title, a day) keeps that thing after it
 * closes, so Kobalte can play the exit before it unmounts the content.
 *
 *   const [episode, setEpisode] = createSignal<Episode | null>(null)
 *   const shown = lastShown(episode)
 *   <Show when={shown()}>{(e) => <EpisodeSheet open={episode() !== null} episode={e()} … />}</Show>
 */
export function lastShown<T>(source: Accessor<T | null | undefined>) {
  return createMemo<T | null>((previous) => source() ?? previous, null)
}
