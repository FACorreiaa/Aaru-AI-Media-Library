import { describe, expect, it } from 'vitest'
import privacy from '../../../docs/privacy.md?raw'
import { parseInline, parseMarkdown } from './markdown'

describe('parseInline', () => {
  it('reads bold, italic, links and bare emails', () => {
    expect(
      parseInline(
        '**Bold** and _it_ via [TVmaze](https://tvmaze.com), x@y.com.',
      ),
    ).toEqual([
      { kind: 'strong', text: 'Bold' },
      { kind: 'text', text: ' and ' },
      { kind: 'em', text: 'it' },
      { kind: 'text', text: ' via ' },
      { kind: 'link', text: 'TVmaze', href: 'https://tvmaze.com' },
      { kind: 'text', text: ', ' },
      { kind: 'link', text: 'x@y.com', href: 'mailto:x@y.com' },
      { kind: 'text', text: '.' },
    ])
  })
})

describe('parseMarkdown', () => {
  it('joins wrapped paragraph lines and list continuation lines', () => {
    expect(parseMarkdown('# T\n\nOne\ntwo.\n\n- a\n  b\n- c')).toEqual([
      { kind: 'h1', text: [{ kind: 'text', text: 'T' }] },
      { kind: 'p', text: [{ kind: 'text', text: 'One two.' }] },
      {
        kind: 'ul',
        items: [[{ kind: 'text', text: 'a b' }], [{ kind: 'text', text: 'c' }]],
      },
    ])
  })

  it('renders the real privacy policy with every section and no stray markers', () => {
    const blocks = parseMarkdown(privacy)
    expect(blocks[0]).toEqual({
      kind: 'h1',
      text: [{ kind: 'text', text: 'Privacy policy' }],
    })
    const headings = blocks.flatMap((block) =>
      block.kind === 'h2' ? [block.text.map((part) => part.text).join('')] : [],
    )
    expect(headings).toEqual([
      'The short version',
      'What Aaru stores',
      'Who else is involved',
      'How long it is kept',
      'Your choices',
    ])
    const text = JSON.stringify(blocks)
    expect(text).not.toMatch(/\*\*|(^|\s)_\w/)
    expect(text).toContain('mailto:privacy@aaruapp.com')
  })
})
