import { OwlEmpty } from '../components/Brand'
import { Link, createFileRoute, useNavigate } from '@tanstack/solid-router'
import { For, Show, createSignal } from 'solid-js'
import { Button, buttonVariants } from '~/components/ui'
import { MentionPill, Monogram, useShell } from '../components/groups/shell'
import { groupMonogram } from '../lib/groups/model'
import { acceptGroupInvite, declineGroupInvite } from '../lib/groups/server'
import type { GroupInvite } from '../lib/groups/server'
import { personLabel } from '../lib/social/model'

// GRP-004 on the web: all groups. On a phone and tablet it lists your groups; everywhere it
// holds waiting invites and the way to make a group. The app shell owns <main>.
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
    <div class="min-w-0 flex-1 overflow-y-auto">
      <div class="px-4 py-8 md:px-8 md:py-12">
        <div class="flex items-end justify-between gap-4">
          <h1 class="font-display text-4xl font-medium tracking-tight">
            Groups
          </h1>
          <Show when={hasHandle() && shell.groups().length > 0}>
            <Button size="sm" onClick={() => shell.openCreate()}>
              New group
            </Button>
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
            <ul class="mt-2 divide-y divide-line rounded-card bg-surface px-4">
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
                      <Button
                        variant="ghost"
                        size="sm"
                        disabled={busy() !== null}
                        onClick={() => void answer(invite, false)}
                        class="px-3"
                      >
                        Decline
                      </Button>
                      <Button
                        size="sm"
                        disabled={busy() !== null || !hasHandle()}
                        onClick={() => void answer(invite, true)}
                      >
                        Join
                      </Button>
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
            <OwlEmpty
              class="rise mt-6"
              title="Make a place to talk with friends."
              body="Choose a handle first, so friends can see who is talking."
              action={
                <Link to="/app/settings/account" class={buttonVariants()}>
                  Choose a handle
                </Link>
              }
            />
          }
        >
          <Show
            when={shell.groups().length > 0}
            fallback={
              <OwlEmpty
                class="rise mt-6"
                title="Make a place to talk with friends."
                body="A group starts with #general. Only friends you invite can join, and nobody can find it otherwise."
                action={
                  <div class="flex flex-wrap justify-center gap-3">
                    <Button onClick={() => shell.openCreate()}>
                      Create a group
                    </Button>
                    <Link
                      to="/app/settings/friends"
                      class={buttonVariants({ variant: 'outline' })}
                    >
                      Add friends
                    </Link>
                  </div>
                }
              />
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
    </div>
  )
}
