import { describe, expect, it } from 'vitest'
import { ADDED_BY_HAND, roadmapSections } from './roadmap'
import type { ListRow } from './model'

const row = (titleId: string): ListRow => ({
  titleId,
  title: titleId,
  kind: 'book',
})

describe('roadmapSections', () => {
  it('groups members by step in list order, keeps missing text, and puts hand-added titles last', () => {
    const rows = [row('B'), row('A'), row('C'), row('HAND')]
    const sections = roadmapSections(
      {
        steps: [
          {
            heading: 'Hickman FF',
            note: 'Start here.',
            items: [
              { titleId: 'a', note: 'FF #570-588', pair: 1 },
              { titleId: 'B', pair: 1 },
            ],
          },
          {
            heading: 'Extras',
            missing: ['Ultimates (#1-12)'],
            items: [{ titleId: 'C', optional: true }, { titleId: 'GONE' }],
          },
          { heading: 'Empty', items: [] },
        ],
      },
      rows,
    )
    expect(sections.map((s) => s.heading)).toEqual([
      'Hickman FF',
      'Extras',
      ADDED_BY_HAND,
    ])
    expect(sections[0].entries.map((e) => e.row.titleId)).toEqual(['B', 'A'])
    expect(sections[0].entries[1]).toMatchObject({
      note: 'FF #570-588',
      pair: 1,
    })
    expect(sections[1].entries).toEqual([
      { row: rows[2], note: undefined, optional: true, pair: undefined },
    ])
    expect(sections[1].missing).toEqual(['Ultimates (#1-12)'])
    expect(sections[2].entries.map((e) => e.row.titleId)).toEqual(['HAND'])
  })
})
