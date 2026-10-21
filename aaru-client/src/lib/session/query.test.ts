import { QueryClient } from '@tanstack/solid-query'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const getSession = vi.fn()
vi.mock('./session', () => ({ getSession }))
// The router's own module needs a DOM; the redirect is all this module uses of it.
vi.mock('@tanstack/solid-router', () => ({
  redirect: (options: unknown) => ({ options }),
}))

const { SESSION_KEY, forgetAccount, requireSession } = await import('./query')

describe('requireSession', () => {
  let queryClient: QueryClient

  beforeEach(() => {
    getSession.mockReset()
    queryClient = new QueryClient()
  })

  it('asks the server once per tab, not once per navigation', async () => {
    getSession.mockResolvedValue({ signedIn: true, displayName: 'Ana' })
    await requireSession(queryClient)
    await requireSession(queryClient)
    await requireSession(queryClient)
    expect(getSession).toHaveBeenCalledTimes(1)
  })

  it('sends a signed-out tab to sign-in and does not keep the answer', async () => {
    getSession.mockResolvedValueOnce({ signedIn: false })
    await expect(requireSession(queryClient)).rejects.toMatchObject({
      options: { to: '/sign-in' },
    })
    expect(queryClient.getQueryData(SESSION_KEY)).toBeUndefined()

    // Signed in since: the next navigation sees it.
    getSession.mockResolvedValueOnce({ signedIn: true, displayName: null })
    await expect(requireSession(queryClient)).resolves.toEqual({
      signedIn: true,
      displayName: null,
    })
  })

  it('asks again after signing out', async () => {
    getSession.mockResolvedValue({ signedIn: true, displayName: null })
    await requireSession(queryClient)
    forgetAccount(queryClient)
    await requireSession(queryClient)
    expect(getSession).toHaveBeenCalledTimes(2)
  })
})
