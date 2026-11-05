import { describe, expect, it } from 'vitest'
import { FrameParser } from './frames'

describe('chat frames', () => {
  it('reads frames split across chunks, and skips heartbeats', () => {
    const parser = new FrameParser()
    expect(parser.consume(': ping\n\nevent: sta')).toEqual([])
    expect(
      parser.consume('tus\ndata: {"text":"Thinking"}\n\nevent: delta\r\n'),
    ).toEqual([{ type: 'status', text: 'Thinking' }])
    expect(parser.consume('data: {"text":"Hi"}\r\n\r\n')).toEqual([
      { type: 'delta', text: 'Hi' },
    ])
  })

  it('reads components, done and error', () => {
    const frames = new FrameParser().consume(
      'event: components\ndata: {"importId":"i1","actionId":"a1"}\n\n' +
        'event: done\ndata: {"turnId":"t1"}\n\n' +
        'event: error\ndata: {"code":"resting","message":"Aaru is resting."}\n\n',
    )
    expect(frames).toEqual([
      { type: 'components', components: { importId: 'i1', actionId: 'a1' } },
      { type: 'done', turnId: 't1' },
      { type: 'error', code: 'resting', message: 'Aaru is resting.' },
    ])
  })

  it('drops a frame it cannot read', () => {
    expect(
      new FrameParser().consume(
        'event: delta\ndata: {nope\n\nevent: odd\ndata: {}\n\n',
      ),
    ).toEqual([])
  })
})
