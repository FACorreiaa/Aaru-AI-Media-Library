import { Show } from 'solid-js'
import {
  Pagination,
  PaginationEllipsis,
  PaginationItem,
  PaginationItems,
  PaginationNext,
  PaginationPrevious,
  TextField,
  TextFieldInput,
  TextFieldLabel,
} from '~/components/ui'
import { cx } from '~/lib/cva'
import { pageCount } from '../lib/paging'

// LIB-005: the filter box and the page numbers Library, Lists and Discover share. The filter
// searches everything the page holds; the numbers show 20 at a time (`lib/paging`).

/** A search box that narrows what the page shows as you type. */
export function FilterField(props: {
  label: string
  placeholder: string
  value: string
  onChange: (value: string) => void
  class?: string
}) {
  return (
    <TextField
      value={props.value}
      onChange={props.onChange}
      class={cx('w-full sm:max-w-xs', props.class)}
    >
      <TextFieldLabel class="sr-only">{props.label}</TextFieldLabel>
      <TextFieldInput
        type="search"
        placeholder={props.placeholder}
        autocomplete="off"
        class="min-h-9 w-full rounded-full px-4"
      />
    </TextField>
  )
}

/** ‹ 1 2 3 … 9 › under a list; nothing when it fits on one page. */
export function PageControls(props: {
  page: number
  total: number
  label: string
  onPage: (page: number) => void
}) {
  return (
    <Show when={pageCount(props.total) > 1}>
      <Pagination
        class="mt-8"
        aria-label={props.label}
        count={pageCount(props.total)}
        page={props.page}
        onPageChange={props.onPage}
        siblingCount={1}
        showFirst
        showLast
        itemComponent={(item) => (
          <PaginationItem page={item.page}>{item.page}</PaginationItem>
        )}
        ellipsisComponent={() => <PaginationEllipsis />}
      >
        <PaginationPrevious aria-label="Previous page" />
        <PaginationItems />
        <PaginationNext aria-label="Next page" />
      </Pagination>
    </Show>
  )
}
