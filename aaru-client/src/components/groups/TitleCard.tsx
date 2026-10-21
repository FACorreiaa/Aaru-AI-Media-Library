import { Link } from '@tanstack/solid-router'
import { For, Show, createSignal, onMount } from 'solid-js'
import { progressLabel } from '../../lib/groups/kinds'
import {
  getChannelProgress,
  setShareProgress,
} from '../../lib/groups/kinds-server'
import type { ChannelProgress } from '../../lib/groups/kinds-server'
import type { Channel } from '../../lib/groups/server'
import { kindOf } from '../../lib/library/model'
import { useRealtime } from '../../lib/realtime/socket'
import { monogram } from '../../lib/social/model'
import { Poster } from '../Poster'
import { useGroup, useShell } from './shell'

/**
 * TitleCard (GRP-007): the head of a title channel. The title, where I am in it, where the
 * members who share their progress here are, and my own switch for that. Off by default.
 */
export function TitleCard(props: { channel: Channel }) {
  const shell = useShell()
  const scope = useGroup()
  const ref = () => ({
    groupId: scope.detail().group.id,
    channelId: props.channel.id,
  })
  const [progress, setProgress] = createSignal<ChannelProgress | null>(null)
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  const sharing = () => scope.detail().group.shareProgress
  const title = () => progress()?.title ?? props.channel.title

  async function load() {
    try {
      setProgress(await getChannelProgress({ data: ref() }))
    } catch {
      // The card still shows the title it came with.
    }
  }

  onMount(() => void load())
  useRealtime((event) => {
    if (event.type === 'ready') return void load()
    if (event.groupId !== ref().groupId) return
    // Someone switched sharing, or progress changed with a read on another device.
    if (event.type === 'group.updated' || event.type === 'read') void load()
  })

  async function toggle() {
    setBusy(true)
    setProblem(null)
    try {
      const summary = await setShareProgress({
        data: { groupId: ref().groupId, shareProgress: !sharing() },
      })
      scope.setDetail((detail) => ({ ...detail, group: summary }))
      await shell.refresh()
    } catch (error) {
      setProblem(error instanceof Error ? error.message : 'Not saved.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Show when={title()}>
      {(t) => (
        <section
          aria-label="About this title"
          class="flex shrink-0 gap-3 border-b border-line bg-surface/40 px-4 py-3 md:px-6"
        >
          <Link
            to="/app/title/$id"
            params={{ id: t().id }}
            class="shrink-0"
            aria-label={`Open ${t().title}`}
          >
            <Poster
              url={t().posterUrl}
              kind={kindOf(t().type, t().isAnime)}
              class="w-12"
            />
          </Link>
          <div class="min-w-0 flex-1">
            <p class="truncate font-display text-lg leading-tight font-medium">
              {t().title}
              <Show when={t().year}>
                <span class="ml-1.5 font-sans text-sm font-normal text-muted">
                  {t().year}
                </span>
              </Show>
            </p>
            <p class="mt-0.5 text-xs text-muted">
              You:{' '}
              <span class="font-semibold text-ink">
                {progressLabel(progress()?.mine, kindOf(t().type, t().isAnime))}
              </span>
              <span class="mx-1.5">·</span>
              Spoilers past your progress stay veiled.
            </p>
            <Show when={(progress()?.members.length ?? 0) > 0}>
              <ul
                class="mt-2 flex flex-wrap gap-1.5"
                aria-label="Members' progress"
              >
                <For each={progress()?.members}>
                  {(member) => (
                    <li class="flex items-center gap-1.5 rounded-full bg-paper py-0.5 pr-2.5 pl-0.5 text-xs">
                      <span
                        aria-hidden="true"
                        class="grid size-5 place-items-center rounded-full bg-medallion/20 font-display text-[9px] font-medium"
                      >
                        {monogram(member.user)}
                      </span>
                      <span class="font-medium">
                        {member.user.displayName ?? `@${member.user.handle}`}
                      </span>
                      <span class="text-muted">
                        {progressLabel(member, kindOf(t().type, t().isAnime))}
                      </span>
                    </li>
                  )}
                </For>
              </ul>
            </Show>
          </div>
          <label class="flex shrink-0 cursor-pointer flex-col items-end gap-1 text-right">
            <span class="flex items-center gap-2 text-xs font-medium">
              <span class="hidden sm:inline">Share my progress</span>
              <span class="sm:hidden">Share</span>
              <input
                type="checkbox"
                role="switch"
                checked={sharing()}
                disabled={busy()}
                onChange={() => void toggle()}
                class="peer sr-only"
              />
              <span
                aria-hidden="true"
                class={`relative h-5 w-9 rounded-full transition-colors peer-focus-visible:ring-2 peer-focus-visible:ring-accent ${sharing() ? 'bg-accent' : 'bg-line'}`}
              >
                <span
                  class={`absolute top-0.5 size-4 rounded-full bg-paper shadow transition-[left] ${sharing() ? 'left-[18px]' : 'left-0.5'}`}
                />
              </span>
            </span>
            <span class="hidden max-w-44 text-[11px] leading-tight text-muted md:block">
              {sharing()
                ? 'Members here see how far you are.'
                : 'Off: nobody here sees how far you are.'}
            </span>
            <Show when={problem()}>
              {(text) => (
                <span role="alert" class="text-[11px] text-danger">
                  {text()}
                </span>
              )}
            </Show>
          </label>
        </section>
      )}
    </Show>
  )
}
