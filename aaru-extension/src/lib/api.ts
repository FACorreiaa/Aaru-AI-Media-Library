import type { Call } from './types'

/** What Aaru made of a scrobble (`POST /v1/scrobble/*`). */
export interface ScrobbleAnswer {
  outcome: 'recorded' | 'watched' | 'stopped' | 'unmatched'
  title?: { id: string; name: string; year?: number }
}

export type SendResult =
  | { kind: 'ok'; answer: ScrobbleAnswer }
  /** The token was revoked or never existed: connect again. */
  | { kind: 'unauthorized' }
  /** Offline, a server error, or an answer Aaru could not read: worth trying again later. */
  | { kind: 'failed'; retry: boolean }

/** Trakt's scrobble body, named by title: these sites have no ids Aaru knows. A YouTube video
 * goes as `video` instead (SCR-009): Aaru shows it as playing and never matches it; a music
 * video carries its track, which Aaru logs as a listen once heard (SCR-011). */
export function body(call: Call) {
  const { playing } = call
  const common = {
    source: playing.source,
    ref: playing.ref,
    progress: call.progress,
    durationMs: call.durationMs > 0 ? call.durationMs : undefined,
  }
  if (playing.type === 'video')
    return {
      ...common,
      video: {
        id: playing.ref,
        title: playing.title,
        channel: playing.channel,
        ...(playing.music ? { music: playing.music } : {}),
      },
    }
  const item = { title: playing.title, year: playing.year }
  return {
    ...common,
    ...(playing.type === 'movie'
      ? { movie: item }
      : {
          show: item,
          episode: {
            season: playing.season,
            number: playing.episode,
            title: playing.episodeTitle,
          },
        }),
  }
}

export async function send(
  base: string,
  token: string,
  call: Call,
): Promise<SendResult> {
  let response: Response
  try {
    response = await fetch(`${base}/v1/scrobble/${call.action}`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body(call)),
    })
  } catch {
    return { kind: 'failed', retry: true }
  }
  if (response.status === 401) return { kind: 'unauthorized' }
  if (!response.ok)
    return {
      kind: 'failed',
      retry: response.status >= 500 || response.status === 429,
    }
  try {
    return { kind: 'ok', answer: (await response.json()) as ScrobbleAnswer }
  } catch {
    return { kind: 'failed', retry: false }
  }
}
