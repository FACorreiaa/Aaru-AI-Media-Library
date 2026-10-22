import { beforeEach, describe, expect, it } from 'vitest'
import { rememberNext, takeNext } from './pending-next'

const store = new Map<string, string>()
beforeEach(() => {
  store.clear()
  globalThis.localStorage = {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  } as Storage
})

describe('pending sign-in destination', () => {
  it('returns it once', () => {
    rememberNext('/app/plans/abc', 1000)
    expect(takeNext(2000)).toBe('/app/plans/abc')
    expect(takeNext(3000)).toBe('/app')
  })

  it('expires with the link', () => {
    rememberNext('/app/plans/abc', 0)
    expect(takeNext(16 * 60 * 1000)).toBe('/app')
  })

  it('never keeps a destination outside Aaru', () => {
    rememberNext('https://evil.example', 0)
    expect(takeNext(1)).toBe('/app')
  })
})
