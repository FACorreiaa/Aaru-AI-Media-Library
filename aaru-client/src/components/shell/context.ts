import {
  createContext,
  createEffect,
  onCleanup,
  onMount,
  useContext,
} from 'solid-js'
import type { Accessor } from 'solid-js'
import type { AiSharingState } from '../../lib/ai-sharing/model'
import type { LibraryEntry } from '../../lib/library/model'
import type { Scope } from '../SearchPanel'

/** A page that holds the library lends it to the shell's Search, so hits read "In your library"
 * from the page's copy and an add shows on the page at once. */
export type SearchHost = {
  entries: Accessor<LibraryEntry[]>
  onAdded: (entry: LibraryEntry) => void
}

/** Where the page you came from was, for a back link that names it (UX-006). */
export type Previous = { href: string; label: string }

export type AppShellContext = {
  openSearch: (scope?: Scope) => void
  setSearchHost: (host: SearchHost | null) => void
  previous: Accessor<Previous | null>
  setMentions: (count: number) => void
  /** Opens the assistant's card (ASK-009); `listen` starts with the microphone. */
  openAssistant: (listen?: boolean) => void
  /** Opens the card and asks this at once, as if typed there. Does nothing while Aaru is off. */
  askAssistant: (question: string) => void
  /** True while the assistant answers: a button that asks it shows only then. */
  assistantAvailable: Accessor<boolean>
  /** The title a title page is showing, so a question there is about it. Null off one. */
  setAssistantTitle: (titleId: string | null) => void
  /** The user's answer to AI sharing (PRV-002). Absent when the server could not be asked. */
  aiSharing: Accessor<AiSharingState | undefined>
  /**
   * Before anything goes to the AI provider: true when the user has allowed it. If they have
   * not, the disclosure opens in place with Allow / Not now and this answers what they chose.
   */
  ensureAiSharing: () => Promise<boolean>
  /** Stores a new answer (Settings' switch). Throws when it was not saved. */
  setAiSharing: (allowed: boolean) => Promise<void>
}

export const ShellContext = createContext<AppShellContext>()

export function useAppShell(): AppShellContext {
  const shell = useContext(ShellContext)
  if (!shell) throw new Error('useAppShell outside the app shell.')
  return shell
}

/** Lends this page's library to Search while the page is mounted. */
export function useSearchHost(host: SearchHost) {
  const shell = useAppShell()
  onMount(() => shell.setSearchHost(host))
  onCleanup(() => shell.setSearchHost(null))
}

/**
 * Tells the assistant which title this page shows, while it is mounted. It follows the id: moving
 * from one title's page to another's keeps the page mounted, and the question must be about the
 * new one (ASK-011).
 */
export function useAssistantTitle(titleId: () => string | null | undefined) {
  const shell = useAppShell()
  createEffect(() => shell.setAssistantTitle(titleId() ?? null))
  onCleanup(() => shell.setAssistantTitle(null))
}
