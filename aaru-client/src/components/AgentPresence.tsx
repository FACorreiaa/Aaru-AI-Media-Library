import { OwlMark } from './Brand'

// DESIGN.md "Brand": the owl is Aaru's quiet presence while it works, a slow breath and never a
// spinner. It says "working" only when something is: an import being read or matched. Still
// under reduced motion (the breath lives in a no-preference media query).
export function AgentPresence(props: { label: string; class?: string }) {
  return (
    <span
      role="status"
      class={`inline-flex items-center gap-2 text-sm text-muted ${props.class ?? ''}`}
    >
      <OwlMark breathing />
      {props.label}
    </span>
  )
}
