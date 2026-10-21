import { describe, expect, it } from 'vitest'
import { albumSummary, discs, largeCover, trackLength } from './album'
import type { AlbumTrack } from './album'

const track = (
  disc: number,
  position: number,
  lengthMs?: number,
): AlbumTrack => ({ disc, position, name: `${disc}-${position}`, lengthMs })

describe('track length', () => {
  it('reads as m:ss, padding the seconds', () => {
    expect(trackLength(187_000)).toBe('3:07')
    expect(trackLength(765_400)).toBe('12:45')
    expect(trackLength(59_600)).toBe('1:00')
  })

  it('carries hours when a track runs past one', () => {
    expect(trackLength(3_729_000)).toBe('1:02:09')
  })

  it('is empty when the length is unknown', () => {
    expect(trackLength(undefined)).toBe('')
    expect(trackLength(null)).toBe('')
    expect(trackLength(0)).toBe('')
  })
})

describe('discs', () => {
  it('groups by disc, discs and positions ascending', () => {
    const grouped = discs([track(2, 2), track(1, 2), track(2, 1), track(1, 1)])
    expect(grouped.map((d) => d.number)).toEqual([1, 2])
    expect(grouped[0].tracks.map((t) => t.name)).toEqual(['1-1', '1-2'])
    expect(grouped[1].tracks.map((t) => t.name)).toEqual(['2-1', '2-2'])
  })

  it('keeps a single-disc album as one group', () => {
    expect(discs([track(1, 1), track(1, 2)])).toHaveLength(1)
    expect(discs([])).toEqual([])
  })
})

describe('album summary', () => {
  it('counts the tracks and their time', () => {
    expect(albumSummary([track(1, 1, 120_000), track(1, 2, 180_000)])).toBe(
      '2 tracks · 5 min',
    )
    expect(albumSummary([track(1, 1, 4_500_000)])).toBe('1 track · 1 h 15 min')
    expect(albumSummary([track(1, 1, 3_600_000)])).toBe('1 track · 1 h')
  })

  it('leaves the time out when a length is missing', () => {
    expect(albumSummary([track(1, 1, 120_000), track(1, 2)])).toBe('2 tracks')
  })
})

describe('large cover', () => {
  it('asks the Cover Art Archive for 500 px instead of 250', () => {
    expect(
      largeCover('https://coverartarchive.org/release-group/abc/front-250'),
    ).toBe('https://coverartarchive.org/release-group/abc/front-500')
  })

  it('leaves other URLs alone', () => {
    expect(largeCover('https://image.tmdb.org/t/p/w342/x.jpg')).toBe(
      'https://image.tmdb.org/t/p/w342/x.jpg',
    )
    expect(largeCover(undefined)).toBeUndefined()
  })
})
