import { describe, expect, it } from 'vitest'
import { previewParams } from './preview'

describe('previewParams', () => {
  it('names a title by the first provider id it has', () => {
    expect(
      previewParams({ type: 'show', ids: { imdb: 'tt1', tmdb: '1399' } }),
    ).toEqual({ type: 'show', provider: 'tmdb', ref: '1399' })
    expect(previewParams({ type: 'show', ids: { anilist: '21' } })).toEqual({
      type: 'show',
      provider: 'anilist',
      ref: '21',
    })
    expect(
      previewParams({ type: 'album', ids: { musicbrainz: 'abc' } }),
    ).toEqual({ type: 'album', provider: 'musicbrainz', ref: 'abc' })
  })

  it('has no page for a title without ids', () => {
    expect(previewParams({ type: 'movie', ids: {} })).toBeNull()
  })
})
