import { describe, expect, it } from 'vitest'
import { BOTTOM, MORE, TOP, inMore, isAt, moreRows } from './nav'
import type { NavPath, NavTarget } from './nav'

const all = [...TOP, ...MORE, ...BOTTOM]
const row = (to: NavPath): NavTarget => {
  const found = all.find((d) => d.to === to)
  if (!found) throw new Error(`no row ${to}`)
  return found
}
/** The rows that light up on a path: always exactly one inside the app. */
const activeOn = (path: string) =>
  all.filter((d) => isAt(path, d)).map((d) => d.to)

describe('shell rows', () => {
  it('keeps six rows on top and More in the owner’s order', () => {
    expect(TOP.map((d) => d.label)).toEqual([
      'Home',
      'Discover',
      'Library',
      'Calendar',
      'Lists',
      'Friends',
    ])
    expect(MORE.map((d) => d.label)).toEqual([
      'Groups',
      'Books',
      'Manga',
      'Music',
      'Sports',
    ])
    expect(BOTTOM.map((d) => d.label)).toEqual(['Insights', 'Settings'])
  })

  it('lists Sports only while it is on', () => {
    expect(moreRows(true).map((d) => d.to)).toContain('/app/sports')
    expect(moreRows(false).map((d) => d.to)).toEqual([
      '/app/groups',
      '/app/books',
      '/app/manga',
      '/app/music',
    ])
  })
})

describe('isAt', () => {
  it('lights the More rows on their pages and below them', () => {
    expect(activeOn('/app/books')).toEqual(['/app/books'])
    expect(activeOn('/app/manga')).toEqual(['/app/manga'])
    expect(activeOn('/app/groups/g1/c1')).toEqual(['/app/groups'])
    expect(activeOn('/app/sports')).toEqual(['/app/sports'])
  })

  it('gives Music to its own row, not Insights', () => {
    expect(activeOn('/app/music')).toEqual(['/app/music'])
    expect(isAt('/app/music', row('/app/insights'))).toBe(false)
    expect(activeOn('/app/insights')).toEqual(['/app/insights'])
    expect(activeOn('/app/recap')).toEqual(['/app/insights'])
  })

  it('does not match a path that only starts with the same letters', () => {
    expect(isAt('/app/bookshelf', row('/app/books'))).toBe(false)
    expect(isAt('/app/musical', row('/app/music'))).toBe(false)
  })

  it('keeps Home to itself and its plans', () => {
    expect(activeOn('/app')).toEqual(['/app'])
    expect(activeOn('/app/')).toEqual(['/app'])
    expect(activeOn('/app/plans/p1')).toEqual(['/app'])
    expect(activeOn('/app/title/t1')).toEqual(['/app/library'])
  })
})

describe('inMore', () => {
  it('opens the group on its own pages only', () => {
    expect(inMore('/app/books')).toBe(true)
    expect(inMore('/app/music')).toBe(true)
    expect(inMore('/app/groups/g1')).toBe(true)
    expect(inMore('/app/sports')).toBe(true)
    expect(inMore('/app')).toBe(false)
    expect(inMore('/app/discover')).toBe(false)
    expect(inMore('/app/insights')).toBe(false)
  })
})
