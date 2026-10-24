import { describe, expect, it } from 'vitest'
import { clampPage, fold, matches, pageCount, pageOf } from './paging'

describe('fold', () => {
  it('drops case, accents and punctuation', () => {
    expect(fold('Pokémon: XY!')).toBe('pokemon xy')
    expect(fold('  Ao   Ashi ')).toBe('ao ashi')
  })
})

describe('matches', () => {
  it('finds every word at the start of a word, in any field', () => {
    expect(matches('', 'Frieren')).toBe(true)
    expect(matches('fri', 'Frieren')).toBe(true)
    expect(matches('ashi ao', 'Ao Ashi')).toBe(true)
    expect(matches('pokemon', 'Pokémon')).toBe(true)
    expect(matches('beatles', 'Abbey Road', 'The Beatles')).toBe(true)
    expect(matches('ieren', 'Frieren')).toBe(false)
    expect(matches('ao bleach', 'Ao Ashi')).toBe(false)
    expect(matches('x', null, undefined)).toBe(false)
  })
})

describe('pages', () => {
  const items = Array.from({ length: 45 }, (_, i) => i)

  it('counts 20 to a page, at least one', () => {
    expect(pageCount(0)).toBe(1)
    expect(pageCount(20)).toBe(1)
    expect(pageCount(21)).toBe(2)
    expect(pageCount(45)).toBe(3)
  })

  it('keeps the page inside the list', () => {
    expect(clampPage(undefined, 45)).toBe(1)
    expect(clampPage(7, 45)).toBe(3)
    expect(clampPage(0, 45)).toBe(1)
  })

  it('slices one page', () => {
    expect(pageOf(items, 1)).toEqual(items.slice(0, 20))
    expect(pageOf(items, 3)).toEqual([40, 41, 42, 43, 44])
    expect(pageOf(items, 9)).toEqual([40, 41, 42, 43, 44])
  })
})
