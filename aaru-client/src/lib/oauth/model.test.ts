import { describe, expect, it } from 'vitest'
import { safeNext } from './model'

describe('safeNext', () => {
  it('keeps Aaru pages and the consent page', () => {
    expect(safeNext('/oauth/consent?request=abc')).toBe(
      '/oauth/consent?request=abc',
    )
    expect(safeNext('/app/settings')).toBe('/app/settings')
    expect(safeNext('/connect/extension?name=Firefox')).toBe(
      '/connect/extension?name=Firefox',
    )
  })

  it('refuses anything that could leave Aaru', () => {
    for (const next of [
      '//evil.example',
      'https://evil.example',
      '/\\evil.example',
      'javascript:alert(1)',
      '/privacy',
      undefined,
      42,
    ])
      expect(safeNext(next)).toBe('/app')
  })
})
