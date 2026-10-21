import { storage } from '#imports'
import type { Call, Playing } from './types'

/** The scrobble token (`aaru_scr_…`). Only this extension's background reads it. */
export const tokenItem = storage.defineItem<string | null>('local:token', {
  fallback: null,
})

/** What plays now and what Aaru matched it to, for the popup. */
export interface NowPlaying {
  playing: Playing
  progress: number
  /** The matched title, "Severance (2022)"; null when Aaru could not tell which it is. */
  matched: string | null
  at: number
}
export const nowItem = storage.defineItem<NowPlaying | null>('local:now', {
  fallback: null,
})

/** One finished play, for the popup's Recent list. */
export interface RecentPlay {
  playing: Playing
  result: 'marked' | 'finished' | 'unmatched'
  at: number
}
export const recentItem = storage.defineItem<RecentPlay[]>('local:recent', {
  fallback: [],
})
export const RECENT_LIMIT = 5

/** Stops that could not be sent, retried until a day old. */
export interface PendingCall {
  call: Call
  at: number
}
export const pendingItem = storage.defineItem<PendingCall[]>('local:pending', {
  fallback: [],
})
export const PENDING_MAX_AGE_MS = 24 * 60 * 60 * 1000

/** Where Aaru lives. A development build talks to a local server. */
export const API_BASE: string =
  import.meta.env.WXT_API_BASE ?? 'https://api.aaruapp.com'
export const WEB_BASE: string =
  import.meta.env.WXT_WEB_BASE ?? 'https://aaruapp.com'
