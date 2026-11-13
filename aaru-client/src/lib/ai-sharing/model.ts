import type { components } from '../api/schema'

// PRV-002 on the web: AI sharing, a user's yes or no to Aaru sending their data to its AI
// provider. The rule is the server's (403 `ai_sharing_required`); this is what the web shows and
// when it asks. The words match the Apple apps' and `docs/privacy.md`.

export type AiSharingState = components['schemas']['AISharing']['state']

/** What the disclosure says, the same on the first run, the full-screen ask, the in-place ask
 * and Settings. */
export const AI_SHARING = {
  title: 'Let Aaru use AI with your data?',
  lead: 'The owl, capture and @aaru in groups are answered by an AI model from Anthropic. If you allow it, Aaru sends Anthropic:',
  sent: [
    'What you ask Aaru, typed or spoken, with the screen you are on and your time zone, and the files, pictures and long pastes you attach.',
    'Text and pictures you send to capture.',
    'What Aaru reads from your account to answer: titles in your library with their status, progress and rating, your lists, stats, favorites, listens and followed sports.',
    "In a group, your messages among a channel's last 30 when someone tags @aaru.",
  ],
  use: "Anthropic uses it to write Aaru's answer and does not train on it. Aaru does not sell it or use it for ads. If you don't allow it, these features stay off and the rest of Aaru works the same. You can change this in Settings.",
  off: "Turning this off stops Aaru sending anything new to Anthropic. Chats you already had stay until you delete them, below or from the owl's History.",
} as const

/** The server's code when a route would send data to the AI provider without a yes. */
export const AI_SHARING_REQUIRED = 'ai_sharing_required'

/**
 * Whether to ask full screen when the app opens: an account that is past the first run and has
 * never answered. Not in the tab where the first run just ended (Skip leaves the answer unset;
 * the next visit asks), and never on a guess: no answer from the server is no ask.
 */
export function asksOnOpen(session: {
  onboardingPending?: boolean
  aiSharing?: AiSharingState
  firstRunEndedHere?: boolean
}): boolean {
  return (
    session.aiSharing === 'unanswered' &&
    !session.onboardingPending &&
    !session.firstRunEndedHere
  )
}

/** Whether a group message tags @aaru, by the server's rule: not inside a word or an address. */
export function tagsAaru(body: string): boolean {
  return /(?<![A-Za-z0-9_])@aaru(?![A-Za-z0-9_])/i.test(body)
}

/** Where the full-screen ask sends you once answered, never back into itself. */
export function askNext(next: string): string {
  return next === '/app/ai-sharing' || next.startsWith('/app/ai-sharing?')
    ? '/app'
    : next
}
