import { For, Match, Show, Switch, createSignal } from 'solid-js'
import {
  Button,
  Dialog,
  DialogContent,
  DialogPortal,
  DialogTitle,
  buttonVariants,
} from '~/components/ui'
import { membersByRole } from '../../lib/groups/model'
import {
  removeGroupMember,
  transferGroup,
  updateGroupMember,
} from '../../lib/groups/server'
import type { GroupMember } from '../../lib/groups/server'
import { monogram } from '../../lib/social/model'
import { AaruAvatar } from './AgentParts'
import { ConfirmDialog, useClosable } from './dialogs'
import { Menu, MenuItem, Monogram, useGroup, useShell } from './shell'

type Pending =
  | { kind: 'remove'; member: GroupMember }
  | { kind: 'transfer'; member: GroupMember }

/**
 * MemberList (GRP-004): who is in the group, by role. The owner makes admins, transfers and
 * removes anyone; admins remove members. Aaru is listed first when it answers in this group.
 */
export function MemberList(props: { class?: string }) {
  const shell = useShell()
  const scope = useGroup()
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
      <Show when={scope.detail().agent}>
        <section class="px-2 pt-4">
          <h3 class="px-2 pb-1 eyebrow">Assistant</h3>
          <details class="group/aaru rounded-lg px-2 py-1.5 hover:bg-surface open:bg-surface">
            <summary
              title="Aaru reads this channel's recent group messages, and your own library when it helps. It can't change anything."
              class="flex cursor-pointer list-none items-center gap-3 [&::-webkit-details-marker]:hidden"
            >
              <AaruAvatar size="sm" />
              <span class="min-w-0 flex-1">
                <span class="block truncate text-sm font-medium">Aaru</span>
                <span class="block truncate text-xs text-muted">
                  Answers when tagged
                </span>
              </span>
            </summary>
            <p class="mt-2 pb-1 text-xs leading-relaxed text-muted">
              Tag @aaru to ask about films, shows, anime and books. It reads
              this channel's recent group messages, and your own library when it
              helps, never anyone else's. It can't change anything.
            </p>
          </details>
        </section>
      </Show>
      <For each={sections()}>
        {(section) => (
          <section class="px-2 pt-4">
            <h3 class="px-2 pb-1 eyebrow">
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
                      <Menu
                        label={`Actions for @${member.user.handle}`}
                        trigger={<span aria-hidden="true">⋯</span>}
                        triggerClass={`${buttonVariants({ variant: 'ghost', size: 'icon-sm' })} rounded-md text-muted opacity-0 group-hover/member:opacity-100 hover:text-ink focus-visible:opacity-100 data-[expanded]:opacity-100 max-lg:opacity-100`}
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
                            onSelect={() =>
                              setPending({ kind: 'transfer', member })
                            }
                          >
                            Make owner
                          </MenuItem>
                        </Show>
                        <MenuItem
                          danger
                          onSelect={() =>
                            setPending({ kind: 'remove', member })
                          }
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
          <h3 class="px-2 pb-1 eyebrow">
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
        <Button
          variant="outline"
          size="sm"
          onClick={() => scope.openInvite()}
          class="w-full border-line font-medium text-accent"
        >
          Invite friends
        </Button>
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
              body="They stop seeing this group. What they wrote stays. They are not told why."
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

/** The member list as a sheet, for tablets and phones (WEB-002: a Dialog, a bottom sheet on a
 * phone). */
export function MemberSheet(props: { onClose: () => void }) {
  const dialog = useClosable(() => props.onClose())
  const scope = useGroup()
  return (
    <Dialog
      open={dialog.open()}
      onOpenChange={(open) => {
        if (!open) dialog.close()
      }}
    >
      <DialogPortal>
        <DialogContent
          placement="sheet"
          showCloseButton={false}
          class="block w-[min(26rem,calc(100vw-2rem))] gap-0 p-0 sm:max-w-none"
        >
          <div class="sticky top-0 z-10 flex items-center justify-between border-b border-line bg-paper px-5 py-4">
            <DialogTitle class="text-xl">
              Members · {scope.detail().members.length}
            </DialogTitle>
            <Button variant="ghost" size="sm" onClick={dialog.close}>
              Done
            </Button>
          </div>
          <MemberList />
        </DialogContent>
      </DialogPortal>
    </Dialog>
  )
}
