<script module>
	import { defineMeta } from '@storybook/addon-svelte-csf';
	import ImportSources from './ImportSources.svelte';
	import '../../../routes/layout.css';

	const { Story } = defineMeta({
		title: 'Landing/ImportSources',
		component: ImportSources,
		tags: ['autodocs']
	});
</script>

<Story name="All sources" />

<Story name="Two sources" args={{ sources: ['Trakt', 'Goodreads'] }} />
