import { browser, defineBackground } from '#imports'
import type { Browser } from '#imports'
import { send } from '../lib/api'
import { PLAYER_PORT, TOKEN } from '../lib/protocol'
import { Session } from '../lib/session'
import {
  API_BASE,
  PENDING_MAX_AGE_MS,
  RECENT_LIMIT,
  nowItem,
  pendingItem,
  recentItem,
  tokenItem,
} from '../lib/store'
import type { RecentPlay } from '../lib/store'
import type { Call, Observation } from '../lib/types'

const RETRY_ALARM = 'aaru-retry'

// SCR-007: every streaming tab reports what it sees on a port; each port gets a Session that turns
// it into scrobbles. The port closing (tab closed, page left) stops what was playing. Stops that
// cannot be sent are kept and retried for a day. The toolbar badge is the only signal: ✓ matched,
// ? not matched, ! connect again.
export default defineBackground(() => {
  browser.runtime.onConnect.addListener((port) => {
    if (port.name !== PLAYER_PORT) return
    const session = new Session()
    // One tab's calls go out in order: a stop never overtakes its start.
    let queue = Promise.resolve()
    const run = (calls: Call[]) => {
      for (const call of calls) queue = queue.then(() => deliver(call))
    }
    port.onMessage.addListener((message: Observation) => {
      run(session.observe(message, Date.now()))
    })
    port.onDisconnect.addListener(() => run(session.end()))
  })

  browser.runtime.onMessage.addListener(
    (
      message: { type?: string; secret?: unknown },
      sender: Browser.runtime.MessageSender,
    ) => {
      if (message.type !== TOKEN || sender.id !== browser.runtime.id) return
      if (
        typeof message.secret !== 'string' ||
        !message.secret.startsWith('aaru_scr_')
      )
        return
      return tokenItem.setValue(message.secret).then(() => {
        void badge('')
        return true
      })
    },
  )

  void browser.alarms.create(RETRY_ALARM, { periodInMinutes: 15 })
  browser.alarms.onAlarm.addListener((alarm) => {
    if (alarm.name === RETRY_ALARM) void retryPending()
  })
  void retryPending()
})

async function deliver(call: Call): Promise<void> {
  const token = await tokenItem.getValue()
  if (!token) {
    await badge('!')
    return
  }
  const result = await send(API_BASE, token, call)
  if (result.kind === 'unauthorized') {
    await tokenItem.setValue(null)
    await badge('!')
    return
  }
  if (result.kind === 'failed') {
    if (result.retry && call.action === 'stop') {
      const pending = await pendingItem.getValue()
      await pendingItem.setValue([...pending, { call, at: Date.now() }])
    }
    return
  }
  const { outcome, title } = result.answer
  const matched = title
    ? title.year
      ? `${title.name} (${title.year})`
      : title.name
    : null
  await badge(outcome === 'unmatched' ? '?' : '✓')
  if (call.action !== 'stop') {
    await nowItem.setValue({
      playing: call.playing,
      progress: call.progress,
      matched,
      at: Date.now(),
    })
    return
  }
  await nowItem.setValue(null)
  if (outcome === 'stopped') return
  const play: RecentPlay = {
    playing: call.playing,
    result:
      outcome === 'unmatched'
        ? 'unmatched'
        : call.playing.type === 'movie'
          ? 'finished'
          : 'marked',
    at: Date.now(),
  }
  const recent = await recentItem.getValue()
  await recentItem.setValue([play, ...recent].slice(0, RECENT_LIMIT))
}

async function retryPending(): Promise<void> {
  const pending = await pendingItem.getValue()
  if (pending.length === 0) return
  await pendingItem.setValue([])
  const fresh = pending.filter((p) => Date.now() - p.at < PENDING_MAX_AGE_MS)
  for (const { call } of fresh) await deliver(call)
}

type Badge = '' | '✓' | '?' | '!'

const BADGE_COLORS: Record<Exclude<Badge, ''>, string> = {
  '✓': '#1f6970',
  '?': '#4b6668',
  '!': '#a33a2c',
}

async function badge(text: Badge): Promise<void> {
  await browser.action.setBadgeText({ text })
  if (text)
    await browser.action.setBadgeBackgroundColor({ color: BADGE_COLORS[text] })
}
