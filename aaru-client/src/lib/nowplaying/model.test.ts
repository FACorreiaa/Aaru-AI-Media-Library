import { describe, expect, it } from 'vitest'
import {
  episodeLine,
  eyebrow,
  fromNowPlaying,
  itemLine,
  libraryPlayEnded,
  livePositionMs,
  minutesLeft,
  playingItems,
  playingLibraryItems,
  progress,
  timeLabel,
} from './model'
import type { NowPlaying, NowPlayingItem } from './model'

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

function item(overrides: Partial<NowPlayingItem> = {}): NowPlayingItem {
  return {
    id: 'play-1',
    kind: 'track',
    name: 'Archangel',
    subtitle: 'Burial',
    service: 'YouTube Music',
    source: 'listenbrainz',
    state: 'playing',
    positionMs: 60_000,
    durationMs: 238_000,
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
    expect(eyebrow(fromNowPlaying(playing()))).toBe('Now playing · Stremio')
    expect(
      eyebrow(
        fromNowPlaying(playing({ state: 'paused', source: 'disney_plus' })),
      ),
    ).toBe('Paused · Disney+')
    expect(episodeLine(playing())).toBe('S2 · E7 · To the Depths with You')
    expect(episodeLine(playing({ episode: undefined }))).toBeNull()
  })
})

describe('everything playing', () => {
  const episode = item({
    id: '00000000-0000-4000-8000-0000000000e1',
    kind: 'episode',
    name: 'Arcane',
    subtitle: 'S1 · E8 · Oil and Water',
    service: 'Stremio',
    source: 'stremio',
    libraryItemId: '00000000-0000-4000-8000-000000000001',
  })
  const film = item({
    id: '00000000-0000-4000-8000-0000000000e2',
    kind: 'movie',
    name: 'Perfect Days',
    subtitle: undefined,
    service: 'Netflix',
    source: 'netflix',
    libraryItemId: '00000000-0000-4000-8000-000000000002',
  })
  const video = item({
    id: 'yt-1',
    kind: 'video',
    name: 'How Kurosawa builds a frame',
    subtitle: 'Every Frame a Painting',
    service: 'YouTube',
    source: 'youtube',
    durationMs: 0,
    originUrl: 'https://www.youtube.com/watch?v=abc',
  })
  const track = item()

  it('keeps the server order, at most three', () => {
    expect(playingItems({ items: [video, episode, track] })).toEqual([
      video,
      episode,
      track,
    ])
    expect(
      playingItems({ items: [episode, film, video, track] }).map((i) => i.id),
    ).toEqual([episode.id, film.id, video.id])
    expect(playingItems({ items: [], nowPlaying: playing() })).toEqual([])
  })

  it('reads an API older than items from its one nowPlaying', () => {
    const [only, ...more] = playingItems({ nowPlaying: playing() })
    expect(more).toEqual([])
    expect(only).toMatchObject({
      id: '00000000-0000-4000-8000-0000000000e1',
      kind: 'episode',
      name: 'Cyberpunk: Edgerunners',
      subtitle: 'S2 · E7 · To the Depths with You',
      service: 'Stremio',
      libraryItemId: '00000000-0000-4000-8000-000000000001',
      positionMs: 687_020,
    })
    expect(
      playingItems({ nowPlaying: playing({ episode: undefined }) })[0].kind,
    ).toBe('movie')
    expect(playingItems({})).toEqual([])
  })

  it('times a track like an episode, and a video of unknown length not at all', () => {
    const now = at('2026-10-21T20:34:00Z')
    expect(progress(track, now)).toBeCloseTo(144_000 / 238_000)
    expect(timeLabel(track, now, false)).toBe('2m left')
    expect(timeLabel(item({ state: 'paused' }), now, true)).toBe('3m left')
    expect(progress(video, now)).toBeNull()
    expect(minutesLeft(video, now)).toBeNull()
    expect(timeLabel(video, now, false)).toBe('')
  })

  it('names what plays and where', () => {
    expect(eyebrow(track)).toBe('Now playing · YouTube Music')
    expect(eyebrow(item({ state: 'paused', service: undefined }))).toBe(
      'Paused · ListenBrainz',
    )
    expect(itemLine(episode)).toBe('S1 · E8 · Oil and Water · Stremio')
    expect(itemLine(film)).toBe('Netflix')
    expect(itemLine(item({ service: undefined, source: 'youtube' }))).toBe(
      'Burial · YouTube',
    )
  })

  it('sets aside every library item playing, not only the first', () => {
    expect([...playingLibraryItems([video, episode, film, track])]).toEqual([
      episode.libraryItemId,
      film.libraryItemId,
    ])
    expect(playingLibraryItems([video, track]).size).toBe(0)
  })

  it('refetches the rows only when a library session ends', () => {
    expect(libraryPlayEnded([episode, track], [episode])).toBe(false)
    expect(libraryPlayEnded([episode, video], [video])).toBe(true)
    // The next episode is a new session.
    expect(
      libraryPlayEnded([episode], [{ ...episode, id: 'next-session' }]),
    ).toBe(true)
    expect(libraryPlayEnded([], [episode])).toBe(false)
  })
})
