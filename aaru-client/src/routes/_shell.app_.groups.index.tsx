import { Link, createFileRoute, useNavigate } from '@tanstack/solid-router'
import { For, Show, createSignal } from 'solid-js'
import { MentionPill, Monogram, useShell } from '../components/groups/shell'
import { groupMonogram } from '../lib/groups/model'
import { acceptGroupInvite, declineGroupInvite } from '../lib/groups/server'
import type { GroupInvite } from '../lib/groups/server'
import { personLabel } from '../lib/social/model'

// GRP-004 on the web: groups home. On a phone and tablet it lists your groups; everywhere it
// holds waiting invites and the way to make a group.
export const Route = createFileRoute('/_shell/app_/groups/')({
  component: GroupsHome,
})

function GroupsHome() {
  const shell = useShell()
  const navigate = useNavigate()
  const [busy, setBusy] = createSignal<string | null>(null)
  const [problem, setProblem] = createSignal<string | null>(null)
  const hasHandle = () => Boolean(shell.me().handle)

  async function answer(invite: GroupInvite, accept: boolean) {
    setBusy(invite.id)
    setProblem(null)
    try {
      if (accept) {
        const group = await acceptGroupInvite({ data: { id: invite.id } })
        await shell.refresh()
        await navigate({
          to: '/app/groups/$groupId/$channelId',
          params: { groupId: group.id, channelId: group.defaultChannelId },
        })
      } else {
        await declineGroupInvite({ data: { id: invite.id } })
        shell.setInvites(shell.invites().filter((i) => i.id !== invite.id))
      }
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'That invite did not work.',
      )
    } finally {
      setBusy(null)
    }
  }

  return (
    <main class="min-w-0 flex-1 overflow-y-auto">
      <div class="mx-auto max-w-2xl px-5 py-8 md:px-8 md:py-12">
        <div class="flex items-end justify-between gap-4">
          <h1 class="font-display text-4xl font-medium tracking-tight">
            Groups
          </h1>
          <Show when={hasHandle() && shell.groups().length > 0}>
            <button
              type="button"
              onClick={() => shell.openCreate()}
              class="rounded-full bg-accent px-4 py-2 text-sm font-semibold text-on-accent"
            >
              New group
            </button>
          </Show>
        </div>

        <Show when={problem()}>
          {(text) => (
            <p role="alert" class="mt-4 text-sm text-danger">
              {text()}
            </p>
          )}
        </Show>

        <Show when={shell.invites().length > 0}>
          <section class="rise mt-8" aria-labelledby="invites-heading">
            <h2
              id="invites-heading"
              class="text-xs font-semibold tracking-wide text-muted uppercase"
            >
              Invites
            </h2>
            <ul class="mt-2 divide-y divide-line rounded-[20px] bg-surface px-4">
              <For each={shell.invites()}>
                {(invite) => (
                  <li class="flex flex-wrap items-center justify-between gap-3 py-3.5">
                    <span class="flex min-w-0 items-center gap-3">
                      <Monogram text={groupMonogram(invite.groupName)} />
                      <span class="min-w-0">
                        <span class="block truncate font-medium">
                          {invite.groupName}
                        </span>
                        <span class="block truncate text-sm text-muted">
                          From {personLabel(invite.inviter)}
                        </span>
                      </span>
                    </span>
                    <span class="flex gap-2">
                      <button
                        type="button"
                        disabled={busy() !== null}
                        onClick={() => void answer(invite, false)}
                        class="rounded-full px-3 py-1.5 text-sm font-medium text-muted hover:text-ink disabled:opacity-40"
                      >
                        Decline
                      </button>
                      <button
                        type="button"
                        disabled={busy() !== null || !hasHandle()}
                        onClick={() => void answer(invite, true)}
                        class="rounded-full bg-accent px-4 py-1.5 text-sm font-semibold text-on-accent disabled:opacity-40"
                      >
                        Join
                      </button>
                    </span>
                  </li>
                )}
              </For>
            </ul>
          </section>
        </Show>

        <Show
          when={hasHandle()}
          fallback={
            <div class="rise mt-12 text-center">
              <p class="font-display text-2xl">
                Make a place to talk with friends.
              </p>
              <p class="mx-auto mt-2 max-w-sm text-muted">
                Choose a handle first, so friends can see who is talking.
              </p>
              <Link
                to="/app/settings/account"
                hash="profile"
                class="mt-6 inline-block rounded-full bg-accent px-5 py-2.5 font-semibold text-on-accent"
              >
                Choose a handle
              </Link>
            </div>
          }
        >
          <Show
            when={shell.groups().length > 0}
            fallback={
              <div class="rise mt-12 text-center">
                <p class="font-display text-2xl">
                  Make a place to talk with friends.
                </p>
                <p class="mx-auto mt-2 max-w-sm text-muted">
                  A group starts with #general. Only friends you invite can
                  join, and nobody can find it otherwise.
                </p>
                <button
                  type="button"
                  onClick={() => shell.openCreate()}
                  class="mt-6 rounded-full bg-accent px-5 py-2.5 font-semibold text-on-accent"
                >
                  Create a group
                </button>
              </div>
            }
          >
            <section class="mt-8 lg:hidden" aria-label="Your groups">
              <ul class="divide-y divide-line">
                <For each={shell.groups()}>
                  {(group) => (
                    <li>
                      <Link
                        to="/app/groups/$groupId"
                        params={{ groupId: group.id }}
                        class="flex items-center gap-3 py-3"
                      >
                        <Monogram text={groupMonogram(group.name)} size="lg" />
                        <span
                          class={`min-w-0 flex-1 truncate text-lg ${group.unread > 0 ? 'font-semibold' : 'font-medium'}`}
                        >
                          {group.name}
                        </span>
                        <Show when={group.unread > 0 && group.mentions === 0}>
                          <span
                            class="size-2.5 rounded-full bg-accent"
                            aria-label="Unread"
                          />
                        </Show>
                        <MentionPill count={group.mentions} />
                      </Link>
                    </li>
                  )}
                </For>
              </ul>
            </section>
            <p class="mt-12 hidden text-center text-muted lg:block">
              Pick a group on the left, or make a new one.
            </p>
          </Show>
        </Show>
      </div>
    </main>
  )
}
