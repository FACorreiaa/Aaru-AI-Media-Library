import { describe, expect, it } from 'vitest'
import { itemLine, roadmapSummary, startsPair, titleCount } from './roadmap'
import type { ChatRoadmap } from './roadmap'

const roadmap: ChatRoadmap = {
  listName: 'Before Secret Wars',
  steps: [
    {
      heading: 'The Multiverse',
      note: 'Start here.',
      items: [
        { title: 'Loki', type: 'show', year: 2021, note: 'Both seasons' },
        { title: 'FF', type: 'book', author: 'Jonathan Hickman', pair: 1 },
        { title: 'Fantastic Four', type: 'book', pair: 1 },
      ],
    },
    { heading: 'Doom', items: [{ title: 'Doomsday', type: 'movie' }] },
  ],
}

describe('a chat roadmap', () => {
  it('counts its titles and steps', () => {
    expect(titleCount(roadmap)).toBe(4)
    expect(roadmapSummary(roadmap)).toBe('4 titles in 2 steps')
  })

  it('is a plain count when no step has a heading', () => {
    expect(
      roadmapSummary({
        steps: [{ items: [{ title: 'Heat', type: 'movie' }] }],
      }),
    ).toBe('1 title')
  })

  it('says what a title is, by whom and when', () => {
    expect(itemLine(roadmap.steps[0].items[0])).toBe('Show · 2021')
    expect(itemLine(roadmap.steps[0].items[1])).toBe('Book · Jonathan Hickman')
    expect(itemLine(roadmap.steps[1].items[0])).toBe('Film')
  })

  it('marks only the first of a pair', () => {
    const items = roadmap.steps[0].items
    expect(startsPair(items, 0)).toBe(false)
    expect(startsPair(items, 1)).toBe(true)
    expect(startsPair(items, 2)).toBe(false)
  })
})
