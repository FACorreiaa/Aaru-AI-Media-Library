import type { components } from '../api/schema'

export type Action = components['schemas']['Action']

/**
 * Who made one journaled write, for Settings → Your data → History (DESIGN.md §18): you, an
 * import, Aaru's own agent, or a connection by its token's name.
 */
export function actionBy(action: Action): string {
  switch (action.actor) {
    case 'user':
      return action.kind === 'import' ? 'An import' : 'You'
    case 'agent':
      return 'Aaru'
    case 'external_agent':
      return action.agentName ?? 'A connection'
  }
}

/** Whether History offers Undo: not for an undo itself, nor for one already undone. */
export const canUndo = (action: Action) =>
  action.kind !== 'undo' && action.undoneAt === undefined

/** "Today, 14:05", "Yesterday, 09:12", else "3 Oct, 18:40" (with the year when not this one). */
export function whenLabel(
  at: string,
  now = new Date(),
  locale?: string,
): string {
  const date = new Date(at)
  const time = date.toLocaleTimeString(locale, {
    hour: '2-digit',
    minute: '2-digit',
  })
  const startOf = (d: Date) =>
    new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
  const days = Math.round((startOf(now) - startOf(date)) / 86_400_000)
  if (days === 0) return `Today, ${time}`
  if (days === 1) return `Yesterday, ${time}`
  const day = date.toLocaleDateString(locale, {
    day: 'numeric',
    month: 'short',
    year: date.getFullYear() === now.getFullYear() ? undefined : 'numeric',
  })
  return `${day}, ${time}`
}
