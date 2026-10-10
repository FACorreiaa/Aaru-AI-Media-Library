<script module lang="ts">
	/** Import sources in the order CLAUDE.md applies them. Names only: vendors are sources, not domain terms. */
	export const IMPORT_SOURCES = [
		'Trakt',
		'IMDb',
		'Letterboxd',
		'Goodreads',
		'Pogdesign CAT',
		'TV Time',
		'MyAnimeList',
		'AniList'
	] as const;
</script>

<script lang="ts">
	let { sources = IMPORT_SOURCES }: { sources?: readonly string[] } = $props();
</script>

<ul class="flex flex-wrap gap-2.5" aria-label="Import sources">
	{#each sources as source (source)}
		<li
			class="rounded-full border border-line bg-paper px-4 py-2 text-sm font-medium tracking-tight text-ink"
		>
			{source}
		</li>
	{/each}
</ul>
