import { describe, expect, it } from 'vitest'
import { hintFor, screenOf } from './hint'

describe('assistant hint', () => {
  it('names the screens the server knows', () => {
    expect(screenOf('/app')).toBe('home')
    expect(screenOf('/app/books')).toBe('books')
    expect(screenOf('/app/groups/g1/c1')).toBe('groups')
    expect(screenOf('/app/settings/data')).toBeNull()
    expect(screenOf('/app/bookshelf')).toBeNull()
  })

  it('sends the title only on a title page', () => {
    expect(hintFor('/app/title/x', 't1')).toEqual({
      screen: 'title',
      titleId: 't1',
    })
    expect(hintFor('/app/books', 't1')).toEqual({ screen: 'books' })
    expect(hintFor('/app/settings', null)).toBeUndefined()
  })
})
