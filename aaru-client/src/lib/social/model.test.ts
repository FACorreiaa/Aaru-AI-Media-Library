import { describe, expect, it } from 'vitest'
import {
  handleProblem,
  monogram,
  normalizeHandle,
  personLabel,
  requestOutcome,
} from './model'

const ana = { userId: '00000000-0000-0000-0000-000000000001', handle: 'ana' }

describe('social model', () => {
  it('normalizes a typed handle the way the server stores it', () => {
    expect(normalizeHandle('  @Ana_B ')).toBe('ana_b')
    expect(normalizeHandle('kai')).toBe('kai')
  })

  it('explains a malformed handle before a round trip', () => {
    expect(handleProblem('')).toBe('Enter a handle.')
    expect(handleProblem('ab')).toBe(
      'Use 3–20 letters, numbers or underscores.',
    )
    expect(handleProblem('has space')).not.toBeNull()
    expect(handleProblem('@Ana_B')).toBeNull()
  })

  it('labels a person by name and handle', () => {
    expect(personLabel(ana)).toBe('@ana')
    expect(personLabel({ ...ana, displayName: 'Ana Silva' })).toBe(
      'Ana Silva · @ana',
    )
  })

  it('makes a monogram from the name, else the handle', () => {
    expect(monogram(ana)).toBe('A')
    expect(monogram({ ...ana, displayName: 'kai mori' })).toBe('KM')
    expect(monogram({ ...ana, displayName: 'Zoë' })).toBe('Z')
  })

  it('says whether a request was sent or became a friendship', () => {
    expect(requestOutcome(ana, 'outgoing')).toBe('Request sent to @ana.')
    expect(requestOutcome(ana, 'friend')).toBe('You and @ana are friends.')
  })
})
