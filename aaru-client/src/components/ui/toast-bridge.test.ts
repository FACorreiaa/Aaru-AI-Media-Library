import { describe, expect, it, vi } from 'vitest'
import type { SomotoToast } from './toast-bridge'
import {
  toasterReady,
  toasterRequested,
  toasterWanted,
  withToaster,
} from './toast-bridge'

describe('toast bridge', () => {
  it('asks for the Toaster on the first toast and holds toasts until it mounts', async () => {
    expect(toasterRequested()).toBe(false)
    expect(toasterWanted()).toBe(false)

    const shown: string[] = []
    withToaster(() => shown.push('first'))
    withToaster(() => shown.push('second'))
    expect(toasterWanted()).toBe(true)
    await Promise.resolve()
    expect(shown).toEqual([])

    const somoto = vi.fn() as unknown as SomotoToast
    toasterReady(somoto)
    await Promise.resolve()
    expect(shown).toEqual(['first', 'second'])

    let got: SomotoToast | undefined
    withToaster((toast) => (got = toast))
    await Promise.resolve()
    expect(got).toBe(somoto)
  })
})
