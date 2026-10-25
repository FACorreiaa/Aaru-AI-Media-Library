import { Link } from '@tanstack/solid-router'
import { Match, Switch } from 'solid-js'
import type { JSX } from 'solid-js'
import type { CatalogHit } from '../lib/library/model'
import { previewParams } from '../lib/title/preview'

/**
 * LIB-006: the way from a title to its page. In the library it opens the Title room; otherwise
 * its catalog page, which adds nothing until Add. A title with no id to name it by stays plain.
 */
export function TitleLink(props: {
  hit?: Pick<CatalogHit, 'type' | 'ids'>
  libraryItemId?: string | null
  class?: string
  'aria-label'?: string
  onClick?: () => void
  children: JSX.Element
}) {
  return (
    <Switch fallback={<div class={props.class}>{props.children}</div>}>
      <Match when={props.libraryItemId}>
        {(id) => (
          <Link
            to="/app/title/$id"
            params={{ id: id() }}
            class={props.class}
            aria-label={props['aria-label']}
            onClick={() => props.onClick?.()}
          >
            {props.children}
          </Link>
        )}
      </Match>
      <Match when={props.hit && previewParams(props.hit)}>
        {(params) => (
          <Link
            to="/app/catalog/$type/$provider/$ref"
            params={params()}
            class={props.class}
            aria-label={props['aria-label']}
            onClick={() => props.onClick?.()}
          >
            {props.children}
          </Link>
        )}
      </Match>
    </Switch>
  )
}
