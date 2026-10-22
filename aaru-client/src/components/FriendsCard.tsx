import { Link } from '@tanstack/solid-router'
import { For, Show, createSignal } from 'solid-js'
import type { Accessor, Setter } from 'solid-js'
import {
  Switch,
  SwitchControl,
  SwitchDescription,
  SwitchInput,
  SwitchLabel,
  SwitchThumb,
} from '~/components/ui'
import { saveSocialSettings } from '../lib/social/server'
import type { SocialSettings } from '../lib/social/server'
import { SettingsSection } from './settings/SettingsSection'

type Key = keyof SocialSettings

// Settings → Friends & privacy: your handle, the way to Friends, whether friends see your
// library (SOC-001), your badges and level, and whether you join the weekly friends board
// (GAM-005). Strangers never see anything, whatever these say.
export function FriendsCard(props: {
  handle?: string
  settings: SocialSettings
}) {
  const [problem, setProblem] = createSignal<string | null>(null)
  const switches: {
    key: Key
    label: string
    description: string
    value: [Accessor<boolean>, Setter<boolean>]
  }[] = [
    {
      key: 'shareLibraryWithFriends',
      label: 'Show my library to friends',
      description:
        'Friends see what you’re watching, what you finished and what you share. Nobody else ever does.',
      value: createSignal(props.settings.shareLibraryWithFriends),
    },
    {
      key: 'showAchievementsToFriends',
      label: 'Show my badges and level to friends',
      description:
        'On your profile, for friends only. Badges about your notes and what you own stay yours.',
      value: createSignal(props.settings.showAchievementsToFriends ?? true),
    },
    {
      key: 'leaderboardOptIn',
      label: 'Join the weekly friends board',
      description:
        'You see this week’s points beside friends who joined too, and they see yours. Never anyone else.',
      value: createSignal(props.settings.leaderboardOptIn ?? false),
    },
  ]

  async function change(
    key: Key,
    [, set]: [Accessor<boolean>, Setter<boolean>],
    next: boolean,
  ) {
    set(next)
    setProblem(null)
    try {
      await saveSocialSettings({ data: { [key]: next } })
    } catch (error) {
      set(!next)
      setProblem(error instanceof Error ? error.message : 'That was not saved.')
    }
  }

  return (
    <SettingsSection
      id="profile"
      title="Friends"
      description={
        <>
          <Show when={props.handle} fallback={<span>No handle yet.</span>}>
            {(handle) => (
              <>
                Your handle{' '}
                <span class="font-medium text-ink">@{handle()}</span>.
              </>
            )}
          </Show>{' '}
          <Link
            to="/app/friends"
            class="font-semibold text-accent hover:underline"
          >
            Friends, invites and requests
          </Link>
        </>
      }
    >
      <div class="flex flex-col gap-5">
        <For each={switches}>
          {(item) => (
            <Switch
              class="flex items-start gap-3 text-sm"
              checked={item.value[0]()}
              onChange={(next) => void change(item.key, item.value, next)}
            >
              <SwitchInput />
              <SwitchControl>
                <SwitchThumb />
              </SwitchControl>
              <span>
                <SwitchLabel class="cursor-pointer">{item.label}</SwitchLabel>
                <SwitchDescription class="block text-xs">
                  {item.description}
                </SwitchDescription>
              </span>
            </Switch>
          )}
        </For>
      </div>
      <Show when={problem()}>
        {(message) => (
          <p role="alert" class="mt-3 text-sm text-danger">
            {message()}
          </p>
        )}
      </Show>
    </SettingsSection>
  )
}
