import type { Call, Observation, Playing } from './types'

/** While playing, `start` is sent again this often so Aaru keeps the position. */
export const HEARTBEAT_MS = 5 * 60 * 1000
/** Shorter videos are trailers and previews, never scrobbled. */
export const MIN_DURATION_MS = 2 * 60 * 1000
/** Playing again from before this point after a stop is a rewatch: it starts a new session. */
const REWATCH_BELOW = 10

type State = 'idle' | 'playing' | 'paused' | 'stopped'

/**
 * One tab's playback, turned into scrobbles: `start` when something plays (and every five minutes
 * while it does), `pause` when it pauses, `stop` when it ends, when the next episode starts, or
 * when the tab goes away. Aaru decides from the stop's progress whether it was watched.
 */
export class Session {
  private current: Playing | null = null
  private state: State = 'idle'
  private positionMs = 0
  private durationMs = 0
  private sentAt = 0

  observe(seen: Observation, now: number): Call[] {
    const calls: Call[] = []
    if (seen.playing?.ref !== this.current?.ref) {
      calls.push(...this.end())
      this.current = seen.playing
      this.state = 'idle'
      this.positionMs = 0
      this.durationMs = 0
    }
    const playing = this.current
    if (!playing) return calls
    if (seen.durationMs > 0) {
      this.positionMs = seen.positionMs
      this.durationMs = Math.max(this.durationMs, seen.durationMs)
    }
    if (this.durationMs < MIN_DURATION_MS) return calls
    if (seen.ended) return [...calls, ...this.end()]
    if (this.state === 'stopped') {
      if (seen.paused || this.progress() >= REWATCH_BELOW) return calls
      this.state = 'idle'
    }
    if (!seen.paused) {
      if (this.state !== 'playing' || now - this.sentAt >= HEARTBEAT_MS) {
        this.state = 'playing'
        this.sentAt = now
        calls.push(this.call('start', playing))
      }
    } else if (this.state === 'playing') {
      this.state = 'paused'
      calls.push(this.call('pause', playing))
    }
    return calls
  }

  /** The tab closed, navigated away, or moved on: stop what was playing. */
  end(): Call[] {
    const playing = this.current
    if (!playing || (this.state !== 'playing' && this.state !== 'paused'))
      return []
    this.state = 'stopped'
    return [this.call('stop', playing)]
  }

  private progress(): number {
    if (this.durationMs <= 0) return 0
    return Math.min(100, (this.positionMs / this.durationMs) * 100)
  }

  private call(action: Call['action'], playing: Playing): Call {
    return {
      action,
      playing,
      progress: Math.round(this.progress() * 10) / 10,
      durationMs: this.durationMs,
    }
  }
}
