import { Button } from '~/components/ui'
import { AI_SHARING } from '../../lib/ai-sharing/model'
import { AiSharingDisclosure } from '../ai-sharing/AiSharingDisclosure'
import { StepFrame } from './StepFrame'
import type { Problem } from './StepFrame'

// PRV-002 in the first run (DESIGN.md §0a): what Aaru would send Anthropic, and a yes or a no of
// equal weight. Either answer goes on; the flow's Skip leaves it unanswered, which sends nothing.

export function AiSharingStep(props: {
  onAnswer: (allowed: boolean) => void
  busy: boolean
  problem: Problem | null
}) {
  return (
    <StepFrame
      title={AI_SHARING.title}
      problem={props.problem}
      footer={
        <div class="grid grid-cols-2 gap-3">
          <Button
            variant="outline"
            size="lg"
            disabled={props.busy}
            onClick={() => props.onAnswer(false)}
          >
            Don't allow
          </Button>
          <Button
            size="lg"
            disabled={props.busy}
            aria-busy={props.busy || undefined}
            onClick={() => props.onAnswer(true)}
          >
            Allow
          </Button>
        </div>
      }
    >
      <AiSharingDisclosure class="mt-6 max-w-xl" />
    </StepFrame>
  )
}
