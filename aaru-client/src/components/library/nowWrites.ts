import { createSignal } from 'solid-js'
import type { LibraryEntry } from '../../lib/library/model'
import type { NowItem } from '../../lib/library/now'
import { setEpisode, updateItem } from '../../lib/title/server'

/**
 * The next steps a Now card or row offers (APP-017): tick the next episode, move a book's page,
 * log a chapter, finish. Nothing is optimistic: each waits for the server's entry and hands it to
 * `onEntry`, so every view of the library agrees. One write per item at a time.
 */
export function createNowWrites(onEntry: (entry: LibraryEntry) => void) {
  const [pending, setPending] = createSignal<ReadonlySet<string>>(new Set())
  const [problem, setProblem] = createSignal<string | null>(null)

  async function run(id: string, write: () => Promise<LibraryEntry>) {
    if (pending().has(id)) return
    setProblem(null)
    setPending((set) => new Set(set).add(id))
    try {
      onEntry(await write())
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'That change was not saved.',
      )
    } finally {
      setPending((set) => {
        const next = new Set(set)
        next.delete(id)
        return next
      })
    }
  }

  /** The callbacks one card or row takes; `isPending` says whether its write is in flight. */
  function actions(item: NowItem) {
    const id = item.entry.id
    return {
      onTickNext: (next: { season: number; number: number }) =>
        run(id, () =>
          setEpisode({
            data: {
              id,
              season: next.season,
              episode: next.number,
              watched: true,
            },
          }),
        ),
      onPage: (page: number) =>
        run(id, () => updateItem({ data: { id, patch: { bookPage: page } } })),
      onChapter: (chapter: number) =>
        run(id, () =>
          updateItem({ data: { id, patch: { mangaChapter: chapter } } }),
        ),
      onFinish: () =>
        run(id, () =>
          updateItem({ data: { id, patch: { status: 'finished' } } }),
        ),
    }
  }

  return {
    problem,
    actions,
    isPending: (item: NowItem) => pending().has(item.entry.id),
  }
}
