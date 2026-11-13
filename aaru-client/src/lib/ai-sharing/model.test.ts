import { describe, expect, it } from 'vitest'
import privacy from '../../../../docs/privacy.md?raw'
import { AI_SHARING, askNext, asksOnOpen, tagsAaru } from './model'

describe('asksOnOpen', () => {
  it('asks an account past the first run that never answered', () => {
    expect(asksOnOpen({ aiSharing: 'unanswered' })).toBe(true)
    expect(
      asksOnOpen({ aiSharing: 'unanswered', onboardingPending: false }),
    ).toBe(true)
  })

  it('leaves a new account to the first run, which asks', () => {
    expect(
      asksOnOpen({ aiSharing: 'unanswered', onboardingPending: true }),
    ).toBe(false)
  })

  it('does not ask straight after the first run ended in this tab', () => {
    expect(
      asksOnOpen({ aiSharing: 'unanswered', firstRunEndedHere: true }),
    ).toBe(false)
  })

  it('never asks again once answered, either way', () => {
    expect(asksOnOpen({ aiSharing: 'allowed' })).toBe(false)
    expect(asksOnOpen({ aiSharing: 'declined' })).toBe(false)
  })

  it('does not ask on a guess when the server could not be read', () => {
    expect(asksOnOpen({})).toBe(false)
  })
})

describe('tagsAaru', () => {
  it('finds the tag anywhere in a message, in any case', () => {
    expect(tagsAaru('@aaru what next?')).toBe(true)
    expect(tagsAaru('so, @Aaru, what next?')).toBe(true)
    expect(tagsAaru('what next\n@aaru')).toBe(true)
  })

  it('ignores a tag inside a word, a longer handle or an address', () => {
    expect(tagsAaru('mail me@aaru.example')).toBe(false)
    expect(tagsAaru('@aaru_fan said so')).toBe(false)
    expect(tagsAaru('ask aaru')).toBe(false)
  })
})

describe('askNext', () => {
  it('never sends you back into the ask', () => {
    expect(askNext('/app/ai-sharing')).toBe('/app')
    expect(askNext('/app/ai-sharing?next=%2Fapp')).toBe('/app')
    expect(askNext('/app/library')).toBe('/app/library')
  })
})

describe('the disclosure', () => {
  it('names who receives the data and links nothing the policy does not say', () => {
    expect(AI_SHARING.lead).toContain('Anthropic')
    expect(AI_SHARING.sent).toHaveLength(4)
    // The policy is the source: it says the same about training, selling and ads.
    expect(privacy).toContain('does not train on it')
    expect(privacy).toContain('does not sell or rent data')
    expect(privacy).toContain('Let Aaru use AI with your data?')
  })
})
