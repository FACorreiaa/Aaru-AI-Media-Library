import { describe, expect, it } from 'vitest'
import { favoriteLabel, favoriteRef, favoriteRows, moveFavorite } from './model'
import type { Favorites } from './model'

const title = (id: string, type: 'movie' | 'manga' = 'movie') => ({
  id,
  type,
  title: id,
  isAnime: false,
  ids: {},
})

const none: Favorites = {
  film: [],
  show: [],
  anime: [],
  manga: [],
  book: [],
  album: [],
}

describe('favoriteRows', () => {
  it('keeps only kinds with favorites, in the library order', () => {
    const rows = favoriteRows({
      ...none,
      manga: [title('Berserk', 'manga')],
      film: [title('Heat'), title('Dune')],
    })
    expect(rows.map((r) => [r.kind, r.label, r.titles.length])).toEqual([
      ['film', 'Films', 2],
      ['manga', 'Manga', 1],
    ])
  })

  it('has nothing to show without favorites', () => {
    expect(favoriteRows(none)).toEqual([])
    expect(favoriteRows(undefined)).toEqual([])
  })
})

describe('moveFavorite', () => {
  const list = ['a', 'b', 'c']
  it('moves up and down', () => {
    expect(moveFavorite(list, 1, -1)).toEqual(['b', 'a', 'c'])
    expect(moveFavorite(list, 1, 1)).toEqual(['a', 'c', 'b'])
  })
  it('leaves the ends alone', () => {
    expect(moveFavorite(list, 0, -1)).toBe(list)
    expect(moveFavorite(list, 2, 1)).toBe(list)
  })
})

describe('favoriteRef and favoriteLabel', () => {
  it('refers to a saved title by its Aaru id', () => {
    expect(favoriteRef(title('x', 'manga'))).toEqual({
      titleId: 'x',
      type: 'manga',
    })
  })
  it('uses the library labels', () => {
    expect(favoriteLabel('album')).toBe('Music')
    expect(favoriteLabel('anime')).toBe('Anime')
  })
})
