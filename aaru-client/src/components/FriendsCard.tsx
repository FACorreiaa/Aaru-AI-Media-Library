import { Link } from '@tanstack/solid-router'
import { Show, createSignal } from 'solid-js'
import {
  Switch,
  SwitchControl,
  SwitchDescription,
  SwitchInput,
  SwitchLabel,
  SwitchThumb,
} from '~/components/ui'
import { saveSocialSettings } from '../lib/social/server'
import { SettingsSection } from './settings/SettingsSection'

// Settings → Friends & privacy: your handle, the way to Friends, and whether friends see your
// library (SOC-001). Strangers never see anything, whatever this says.
export function FriendsCard(props: {
  handle?: string
  shareLibraryWithFriends: boolean
}) {
  const [sharing, setSharing] = createSignal(props.shareLibraryWithFriends)
  const [problem, setProblem] = createSignal<string | null>(null)

  async function change(next: boolean) {
    setSharing(next)
    setProblem(null)
    try {
      await saveSocialSettings({ data: { shareLibraryWithFriends: next } })
    } catch (error) {
      setSharing(!next)
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
      <Switch
        class="flex items-start gap-3 text-sm"
        checked={sharing()}
        onChange={(next) => void change(next)}
      >
        <SwitchInput />
        <SwitchControl>
          <SwitchThumb />
        </SwitchControl>
        <span>
          <SwitchLabel class="cursor-pointer">
            Show my library to friends
          </SwitchLabel>
          <SwitchDescription class="block text-xs">
            Friends see what you’re watching, what you finished and what you
            share. Nobody else ever does.
          </SwitchDescription>
        </span>
      </Switch>
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
