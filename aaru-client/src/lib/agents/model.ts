import type { components } from '../api/schema'

type AgentToken = components['schemas']['AgentToken']
export type AgentKind = components['schemas']['AgentMCPKind']

/** The MCP clients Settings offers, in the order it shows them. Claude connects over OAuth. */
export const AGENT_KINDS = [
  'claude',
  'claude_code',
  'codex',
  'hermes',
  'gemini',
  'other',
] as const satisfies readonly AgentKind[]

const labels: Record<AgentToken['kind'], string> = {
  claude_code: 'Claude Code',
  codex: 'Codex',
  hermes: 'Hermes',
  gemini: 'Gemini CLI',
  other: 'Other MCP client',
  stremio: 'Stremio',
  claude: 'Claude',
  browser: 'Browser extension',
}

export const kindLabel = (kind: AgentToken['kind']) => labels[kind]

/** What a connection may do, in the words Settings uses. */
export function accessLabel(token: AgentToken): string {
  if (token.kind === 'browser') return 'Marks what you watch'
  const access = token.scopes.includes('library:write')
    ? 'Can change one item at a time'
    : 'Read only'
  return token.scopes.includes('imports:write')
    ? `${access} · can send imports`
    : access
}
