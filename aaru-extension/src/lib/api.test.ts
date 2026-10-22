import { describe, expect, it } from 'vitest'
import { body } from './api'

describe('scrobble body', () => {
  it('sends a YouTube video as a video, never as a film or show', () => {
    expect(
      body({
        action: 'start',
        playing: {
          source: 'youtube',
          ref: 'dQw4w9WgXcQ',
          type: 'video',
          title: 'Never Gonna Give You Up',
          channel: 'Rick Astley',
        },
        progress: 19.7,
        durationMs: 213_000,
      }),
    ).toStrictEqual({
      source: 'youtube',
      ref: 'dQw4w9WgXcQ',
      progress: 19.7,
      durationMs: 213_000,
      video: {
        id: 'dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        channel: 'Rick Astley',
      },
    })
  })
})
