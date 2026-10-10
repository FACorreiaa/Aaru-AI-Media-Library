<script lang="ts">
	import { m } from '#lib/paraglide/messages.js';
	import { SITE_URL } from '#lib/site.js';
	import type { Path } from '$app/types';
	import { resolve } from '$app/paths';
	import { localizeHref } from '#lib/paraglide/runtime.js';
	import ImportSources from '#lib/components/landing/ImportSources.svelte';
	import wordmark from '#lib/assets/brand/wordmark.webp';
	import mascot from '#lib/assets/brand/mascot.webp';
	import mascot2x from '#lib/assets/brand/mascot@2x.webp';
	import reedMark from '#lib/assets/brand/reed-mark.webp';
	import appIcon from '#lib/assets/brand/app-icon.webp';

	const statuses = [m.status_wishlist, m.status_in_progress, m.status_finished, m.status_dropped];
	const faqs = [
		[m.faq_public_q, m.faq_public_a],
		[m.faq_export_q, m.faq_export_a],
		[m.faq_import_q, m.faq_import_a],
		[m.faq_anime_q, m.faq_anime_a],
		[m.faq_when_q, m.faq_when_a],
		[m.faq_price_q, m.faq_price_a]
	];
</script>

<svelte:head>
	<title>{m.meta_title()}</title>
	<meta name="description" content={m.meta_description()} />
	<meta property="og:type" content="website" />
	<meta property="og:title" content={m.meta_title()} />
	<meta property="og:description" content={m.meta_description()} />
	<meta property="og:image" content="{SITE_URL}/og.jpg" />
	<meta name="twitter:card" content="summary_large_image" />
	<link rel="preload" as="image" href={mascot} imagesrcset="{mascot} 1x, {mascot2x} 2x" />
</svelte:head>

<header class="mx-auto flex h-18 max-w-6xl items-center justify-between px-5 md:px-8">
	<a href={resolve(localizeHref('/') as Path)} class="block" aria-label="Aaru">
		<img src={wordmark} alt="Aaru" width="656" height="263" class="h-8 w-auto md:h-9" />
	</a>
	<nav class="flex items-center gap-6 text-sm font-medium text-muted">
		<a href="#how" class="transition-colors hover:text-ink">{m.nav_how()}</a>
		<a href="#faq" class="transition-colors hover:text-ink">{m.nav_faq()}</a>
	</nav>
</header>

<main>
	<!-- Hero -->
	<section
		class="mx-auto grid max-w-6xl items-center gap-10 px-5 pt-6 pb-16 md:grid-cols-[1.05fr_0.95fr] md:px-8 md:pt-10 md:pb-24"
	>
		<div class="order-2 md:order-1">
			<h1
				class="rise max-w-[14ch] font-display text-[2.6rem] leading-[1.05] font-medium tracking-tight text-balance md:text-6xl lg:text-[4.25rem]"
			>
				{m.hero_title()}
			</h1>
			<p class="rise mt-6 max-w-[46ch] text-lg leading-relaxed text-muted" style="--delay:80ms">
				{m.hero_body()}
			</p>
			<div class="rise mt-9 flex flex-wrap items-center gap-x-6 gap-y-4" style="--delay:160ms">
				<a
					href="#how"
					class="inline-flex items-center rounded-full bg-accent px-6 py-3.5 text-base font-semibold whitespace-nowrap text-on-accent shadow-[0_8px_24px_-12px_rgb(31_105_112/0.6)] transition-transform hover:-translate-y-0.5 active:translate-y-0 active:scale-[0.98]"
				>
					{m.hero_cta()}
				</a>
				<span class="text-sm font-medium text-muted">{m.hero_platforms()}</span>
			</div>
		</div>
		<div class="rise order-1 flex justify-center md:order-2" style="--delay:120ms">
			<div class="relative aspect-square w-[min(78vw,30rem)]">
				<div class="absolute inset-[6%] rounded-full bg-medallion"></div>
				<img
					src={mascot}
					srcset="{mascot} 1x, {mascot2x} 2x"
					alt={m.mascot_alt()}
					width="720"
					height="794"
					fetchpriority="high"
					class="absolute inset-0 h-full w-full object-contain"
				/>
			</div>
		</div>
	</section>

	<!-- Imports: easy in, easy out -->
	<section id="how" class="scroll-mt-6 bg-surface">
		<div class="mx-auto max-w-6xl px-5 py-20 md:px-8 md:py-24">
			<h2
				class="max-w-[22ch] font-display text-3xl leading-tight font-medium tracking-tight md:text-5xl"
			>
				{m.import_title()}
			</h2>
			<p class="mt-4 max-w-[52ch] text-lg leading-relaxed text-muted">{m.import_body()}</p>
			<div class="mt-10">
				<ImportSources />
			</div>
		</div>
	</section>

	<!-- What it is: asymmetric bento, one cell per pillar -->
	<section class="mx-auto max-w-6xl px-5 py-20 md:px-8 md:py-28">
		<div class="grid gap-5 md:grid-cols-5 md:grid-rows-2">
			<article
				class="relative flex min-h-[22rem] flex-col justify-between overflow-hidden rounded-[28px] bg-[linear-gradient(160deg,#13505a_0%,#2f7c7f_45%,#e8cf9f_100%)] p-8 text-[#fbf6ec] md:col-span-3 md:row-span-2 md:p-10"
			>
				<div class="relative z-10 max-w-[34ch]">
					<h3 class="font-display text-3xl leading-tight font-medium text-balance md:text-4xl">
						{m.shelf_title()}
					</h3>
					<p class="mt-4 text-lg leading-relaxed text-[#fbf6ec]/85">{m.shelf_body()}</p>
				</div>
				<ul class="relative z-10 mt-10 flex flex-wrap gap-2">
					{#each statuses as status (status)}
						<li
							class="rounded-full bg-[#0f2224]/35 px-4 py-2 text-sm font-medium text-[#fbf6ec] backdrop-blur-sm"
						>
							{status()}
						</li>
					{/each}
				</ul>
			</article>

			<article
				class="flex items-center gap-6 rounded-[28px] border border-line bg-paper p-8 md:col-span-2"
			>
				<img src={reedMark} alt="" width="318" height="453" class="h-28 w-auto shrink-0" />
				<div>
					<h3 class="font-display text-2xl font-medium">{m.private_title()}</h3>
					<p class="mt-2 leading-relaxed text-muted">{m.private_body()}</p>
				</div>
			</article>

			<article class="rounded-[28px] bg-surface p-8 md:col-span-2">
				<h3 class="font-display text-2xl font-medium">{m.week_title()}</h3>
				<p class="mt-2 leading-relaxed text-muted">{m.week_body()}</p>
			</article>
		</div>
	</section>

	<!-- Native apps -->
	<section class="mx-auto max-w-3xl px-5 pb-24 text-center md:px-8 md:pb-32">
		<img
			src={appIcon}
			alt=""
			width="512"
			height="512"
			loading="lazy"
			class="mx-auto h-28 w-28 rounded-[22.5%] shadow-[0_18px_40px_-18px_rgb(19_80_90/0.55)] md:h-32 md:w-32"
		/>
		<h2 class="mt-10 font-display text-3xl leading-tight font-medium tracking-tight md:text-5xl">
			{m.apple_title()}
		</h2>
		<p class="mx-auto mt-4 max-w-[46ch] text-lg leading-relaxed text-muted">{m.apple_body()}</p>
	</section>

	<!-- FAQ -->
	<section id="faq" class="scroll-mt-6 border-t border-line">
		<div class="mx-auto grid max-w-6xl gap-10 px-5 py-20 md:grid-cols-[1fr_2fr] md:px-8 md:py-24">
			<h2 class="font-display text-3xl font-medium tracking-tight md:text-4xl">{m.faq_title()}</h2>
			<div class="flex flex-col gap-3">
				{#each faqs as [question, answer] (question)}
					<details class="group rounded-[20px] bg-surface px-6 py-5 open:pb-6">
						<summary
							class="flex cursor-pointer list-none items-center justify-between gap-6 text-lg font-medium [&::-webkit-details-marker]:hidden"
						>
							{question()}
							<span
								aria-hidden="true"
								class="text-2xl leading-none text-muted transition-transform group-open:rotate-45"
								>+</span
							>
						</summary>
						<p class="mt-3 max-w-[60ch] leading-relaxed text-muted">{answer()}</p>
					</details>
				{/each}
			</div>
		</div>
	</section>
</main>

<footer class="border-t border-line">
	<div
		class="mx-auto flex max-w-6xl flex-col items-start justify-between gap-4 px-5 py-10 text-sm text-muted md:flex-row md:items-center md:px-8"
	>
		<div class="flex items-center gap-3">
			<img src={reedMark} alt="" width="318" height="453" class="h-11 w-auto" />
			<span>{m.footer_line()}</span>
		</div>
		<span>© {new Date().getFullYear()} Aaru</span>
	</div>
</footer>
