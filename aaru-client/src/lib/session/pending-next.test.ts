import { beforeEach, describe, expect, it } from 'vitest'
import { rememberNext, takeNext } from './pending-next'

// Tests run in Node: a minimal in-memory Storage.
class MemoryStorage {
  private items = new Map<string, string>()
  getItem(key: string) {
    return this.items.get(key) ?? null
  }
  setItem(key: string, value: string) {
    this.items.set(key, value)
  }
  removeItem(key: string) {
    this.items.delete(key)
  }
}

describe('pending next', () => {
  beforeEach(() => {
    Object.defineProperty(globalThis, 'localStorage', {
      value: new MemoryStorage(),
      configurable: true,
    })
  })

  it('returns a remembered invite once', () => {
    rememberNext('/i/k7Q2xPa9Lm3Z', 1000)
    expect(takeNext(2000)).toBe('/i/k7Q2xPa9Lm3Z')
    expect(takeNext(3000)).toBe('/app')
  })

  it('forgets stale and unsafe destinations', () => {
    rememberNext('/i/k7Q2xPa9Lm3Z', 0)
    expect(takeNext(16 * 60 * 1000)).toBe('/app')
    rememberNext('//evil.example', 0)
    expect(takeNext(1)).toBe('/app')
    localStorage.setItem('aaru.next', JSON.stringify({ next: '//evil', at: 0 }))
    expect(takeNext(1)).toBe('/app')
  })
})
