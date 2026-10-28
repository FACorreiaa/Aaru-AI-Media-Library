import { beforeEach, describe, expect, it } from 'vitest'
import { rememberAdd, takeAdd } from './pending-add'

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

describe('pending add', () => {
  beforeEach(() => {
    Object.defineProperty(globalThis, 'localStorage', {
      value: new MemoryStorage(),
      configurable: true,
    })
  })

  it('saves once, for the link this browser asked to save', () => {
    rememberAdd('abc', 1000)
    expect(takeAdd('abc', 2000)).toBe(true)
    expect(takeAdd('abc', 3000)).toBe(false)
  })

  it('never saves from a link that only carries ?add=1', () => {
    expect(takeAdd('abc', 1000)).toBe(false)
  })

  it('refuses another link or a stale ask', () => {
    rememberAdd('abc', 1000)
    expect(takeAdd('xyz', 2000)).toBe(false)
    rememberAdd('abc', 1000)
    expect(takeAdd('abc', 1000 + 16 * 60 * 1000)).toBe(false)
  })
})
