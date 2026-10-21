import { describe, expect, it } from 'vitest'
import { AGENT_KINDS, accessLabel, kindLabel } from './model'
import type { AgentToken } from './server'

const token = (overrides: Partial<AgentToken> = {}): AgentToken => ({
  id: '00000000-0000-0000-0000-000000000001',
  name: 'Laptop',
  kind: 'claude_code',
  scopes: ['library:read'],
  createdAt: '2026-10-01T00:00:00Z',
  ...overrides,
})

describe('agents model', () => {
  it('offers every MCP client, Claude first', () => {
    expect(AGENT_KINDS).toEqual([
      'claude',
      'claude_code',
      'codex',
      'hermes',
      'gemini',
      'other',
    ])
    expect(AGENT_KINDS.map(kindLabel)).toEqual([
      'Claude',
      'Claude Code',
      'Codex',
      'Hermes',
      'Gemini CLI',
      'Other MCP client',
    ])
  })

  it('says what a connection may do', () => {
    expect(accessLabel(token())).toBe('Read only')
    expect(
      accessLabel(token({ scopes: ['library:read', 'library:write'] })),
    ).toBe('Can change one item at a time')
    expect(
      accessLabel(token({ scopes: ['library:read', 'imports:write'] })),
    ).toBe('Read only · can send imports')
  })
})
