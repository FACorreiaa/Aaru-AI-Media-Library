import { describe, expect, it } from 'vitest'
import { safeNext } from './model'

describe('safeNext', () => {
  it('keeps Aaru pages and the consent page', () => {
    expect(safeNext('/oauth/consent?request=abc')).toBe(
      '/oauth/consent?request=abc',
    )
    expect(safeNext('/app/settings')).toBe('/app/settings')
    expect(safeNext('/connect/extension?name=Chrome')).toBe(
      '/connect/extension?name=Chrome',
    )
    expect(safeNext('/i/k7Q2xPa9Lm3Z')).toBe('/i/k7Q2xPa9Lm3Z')
    expect(safeNext('/s/k7Q2xPa9Lm3Z')).toBe('/s/k7Q2xPa9Lm3Z')
    expect(safeNext('/s/k7Q2xPa9Lm3Z?add=1')).toBe('/s/k7Q2xPa9Lm3Z?add=1')
  })

  it('refuses anything that could leave Aaru', () => {
    for (const next of [
      '//evil.example',
      'https://evil.example',
      '/\\evil.example',
      'javascript:alert(1)',
      '/privacy',
      '/i/',
      '/i/../app',
      '/i/abc/def',
      '/i/abc?next=//evil.example',
      '/connect/extensionx',
      '/s/',
      '/s/abc/def',
      '/s/abc?add=2',
      '/s/abc?add=1&next=//evil.example',
      '/s/../app',
      undefined,
      42,
    ])
      expect(safeNext(next)).toBe('/app')
  })
})
