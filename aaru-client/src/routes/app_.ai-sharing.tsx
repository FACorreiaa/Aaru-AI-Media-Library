import {
  createFileRoute,
  redirect,
  useNavigate,
  useRouter,
} from '@tanstack/solid-router'
import { createSignal } from 'solid-js'
import { AiSharingStep } from '../components/onboarding/AiSharingStep'
import type { Problem } from '../components/onboarding/StepFrame'
import { askNext } from '../lib/ai-sharing/model'
import { setAiSharing } from '../lib/ai-sharing/server'
import { aiSharingAnswered } from '../lib/ai-sharing/session'
import { safeNext } from '../lib/oauth/model'
import { optionalString } from '../lib/search-params'
import { requireSession } from '../lib/session/query'

// PRV-002: the AI sharing question for an account that is past the first run and never answered
// it, full screen and outside the app shell, at `/app/ai-sharing?next=…`. It is the first run's
// own screen with no Skip: Allow or Don't allow, then on to `next`. Once answered this address
// sends you straight on.
export const Route = createFileRoute('/app_/ai-sharing')({
  head: () => ({ meta: [{ title: 'AI data sharing · Aaru' }] }),
  validateSearch: (search): { next?: string } => ({
    next: optionalString(search.next),
  }),
  beforeLoad: async ({ search, location, context }) => {
    const session = await requireSession(context.queryClient, location.href)
    const next = askNext(safeNext(search.next))
    if (session.aiSharing !== 'unanswered') throw redirect({ href: next })
    return { next }
  },
  component: AiSharingAsk,
})

function AiSharingAsk() {
  const context = Route.useRouteContext()
  const router = useRouter()
  const navigate = useNavigate()
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<Problem | null>(null)

  async function answer(allowed: boolean) {
    setBusy(true)
    setProblem(null)
    try {
      const state = await setAiSharing({ data: { allowed } })
      aiSharingAnswered(router.options.context.queryClient, state)
      await navigate({ href: context().next, replace: true })
    } catch (error) {
      setProblem({
        message:
          error instanceof Error && error.message
            ? error.message
            : 'Your answer was not saved.',
        retry: () => void answer(allowed),
      })
    } finally {
      setBusy(false)
    }
  }

  return (
    <main class="min-h-dvh bg-paper text-ink">
      <div class="mx-auto w-full max-w-6xl px-4 pt-16 md:px-8">
        <AiSharingStep
          onAnswer={(allowed) => void answer(allowed)}
          busy={busy()}
          problem={problem()}
        />
      </div>
    </main>
  )
}
