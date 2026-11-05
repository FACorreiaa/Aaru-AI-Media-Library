import type { components } from '../api/schema'

// ASK-009 on the web: one Chat turn's answer arrives as server-sent events. This reads them
// out of the stream's text, in whatever pieces it arrives.

export type ChatComponents = components['schemas']['ChatComponentsFrame']

export type ChatFrame =
  | { type: 'status'; text: string }
  | { type: 'delta'; text: string }
  | { type: 'components'; components: ChatComponents }
  | { type: 'done'; turnId: string }
  | { type: 'error'; code: string; message: string }

/** Reads frames out of the stream's text. A frame split across chunks waits for the rest. */
export class FrameParser {
  private buffer = ''
  private event = ''
  private data: string[] = []

  consume(chunk: string): ChatFrame[] {
    this.buffer += chunk
    const frames: ChatFrame[] = []
    let newline = this.buffer.indexOf('\n')
    while (newline >= 0) {
      const line = this.buffer.slice(0, newline).replace(/\r$/, '')
      this.buffer = this.buffer.slice(newline + 1)
      const frame = this.line(line)
      if (frame) frames.push(frame)
      newline = this.buffer.indexOf('\n')
    }
    return frames
  }

  private line(line: string): ChatFrame | null {
    if (line === '') {
      const frame = this.event
        ? toFrame(this.event, this.data.join('\n'))
        : null
      this.event = ''
      this.data = []
      return frame
    }
    // A heartbeat.
    if (line.startsWith(':')) return null
    const colon = line.indexOf(':')
    const field = colon < 0 ? line : line.slice(0, colon)
    const value = colon < 0 ? '' : line.slice(colon + 1).replace(/^ /, '')
    if (field === 'event') this.event = value
    else if (field === 'data') this.data.push(value)
    return null
  }
}

function toFrame(event: string, data: string): ChatFrame | null {
  let json: Record<string, unknown>
  try {
    json = JSON.parse(data) as Record<string, unknown>
  } catch {
    return null
  }
  const text = typeof json.text === 'string' ? json.text : ''
  switch (event) {
    case 'status':
      return { type: 'status', text }
    case 'delta':
      return { type: 'delta', text }
    case 'components':
      return { type: 'components', components: json }
    case 'done':
      return typeof json.turnId === 'string'
        ? { type: 'done', turnId: json.turnId }
        : null
    case 'error':
      return {
        type: 'error',
        code: typeof json.code === 'string' ? json.code : 'try_again',
        message:
          typeof json.message === 'string'
            ? json.message
            : 'Aaru could not answer that. Try again.',
      }
    default:
      return null
  }
}
