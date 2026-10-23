import type { Entitlement } from './server'

const day = new Intl.DateTimeFormat('en', { month: 'long', day: 'numeric' })

/** Settings → Account's Plus line: "Active · renews 3 November", or the month's captures. */
export function plusLine(entitlement: Entitlement): string {
  if (entitlement.plus) {
    return entitlement.expiresAt
      ? `Active · renews ${day.format(new Date(entitlement.expiresAt))}`
      : 'Active'
  }
  const { used, limit, resetsAt } = entitlement.capture
  const count = limit === undefined ? `${used}` : `${used} of ${limit}`
  return `Not subscribed · ${count} captures this month, more on ${day.format(new Date(resetsAt))}`
}
