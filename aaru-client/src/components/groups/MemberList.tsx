import { For, Match, Show, Switch, createSignal, onMount } from 'solid-js'
import { membersByRole } from '../../lib/groups/model'
import {
  removeGroupMember,
  transferGroup,
  updateGroupMember,
} from '../../lib/groups/server'
import type { GroupMember } from '../../lib/groups/server'
import { monogram } from '../../lib/social/model'
import { ConfirmDialog } from './dialogs'
import { Menu, MenuItem, Monogram, useGroup, useShell } from './shell'

type Pending =
  | { kind: 'remove'; member: GroupMember }
  | { kind: 'transfer'; member: GroupMember }

/**
 * MemberList (GRP-004): who is in the group, by role. The owner makes admins, transfers and
 * removes anyone; admins remove members. Aaru joins this list with M5.
 */
export function MemberList(props: { class?: string }) {
  const shell = useShell()
  const scope = useGroup()
  const [open, setOpen] = createSignal<string | null>(null)
  const [pending, setPending] = createSignal<Pending | null>(null)
  const [problem, setProblem] = createSignal<string | null>(null)

  const role = () => scope.detail().group.role
  const groupId = () => scope.detail().group.id
  const sections = () => {
    const grouped = membersByRole(scope.detail().members)
    return [
      { label: 'Owner', members: grouped.owner },
      { label: 'Admins', members: grouped.admins },
      { label: 'Members', members: grouped.members },
    ].filter((s) => s.members.length > 0)
  }

  const canAct = (member: GroupMember) =>
    member.user.userId !== shell.me().userId &&
    (role() === 'owner' || (role() === 'admin' && member.role === 'member'))

  async function setRole(member: GroupMember, next: 'admin' | 'member') {
    setOpen(null)
    setProblem(null)
    try {
      await updateGroupMember({
        data: { groupId: groupId(), userId: member.user.userId, role: next },
      })
      await scope.refresh()
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'That role was not changed.',
      )
    }
  }

  return (
    <div class={props.class}>
      <Show when={problem()}>
        {(text) => (
          <p role="alert" class="px-4 pt-3 text-sm text-danger">
            {text()}
          </p>
        )}
      </Show>
      <For each={sections()}>
        {(section) => (
          <section class="px-2 pt-4">
            <h3 class="px-2 pb-1 text-xs font-semibold tracking-wide text-muted uppercase">
              {section.label} — {section.members.length}
            </h3>
            <ul>
              <For each={section.members}>
                {(member) => (
                  <li class="group/member relative flex items-center gap-3 rounded-lg px-2 py-1.5 hover:bg-surface">
                    <Monogram text={monogram(member.user)} size="sm" />
                    <span class="min-w-0 flex-1">
                      <span class="block truncate text-sm font-medium">
                        {member.user.displayName ?? `@${member.user.handle}`}
                        <Show when={member.user.userId === shell.me().userId}>
                          <span class="ml-1.5 text-xs font-normal text-muted">
                            you
                          </span>
                        </Show>
                      </span>
                      <Show when={member.user.displayName}>
                        <span class="block truncate text-xs text-muted">
                          @{member.user.handle}
                        </span>
                      </Show>
                    </span>
                    <Show when={canAct(member)}>
                      <button
                        type="button"
                        aria-label={`Actions for @${member.user.handle}`}
                        aria-haspopup="menu"
                        onClick={() =>
                          setOpen(
                            open() === member.user.userId
                              ? null
                              : member.user.userId,
                          )
                        }
                        class="grid size-7 place-items-center rounded-md text-muted opacity-0 group-hover/member:opacity-100 hover:text-ink focus-visible:opacity-100 max-lg:opacity-100"
                      >
                        <span aria-hidden="true">⋯</span>
                      </button>
                      <Menu
                        open={open() === member.user.userId}
                        onClose={() => setOpen(null)}
                        class="top-full right-2 mt-1"
                      >
                        <Show when={role() === 'owner'}>
                          <Show
                            when={member.role === 'admin'}
                            fallback={
                              <MenuItem
                                onSelect={() => void setRole(member, 'admin')}
                              >
                                Make admin
                              </MenuItem>
                            }
                          >
                            <MenuItem
                              onSelect={() => void setRole(member, 'member')}
                            >
                              Make member
                            </MenuItem>
                          </Show>
                          <MenuItem
                            onSelect={() => {
                              setOpen(null)
                              setPending({ kind: 'transfer', member })
                            }}
                          >
                            Make owner
                          </MenuItem>
                        </Show>
                        <MenuItem
                          danger
                          onSelect={() => {
                            setOpen(null)
                            setPending({ kind: 'remove', member })
                          }}
                        >
                          Remove from group
                        </MenuItem>
                      </Menu>
                    </Show>
                  </li>
                )}
              </For>
            </ul>
          </section>
        )}
      </For>
      <Show when={scope.detail().invited.length > 0}>
        <section class="px-2 pt-4">
          <h3 class="px-2 pb-1 text-xs font-semibold tracking-wide text-muted uppercase">
            Invited — {scope.detail().invited.length}
          </h3>
          <ul>
            <For each={scope.detail().invited}>
              {(user) => (
                <li class="flex items-center gap-3 px-2 py-1.5 opacity-60">
                  <Monogram text={monogram(user)} size="sm" />
                  <span class="truncate text-sm">@{user.handle}</span>
                </li>
              )}
            </For>
          </ul>
        </section>
      </Show>
      <div class="px-4 pt-4 pb-6">
        <button
          type="button"
          onClick={() => scope.openInvite()}
          class="w-full rounded-full border border-line px-4 py-2 text-sm font-medium text-accent hover:bg-surface"
        >
          Invite friends
        </button>
      </div>

      <Switch>
        <Match
          when={(() => {
            const p = pending()
            return p?.kind === 'remove' ? p : null
          })()}
        >
          {(p) => (
            <ConfirmDialog
              title={`Remove @${p().member.user.handle}?`}
              body="They stop seeing this group. Their messages stay. They are not told why."
              confirm="Remove"
              danger
              onConfirm={async () => {
                await removeGroupMember({
                  data: { groupId: groupId(), userId: p().member.user.userId },
                })
                await scope.refresh()
              }}
              onClose={() => setPending(null)}
            />
          )}
        </Match>
        <Match
          when={(() => {
            const p = pending()
            return p?.kind === 'transfer' ? p : null
          })()}
        >
          {(p) => (
            <ConfirmDialog
              title={`Make @${p().member.user.handle} the owner?`}
              body="They can delete the group and change roles. You become an admin."
              confirm="Make owner"
              onConfirm={async () => {
                await transferGroup({
                  data: { groupId: groupId(), userId: p().member.user.userId },
                })
                await scope.refresh()
                await shell.refresh()
              }}
              onClose={() => setPending(null)}
            />
          )}
        </Match>
      </Switch>
    </div>
  )
}

/** The member list as a sheet, for tablets and phones. */
export function MemberSheet(props: { onClose: () => void }) {
  let dialog: HTMLDialogElement | undefined
  onMount(() => dialog?.showModal())
  const scope = useGroup()
  return (
    <dialog
      ref={dialog}
      aria-label="Members"
      onClose={() => props.onClose()}
      class="group-sheet mt-auto mb-0 max-h-[85dvh] w-full max-w-none overflow-y-auto rounded-t-[24px] bg-paper p-0 text-ink shadow-2xl backdrop:bg-black/40 md:m-auto md:w-[min(26rem,calc(100vw-2rem))] md:rounded-[20px]"
    >
      <div class="sticky top-0 flex items-center justify-between border-b border-line bg-paper px-5 py-4">
        <h2 class="font-display text-xl font-medium">
          Members · {scope.detail().members.length}
        </h2>
        <button
          type="button"
          onClick={() => dialog?.close()}
          class="text-sm font-medium text-muted hover:text-ink"
        >
          Done
        </button>
      </div>
      <MemberList />
    </dialog>
  )
}
