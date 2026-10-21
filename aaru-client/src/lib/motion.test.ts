import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const animate = vi.fn(() => Promise.resolve())
vi.mock('motion/mini', () => ({ animate }))

const { flip, leave, play, pop } = await import('./motion')

function reduceMotion(reduce: boolean) {
  vi.stubGlobal('window', {
    matchMedia: () => ({ matches: reduce }),
  })
}

/** A stand-in element whose position the test moves by hand. */
function box(left: number, top: number) {
  const rect = { left, top }
  const el = {
    rect,
    getBoundingClientRect: () => ({ ...rect }),
  }
  return el
}

beforeEach(() => animate.mockClear())
afterEach(() => vi.unstubAllGlobals())

describe('play', () => {
  it('animates with the shared ease-out', async () => {
    reduceMotion(false)
    const el = box(0, 0) as unknown as Element
    await play(el, { opacity: [0, 1] })
    expect(animate).toHaveBeenCalledWith(
      el,
      { opacity: [0, 1] },
      { duration: 0.24, ease: [0.2, 0.7, 0.2, 1] },
    )
  })

  it('does nothing with reduced motion, and still resolves', async () => {
    reduceMotion(true)
    await leave(box(0, 0) as unknown as Element)
    expect(animate).not.toHaveBeenCalled()
  })

  it('does nothing on the server', async () => {
    await play(box(0, 0) as unknown as Element, { opacity: [0, 1] })
    expect(animate).not.toHaveBeenCalled()
  })
})

describe('pop', () => {
  it('scales up to rest once, short and without overshoot', async () => {
    reduceMotion(false)
    const el = box(0, 0) as unknown as Element
    await pop(el)
    expect(animate).toHaveBeenCalledWith(
      el,
      { transform: ['scale(0.85)', 'scale(1)'] },
      { duration: 0.2, ease: [0.2, 0.7, 0.2, 1] },
    )
  })

  it('does nothing with reduced motion', async () => {
    reduceMotion(true)
    await pop(box(0, 0) as unknown as Element)
    expect(animate).not.toHaveBeenCalled()
  })
})

describe('flip', () => {
  it('slides only the children that moved, from their old place', async () => {
    reduceMotion(false)
    const stays = box(0, 0)
    const moves = box(0, 100)
    const container = { children: [stays, moves] } as unknown as Element
    await flip(container, () => {
      moves.rect.top = 60
    })
    expect(animate).toHaveBeenCalledTimes(1)
    expect(animate).toHaveBeenCalledWith(
      moves,
      { transform: ['translate(0px, 40px)', 'translate(0, 0)'] },
      expect.anything(),
    )
  })

  it('only mutates with reduced motion', async () => {
    reduceMotion(true)
    const mutate = vi.fn()
    await flip({ children: [box(0, 0)] } as unknown as Element, mutate)
    expect(mutate).toHaveBeenCalledOnce()
    expect(animate).not.toHaveBeenCalled()
  })
})
