import { Show, children } from 'solid-js'
import type { JSX } from 'solid-js'
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from '~/components/ui'
import { cn } from '~/lib/utils'

/**
 * One section of a Settings page (WEB-007): shadcn-solid's Card parts on Aaru's surface, a
 * display-face title, an optional line under it, the controls, and an optional footer note.
 */
export function SettingsSection(props: {
  id?: string
  title: string
  description?: JSX.Element
  footer?: JSX.Element
  tone?: 'danger'
  class?: string
  children?: JSX.Element
}) {
  // Each JSX prop is resolved once, here. Reading `props.children` both in a `when` and in
  // the body builds the children twice, and the server and the browser then number their
  // hydration keys differently: the page re-creates its DOM, and a Kobalte Button (a
  // `Dynamic`) inside it throws "t is not a function" on hydration.
  const description = children(() => props.description)
  const content = children(() => props.children)
  const footer = children(() => props.footer)
  return (
    <Card
      id={props.id}
      class={cn(
        'mt-6 scroll-mt-6 gap-4 py-5 first:mt-0',
        props.tone === 'danger' && 'ring-1 ring-danger/30',
        props.class,
      )}
      aria-labelledby={props.id ? `${props.id}-title` : undefined}
    >
      <CardHeader class="gap-1 px-5">
        <CardTitle>
          <h2
            id={props.id ? `${props.id}-title` : undefined}
            class={cn(
              'font-display text-xl leading-tight font-medium',
              props.tone === 'danger' && 'text-danger',
            )}
          >
            {props.title}
          </h2>
        </CardTitle>
        <Show when={description()}>
          <CardDescription class="max-w-prose text-muted">
            {description()}
          </CardDescription>
        </Show>
      </CardHeader>
      <Show when={content()}>
        <CardContent class="px-5">{content()}</CardContent>
      </Show>
      <Show when={footer()}>
        <CardFooter class="px-5 text-sm text-muted">{footer()}</CardFooter>
      </Show>
    </Card>
  )
}
