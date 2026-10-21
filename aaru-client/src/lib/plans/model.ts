import type { components } from '../api/schema'

type AgentPlan = components['schemas']['AgentPlan']

/** "Expires in 3 h", "Expires in 12 min", or "Expired". */
export function expiresLabel(plan: AgentPlan, now = new Date()): string {
  const minutes = Math.floor(
    (new Date(plan.expiresAt).getTime() - now.getTime()) / 60_000,
  )
  if (minutes <= 0) return 'Expired'
  if (minutes < 60) return `Expires in ${minutes} min`
  return `Expires in ${Math.floor(minutes / 60)} h`
}

/** What a decided plan says instead of buttons. */
export function decidedLabel(plan: AgentPlan): string | null {
  switch (plan.status) {
    case 'pending':
      return null
    case 'applied':
      return 'Applied. You can undo it from your history.'
    case 'denied':
      return 'You said no. Nothing changed.'
    case 'stale':
      return 'Your library changed since, so nothing was applied.'
    case 'expired':
      return 'Expired. Nothing changed.'
  }
}

/** "3 episodes · 2 titles added", from the plan's counts. */
export function countsLine(plan: AgentPlan): string {
  const { adds, updates, removes, episodes } = plan.counts
  const plural = (n: number, noun: string) =>
    `${n} ${noun}${n === 1 ? '' : 's'}`
  return [
    episodes > 0 ? plural(episodes, 'episode') : null,
    adds > 0 ? `${plural(adds, 'title')} added` : null,
    updates > 0 ? `${plural(updates, 'item')} updated` : null,
    removes > 0 ? `${plural(removes, 'title')} removed` : null,
  ]
    .filter(Boolean)
    .join(' · ')
}
