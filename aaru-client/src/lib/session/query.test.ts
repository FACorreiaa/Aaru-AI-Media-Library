import { QueryClient } from '@tanstack/solid-query'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const getSession = vi.fn()
vi.mock('./session', () => ({ getSession }))
// The router's own module needs a DOM; the redirect is all this module uses of it.
vi.mock('@tanstack/solid-router', () => ({
  redirect: (options: unknown) => ({ options }),
}))

const {
  SESSION_KEY,
  forgetAccount,
  requireAiSharingAnswered,
  requireOnboarded,
  requireSession,
} = await import('./query')
const { onboardingFinished } = await import('../onboarding/session')

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

describe('requireOnboarded', () => {
  const signedIn = {
    signedIn: true as const,
    displayName: 'Ana',
    handle: 'ana',
  }

  it('sends a new account to the first run, carrying where it was headed', () => {
    expect(() =>
      requireOnboarded(
        { ...signedIn, onboardingPending: true },
        '/app/library?kind=book',
      ),
    ).toThrow(
      expect.objectContaining({
        options: {
          to: '/app/welcome',
          search: { next: '/app/library?kind=book' },
        },
      }),
    )
  })

  it('lets everyone else through, an absent flag included', () => {
    expect(() =>
      requireOnboarded({ ...signedIn, onboardingPending: false }, '/app'),
    ).not.toThrow()
    expect(() => requireOnboarded(signedIn, '/app')).not.toThrow()
  })

  it('stops asking once the first run ends, without asking the server again', async () => {
    getSession.mockReset()
    getSession.mockResolvedValue({ ...signedIn, onboardingPending: true })
    const queryClient = new QueryClient()
    queryClient.setQueryData(['library'], [])
    const before = await requireSession(queryClient)
    expect(before.onboardingPending).toBe(true)

    onboardingFinished(queryClient)
    const after = await requireSession(queryClient)
    expect(after.onboardingPending).toBe(false)
    expect(() => requireOnboarded(after, '/app')).not.toThrow()
    expect(getSession).toHaveBeenCalledTimes(1)
    // Pages read before the flow added titles are asked again.
    expect(queryClient.getQueryData(['library'])).toBeUndefined()
    expect(queryClient.getQueryData(SESSION_KEY)).toBeDefined()
  })
})

describe('requireAiSharingAnswered', () => {
  const signedIn = {
    signedIn: true as const,
    displayName: 'Ana',
    handle: 'ana',
  }

  it('sends an account that never answered to the question, carrying where it was headed', () => {
    expect(() =>
      requireAiSharingAnswered(
        { ...signedIn, aiSharing: 'unanswered' },
        '/app/library',
      ),
    ).toThrow(
      expect.objectContaining({
        options: { to: '/app/ai-sharing', search: { next: '/app/library' } },
      }),
    )
  })

  it('lets an answered account through, and one whose answer could not be read', () => {
    for (const aiSharing of ['allowed', 'declined', undefined] as const)
      expect(() =>
        requireAiSharingAnswered({ ...signedIn, aiSharing }, '/app'),
      ).not.toThrow()
  })

  it('does not ask in the tab where the first run just ended', async () => {
    const queryClient = new QueryClient()
    queryClient.setQueryData(SESSION_KEY, {
      ...signedIn,
      onboardingPending: true,
      aiSharing: 'unanswered',
    })
    onboardingFinished(queryClient)
    const session = await requireSession(queryClient)
    expect(() => requireAiSharingAnswered(session, '/app')).not.toThrow()
  })
})
