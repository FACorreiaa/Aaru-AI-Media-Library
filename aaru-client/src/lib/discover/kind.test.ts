import { describe, expect, it } from 'vitest'
import type { DiscoverRow } from '../home/model'
import { TODAY_KINDS, rowsOfKinds } from './kind'

const row = (id: string, kind: DiscoverRow['kind']): DiscoverRow => ({
  id,
  kind,
  title: id,
  items: [],
})

const rows: DiscoverRow[] = [
  row('tv_trending', 'show'),
  row('books_trending', 'book'),
  row('movies_in_theaters', 'film'),
  row('anime_season', 'anime'),
  row('manga_trending', 'manga'),
  row('music_new', 'album'),
  row('manga_publishing', 'manga'),
]

describe('rows by kind', () => {
  it('keeps films, shows and anime on Today, in the server’s order', () => {
    expect(rowsOfKinds(rows, TODAY_KINDS).map((r) => r.id)).toEqual([
      'tv_trending',
      'movies_in_theaters',
      'anime_season',
    ])
  })

  it('gives each kind page its own rows', () => {
    expect(rowsOfKinds(rows, ['manga']).map((r) => r.id)).toEqual([
      'manga_trending',
      'manga_publishing',
    ])
    expect(rowsOfKinds(rows, ['book']).map((r) => r.id)).toEqual([
      'books_trending',
    ])
    expect(rowsOfKinds(rows, ['album']).map((r) => r.id)).toEqual(['music_new'])
  })

  it('reads the kind, never the id', () => {
    expect(rowsOfKinds([row('books_odd', 'film')], ['book'])).toEqual([])
  })

  it('is empty with no rows', () => {
    expect(rowsOfKinds([], TODAY_KINDS)).toEqual([])
  })
})
