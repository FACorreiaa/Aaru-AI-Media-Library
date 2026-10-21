import { describe, expect, it } from 'vitest'
import {
  episodeLine,
  eyebrow,
  livePositionMs,
  minutesLeft,
  progress,
  timeLabel,
} from './model'
import type { NowPlaying } from './model'

function playing(overrides: Partial<NowPlaying> = {}): NowPlaying {
  return {
    watchEventId: '00000000-0000-4000-8000-0000000000e1',
    libraryItemId: '00000000-0000-4000-8000-000000000001',
    title: {
      id: '00000000-0000-4000-8000-0000000000aa',
      type: 'show',
      title: 'Cyberpunk: Edgerunners',
      isAnime: false,
      ids: {},
    },
    episode: { season: 2, number: 7 },
    episodeName: 'To the Depths with You',
    source: 'stremio',
    state: 'playing',
    positionMs: 687_020,
    durationMs: 1_715_264,
    updatedAt: '2026-10-21T20:32:36Z',
    ...overrides,
  }
}

const at = (iso: string) => new Date(iso)

describe('now playing', () => {
  it('runs on from the last report while playing, up to the end', () => {
    // 3 minutes after the report.
    expect(livePositionMs(playing(), at('2026-10-21T20:35:36Z'))).toBe(867_020)
    expect(livePositionMs(playing(), at('2026-10-21T23:00:00Z'))).toBe(
      1_715_264,
    )
  })

  it('stands still while paused', () => {
    expect(
      livePositionMs(playing({ state: 'paused' }), at('2026-10-21T21:00:00Z')),
    ).toBe(687_020)
  })

  it('reads time left, and flips to the end time', () => {
    const now = at('2026-10-21T20:32:36Z')
    expect(minutesLeft(playing(), now)).toBe(18)
    expect(timeLabel(playing(), now, false)).toBe('18m left')
    expect(timeLabel(playing(), now, true, 'en-GB', 'UTC')).toBe(
      'Ends at 20:49',
    )
    // A pause has no end time.
    expect(timeLabel(playing({ state: 'paused' }), now, true)).toBe('18m left')
  })

  it('knows nothing of the time without a duration', () => {
    const now = at('2026-10-21T20:40:00Z')
    expect(progress(playing({ durationMs: 0 }), now)).toBeNull()
    expect(timeLabel(playing({ durationMs: 0 }), now, false)).toBe('')
  })

  it('names the state, the player and the episode', () => {
    expect(eyebrow(playing())).toBe('Now playing · Stremio')
    expect(eyebrow(playing({ state: 'paused', source: 'disney_plus' }))).toBe(
      'Paused · Disney+',
    )
    expect(episodeLine(playing())).toBe('S2 · E7 · To the Depths with You')
    expect(episodeLine(playing({ episode: undefined }))).toBeNull()
  })
})
