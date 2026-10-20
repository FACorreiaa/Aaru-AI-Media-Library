import { describe, expect, it } from 'vitest'
import { countsLine, decidedLabel, expiresLabel } from './model'
import type { AgentPlan } from './server'

const plan = (overrides: Partial<AgentPlan> = {}): AgentPlan => ({
  id: '00000000-0000-0000-0000-000000000001',
  status: 'pending',
  agentName: 'Claude Code',
  summary: 'Marked 3 episodes of Andor watched',
  changes: [],
  counts: { adds: 0, updates: 0, removes: 0, episodes: 3 },
  createdAt: '2026-10-20T10:00:00Z',
  expiresAt: '2026-10-21T10:00:00Z',
  ...overrides,
})

describe('plans model', () => {
  it('says when a plan expires', () => {
    expect(expiresLabel(plan(), new Date('2026-10-21T07:00:00Z'))).toBe(
      'Expires in 3 h',
    )
    expect(expiresLabel(plan(), new Date('2026-10-21T09:48:00Z'))).toBe(
      'Expires in 12 min',
    )
    expect(expiresLabel(plan(), new Date('2026-10-21T10:00:00Z'))).toBe(
      'Expired',
    )
  })

  it('sums up what a plan changes', () => {
    expect(countsLine(plan())).toBe('3 episodes')
    expect(
      countsLine(
        plan({ counts: { adds: 1, updates: 2, removes: 1, episodes: 0 } }),
      ),
    ).toBe('1 title added · 2 items updated · 1 title removed')
  })

  it('explains a decided plan', () => {
    expect(decidedLabel(plan())).toBeNull()
    expect(decidedLabel(plan({ status: 'stale' }))).toBe(
      'Your library changed since, so nothing was applied.',
    )
  })
})
