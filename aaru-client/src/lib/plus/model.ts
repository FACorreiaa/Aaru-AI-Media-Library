import type { Entitlement } from './server'

const day = new Intl.DateTimeFormat('en', { month: 'long', day: 'numeric' })

/** Settings → Account's Plus line: "Active · renews 3 November". */
export function plusLine(entitlement: Entitlement): string {
  return entitlement.expiresAt
    ? `Active · renews ${day.format(new Date(entitlement.expiresAt))}`
    : 'Active'
}
