import { describe, expect, it } from 'vitest'
import { HEARTBEAT_MS, Session } from './session'
import type { Observation, Playing } from './types'

const episode = (ref: string, number = 3): Playing => ({
  source: 'netflix',
  ref,
  type: 'show',
  title: 'Severance',
  season: 2,
  episode: number,
  episodeTitle: 'Who Is Alive?',
})

const minute = 60_000
const seen = (
  playing: Playing | null,
  position: number,
  extra: Partial<Observation> = {},
): Observation => ({
  playing,
  positionMs: position * minute,
  durationMs: 50 * minute,
  paused: false,
  ended: false,
  ...extra,
})

const actions = (calls: { action: string; progress: number }[]) =>
  calls.map((call) => `${call.action} ${call.progress}`)

describe('session', () => {
  it('starts, pauses, resumes and stops when the episode ends', () => {
    const session = new Session()
    const one = episode('81')
    expect(actions(session.observe(seen(one, 0), 0))).toEqual(['start 0'])
    expect(session.observe(seen(one, 1), 1000)).toEqual([])
    expect(
      actions(session.observe(seen(one, 10, { paused: true }), 2000)),
    ).toEqual(['pause 20'])
    expect(actions(session.observe(seen(one, 10), 3000))).toEqual(['start 20'])
    expect(
      actions(session.observe(seen(one, 50, { ended: true }), 4000)),
    ).toEqual(['stop 100'])
    expect(session.observe(seen(one, 50, { paused: true }), 5000)).toEqual([])
  })

  it('sends start again every five minutes while playing', () => {
    const session = new Session()
    session.observe(seen(episode('81'), 0), 0)
    expect(session.observe(seen(episode('81'), 4), HEARTBEAT_MS - 1)).toEqual(
      [],
    )
    expect(
      actions(session.observe(seen(episode('81'), 5), HEARTBEAT_MS)),
    ).toEqual(['start 10'])
  })

  it('stops the last episode at its progress when the next one starts', () => {
    const session = new Session()
    session.observe(seen(episode('81'), 0), 0)
    session.observe(seen(episode('81'), 47), 1000)
    const calls = session.observe(seen(episode('82', 4), 0), 2000)
    expect(calls.map((c) => [c.action, c.playing.ref, c.progress])).toEqual([
      ['stop', '81', 94],
      ['start', '82', 0],
    ])
  })

  it('stops on leaving the page, once', () => {
    const session = new Session()
    session.observe(seen(episode('81'), 0), 0)
    session.observe(seen(episode('81'), 20), 1000)
    expect(actions(session.end())).toEqual(['stop 40'])
    expect(session.end()).toEqual([])
  })

  it('ignores trailers, and pages with nothing playing', () => {
    const session = new Session()
    expect(
      session.observe(seen(episode('trailer'), 0, { durationMs: minute }), 0),
    ).toEqual([])
    expect(session.observe(seen(null, 0), 0)).toEqual([])
    expect(session.end()).toEqual([])
  })

  it('a rewatch from the start after a stop is a new session', () => {
    const session = new Session()
    session.observe(seen(episode('81'), 0), 0)
    session.observe(seen(episode('81'), 50, { ended: true }), 1000)
    expect(session.observe(seen(episode('81'), 49), 2000)).toEqual([])
    expect(actions(session.observe(seen(episode('81'), 1), 3000))).toEqual([
      'start 2',
    ])
  })
})
