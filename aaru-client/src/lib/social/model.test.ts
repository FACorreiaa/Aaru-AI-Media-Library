import { describe, expect, it } from 'vitest'
import {
  activityDay,
  activityVerb,
  countsLine,
  handleProblem,
  itemProgress,
  withReaction,
  inviteExpiry,
  invitePlea,
  inviterName,
  monogram,
  normalizeHandle,
  personLabel,
  requestOutcome,
} from './model'

const ana = { userId: '00000000-0000-0000-0000-000000000001', handle: 'ana' }

describe('social model', () => {
  it('normalizes a typed handle the way the server stores it', () => {
    expect(normalizeHandle('  @Ana_B ')).toBe('ana_b')
    expect(normalizeHandle('kai')).toBe('kai')
  })

  it('explains a malformed handle before a round trip', () => {
    expect(handleProblem('')).toBe('Enter a handle.')
    expect(handleProblem('ab')).toBe(
      'Use 3–20 letters, numbers or underscores.',
    )
    expect(handleProblem('has space')).not.toBeNull()
    expect(handleProblem('@Ana_B')).toBeNull()
  })

  it('labels a person by name and handle', () => {
    expect(personLabel(ana)).toBe('@ana')
    expect(personLabel({ ...ana, displayName: 'Ana Silva' })).toBe(
      'Ana Silva · @ana',
    )
  })

  it('makes a monogram from the name, else the handle', () => {
    expect(monogram(ana)).toBe('A')
    expect(monogram({ ...ana, displayName: 'kai mori' })).toBe('KM')
    expect(monogram({ ...ana, displayName: 'Zoë' })).toBe('Z')
  })

  it('says whether a request was sent or became a friendship', () => {
    expect(requestOutcome(ana, 'outgoing')).toBe('Request sent to @ana.')
    expect(requestOutcome(ana, 'friend')).toBe('You and @ana are friends.')
  })

  it('words an invite in the sender’s voice', () => {
    expect(inviterName(ana)).toBe('@ana')
    expect(inviterName({ ...ana, displayName: ' Ana ' })).toBe('Ana')
    expect(invitePlea('Arrival', 'film')).toBe('Watch Arrival with me.')
    expect(invitePlea('Dune', 'book')).toBe('Read Dune with me.')
    expect(invitePlea('Blue', 'album')).toBe('Listen to Blue with me.')
  })

  it('counts down an invite’s last days', () => {
    const now = Date.parse('2026-10-21T12:00:00Z')
    expect(inviteExpiry('2026-11-04T12:00:00Z', now)).toBe('Expires in 14 days')
    expect(inviteExpiry('2026-10-22T13:00:00Z', now)).toBe('Expires tomorrow')
    expect(inviteExpiry('2026-10-21T20:00:00Z', now)).toBe('Expires today')
  })

  it('says what a friend did', () => {
    const row = {
      id: 'x',
      user: ana,
      title: {
        id: 't',
        type: 'show' as const,
        title: 'Andor',
        isAnime: false,
        ids: {},
      },
      day: '2026-10-21',
      episodes: 1,
      finished: false,
      at: '2026-10-21T20:00:00Z',
    }
    expect(activityVerb({ ...row, lastSeason: 1, lastEpisode: 3 })).toBe(
      'watched S1 · E3',
    )
    expect(
      activityVerb({ ...row, episodes: 3, lastSeason: 1, lastEpisode: 5 }),
    ).toBe('watched 3 episodes, up to S1 · E5')
    expect(activityVerb({ ...row, episodes: 0, finished: true })).toBe(
      'finished',
    )
    const now = new Date('2026-10-21T22:00:00Z')
    expect(activityDay('2026-10-21', now)).toBe('Today')
    expect(activityDay('2026-10-20', now)).toBe('Yesterday')
    expect(activityDay('2026-10-17', now)).toBe('Sat 17 Oct')
  })

  it('sums up a shelf', () => {
    expect(
      countsLine({ movie: 42, show: 1, anime: 0, book: 8, album: 0 }),
    ).toBe('42 films · 1 show · 8 books')
    expect(countsLine({ movie: 0, show: 0, anime: 0, book: 0, album: 0 })).toBe(
      null,
    )
    const item = {
      title: base(),
      status: 'in_progress' as const,
      updatedAt: '',
    }
    expect(itemProgress({ ...item, lastSeason: 2, lastEpisode: 4 })).toBe(
      'S2 · E4',
    )
    expect(itemProgress({ ...item, bookPage: 120 })).toBe('Page 120')
    expect(itemProgress(item)).toBe(null)
  })

  it('keeps reaction counts in step with yours', () => {
    const row = {
      id: 'x',
      user: ana,
      title: base(),
      day: '2026-10-21',
      episodes: 0,
      finished: true,
      at: '2026-10-21T20:00:00Z',
      reactions: [{ emoji: '🔥', count: 2 }],
    }
    const loved = withReaction(row, '❤️')
    expect(loved.myReaction).toBe('❤️')
    expect(loved.reactions).toEqual([
      { emoji: '🔥', count: 2 },
      { emoji: '❤️', count: 1 },
    ])
    const switched = withReaction(loved, '🔥')
    expect(switched.reactions).toEqual([{ emoji: '🔥', count: 3 }])
    const cleared = withReaction(switched, null)
    expect(cleared.myReaction).toBeUndefined()
    expect(cleared.reactions).toEqual([{ emoji: '🔥', count: 2 }])
  })
})

function base() {
  return {
    id: 't',
    type: 'show' as const,
    title: 'Andor',
    isAnime: false,
    ids: {},
  }
}
