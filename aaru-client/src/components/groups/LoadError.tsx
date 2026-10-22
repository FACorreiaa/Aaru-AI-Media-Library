import { useRouter } from '@tanstack/solid-router'
import { Button } from '~/components/ui'

/**
 * A group or channel that did not load (UX-064): said as a failure with Try again, never as
 * "gone", which is kept for a 404.
 */
export function LoadError(props: {
  what: string
  error: unknown
  reset?: () => void
}) {
  const router = useRouter()
  const detail = () =>
    props.error instanceof Error ? props.error.message : null
  return (
    <div class="grid flex-1 place-items-center p-8 text-center">
      <div role="alert">
        <p class="font-display text-2xl">{props.what} didn't load.</p>
        <p class="mt-2 text-sm text-muted">
          {detail() ?? 'Check your connection and try again.'}
        </p>
        <Button
          class="mt-5"
          onClick={() => {
            props.reset?.()
            void router.invalidate()
          }}
        >
          Try again
        </Button>
      </div>
    </div>
  )
}
