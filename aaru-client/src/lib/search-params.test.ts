import { describe, expect, it } from 'vitest'
import {
  optionalBoolean,
  optionalEnum,
  optionalInt,
  optionalString,
} from './search-params'

describe('search params', () => {
  it('keeps strings and drops anything else', () => {
    expect(optionalString('/app')).toBe('/app')
    expect(optionalString(42)).toBeUndefined()
    expect(optionalString(undefined)).toBeUndefined()
  })

  it('keeps booleans only', () => {
    expect(optionalBoolean(true)).toBe(true)
    expect(optionalBoolean('true')).toBeUndefined()
  })

  it('keeps a value from the options', () => {
    expect(optionalEnum('month', ['week', 'month'])).toBe('month')
    expect(optionalEnum('year', ['week', 'month'])).toBeUndefined()
  })

  it('reads integers in range from numbers or numeric strings', () => {
    expect(optionalInt(2026, 1900, 2200)).toBe(2026)
    expect(optionalInt('7', 1, 12)).toBe(7)
    expect(optionalInt(13, 1, 12)).toBeUndefined()
    expect(optionalInt(1.5, 1, 12)).toBeUndefined()
    expect(optionalInt('', 1, 12)).toBeUndefined()
    expect(optionalInt('x', 1, 12)).toBeUndefined()
  })
})
