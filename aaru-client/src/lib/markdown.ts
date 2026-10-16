/**
 * Just enough Markdown for Aaru's own legal pages (docs/privacy.md): headings, paragraphs,
 * bullet lists, **bold**, _italic_, links and bare email addresses. Not a general parser —
 * the source is ours and reviewed, so anything else is plain text.
 */

export type Inline =
  | { kind: 'text'; text: string }
  | { kind: 'strong'; text: string }
  | { kind: 'em'; text: string }
  | { kind: 'link'; text: string; href: string }

export type Block =
  | { kind: 'h1' | 'h2' | 'h3'; text: Inline[] }
  | { kind: 'p'; text: Inline[] }
  | { kind: 'ul'; items: Inline[][] }

const INLINE =
  /\*\*([^*]+)\*\*|_([^_]+)_|\[([^\]]+)\]\(([^)\s]+)\)|([\w.+-]+@[\w-]+(?:\.[\w-]+)+)/g

export function parseInline(source: string): Inline[] {
  const out: Inline[] = []
  let last = 0
  for (const match of source.matchAll(INLINE)) {
    const index = match.index
    if (index > last)
      out.push({ kind: 'text', text: source.slice(last, index) })
    // Unmatched groups are undefined at runtime, which the RegExp types do not say.
    const [, strong, em, linkText, href, email] = match as (
      string | undefined
    )[]
    if (strong !== undefined) out.push({ kind: 'strong', text: strong })
    else if (em !== undefined) out.push({ kind: 'em', text: em })
    else if (linkText !== undefined && href !== undefined)
      out.push({ kind: 'link', text: linkText, href })
    else if (email !== undefined) {
      // A sentence-ending full stop is not part of the address.
      const address = email.replace(/\.$/, '')
      out.push({ kind: 'link', text: address, href: `mailto:${address}` })
      if (address.length < email.length) out.push({ kind: 'text', text: '.' })
    }
    last = index + match[0].length
  }
  if (last < source.length) out.push({ kind: 'text', text: source.slice(last) })
  return out
}

/** Blocks are separated by blank lines; a list's items may wrap onto indented lines. */
export function parseMarkdown(source: string): Block[] {
  const blocks: Block[] = []
  for (const chunk of source.replace(/\r\n/g, '\n').split(/\n\s*\n/)) {
    const lines = chunk.split('\n').filter((line) => line.trim() !== '')
    if (lines.length === 0) continue
    const first = lines[0]
    const heading = /^(#{1,3})\s+(.*)$/.exec(first)
    if (heading && lines.length === 1) {
      const level = heading[1].length as 1 | 2 | 3
      blocks.push({ kind: `h${level}`, text: parseInline(heading[2]) })
    } else if (/^[-*]\s+/.test(first)) {
      const items: string[] = []
      for (const line of lines) {
        if (/^[-*]\s+/.test(line)) items.push(line.replace(/^[-*]\s+/, ''))
        else items[items.length - 1] += ` ${line.trim()}`
      }
      blocks.push({ kind: 'ul', items: items.map(parseInline) })
    } else {
      blocks.push({
        kind: 'p',
        text: parseInline(lines.map((line) => line.trim()).join(' ')),
      })
    }
  }
  return blocks
}
