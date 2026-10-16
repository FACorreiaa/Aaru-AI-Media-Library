import { For, Match, Switch } from 'solid-js'
import type { Block, Inline } from '../lib/markdown'

function Inlines(props: { parts: Inline[] }) {
  return (
    <For each={props.parts}>
      {(part) => (
        <Switch fallback={part.text}>
          <Match when={part.kind === 'strong'}>
            <strong class="font-semibold text-ink">{part.text}</strong>
          </Match>
          <Match when={part.kind === 'em'}>
            <em>{part.text}</em>
          </Match>
          <Match when={part.kind === 'link' && part}>
            {(link) => (
              <a
                href={link().href}
                class="font-medium text-accent underline underline-offset-2 hover:no-underline"
              >
                {link().text}
              </a>
            )}
          </Match>
        </Switch>
      )}
    </For>
  )
}

/** Renders parsed Markdown blocks (`lib/markdown`) in the long-form reading style. */
export function Prose(props: { blocks: Block[] }) {
  return (
    <For each={props.blocks}>
      {(block) => (
        <Switch>
          <Match when={block.kind === 'h1' && block}>
            {(heading) => (
              <h1 class="font-display text-4xl leading-tight font-medium tracking-tight text-balance">
                <Inlines parts={heading().text} />
              </h1>
            )}
          </Match>
          <Match when={block.kind === 'h2' && block}>
            {(heading) => (
              <h2 class="mt-10 font-display text-2xl font-medium">
                <Inlines parts={heading().text} />
              </h2>
            )}
          </Match>
          <Match when={block.kind === 'h3' && block}>
            {(heading) => (
              <h3 class="mt-6 font-semibold">
                <Inlines parts={heading().text} />
              </h3>
            )}
          </Match>
          <Match when={block.kind === 'p' && block}>
            {(paragraph) => (
              <p class="mt-4 leading-relaxed text-muted">
                <Inlines parts={paragraph().text} />
              </p>
            )}
          </Match>
          <Match when={block.kind === 'ul' && block}>
            {(list) => (
              <ul class="mt-4 list-disc space-y-2 pl-5 leading-relaxed text-muted marker:text-accent">
                <For each={list().items}>
                  {(item) => (
                    <li>
                      <Inlines parts={item} />
                    </li>
                  )}
                </For>
              </ul>
            )}
          </Match>
        </Switch>
      )}
    </For>
  )
}
