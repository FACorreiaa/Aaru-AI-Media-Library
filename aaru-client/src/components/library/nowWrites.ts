import { createSignal } from 'solid-js'
import { stepMessage } from '../../lib/home/reading'
import type { ReadingStep } from '../../lib/home/reading'
import type { LibraryEntry } from '../../lib/library/model'
import type { NowItem } from '../../lib/library/now'
import { setEpisode, stepItem } from '../../lib/title/server'
import type { Ticked } from '../../lib/title/server'
import { offerUndo } from '../undo-toast'

/**
 * The next steps a Now card or row offers (APP-017): tick the next episode, move a book's page,
 * log a chapter, finish. Nothing is optimistic: each waits for the server's entry and hands it to
 * `onEntry`, so every view of the library agrees. One write per item at a time. With `onUndone`
 * (Home's Reading row), a page, chapter or finish also offers Undo; `onUndone` reloads after it.
 */
export function createNowWrites(
  onEntry: (entry: LibraryEntry) => void,
  onUndone?: () => void,
) {
  const [pending, setPending] = createSignal<ReadonlySet<string>>(new Set())
  const [problem, setProblem] = createSignal<string | null>(null)

  async function run(
    id: string,
    write: () => Promise<Ticked>,
    undo?: { name: string; step: ReadingStep },
  ) {
    if (pending().has(id)) return
    setProblem(null)
    setPending((set) => new Set(set).add(id))
    try {
      const ticked = await write()
      onEntry(ticked.entry)
      if (undo && onUndone && ticked.actionId)
        offerUndo(stepMessage(undo.name, undo.step), ticked.actionId, onUndone)
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
    const name = item.entry.title.title
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
        run(id, () => stepItem({ data: { id, patch: { bookPage: page } } }), {
          name,
          step: { page },
        }),
      onChapter: (chapter: number) =>
        run(
          id,
          () => stepItem({ data: { id, patch: { mangaChapter: chapter } } }),
          { name, step: { chapter } },
        ),
      onFinish: () =>
        run(
          id,
          () => stepItem({ data: { id, patch: { status: 'finished' } } }),
          { name, step: { finished: true } },
        ),
    }
  }

  return {
    problem,
    actions,
    isPending: (item: NowItem) => pending().has(item.entry.id),
  }
}
