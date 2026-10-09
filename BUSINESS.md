# Business

Strategy notes for Aaru: what could be defensible, and how it could pay.
Written 2026-09-12, pre-users. Nothing here is decided. This file records
thinking so it does not have to be redone; it is not a plan of record.

## Moat

Ranked, honest.

**1. Tracking itself — zero moat.** Trakt, Letterboxd, Goodreads, Simkl and
Serializd all exist and are free. The core loop is a commodity.

**2. Privacy — weak.** Private-first is a good positioning line. People say they
want it; few pay for it. Not a moat on its own.

**3. Cross-media unification — medium.** Books, movies and TV in one library.
Incumbents are culturally single-medium: Letterboxd will not ship books,
Goodreads will not ship TV. That gap is hard for them to cross and easy for a
new entrant to copy.

**4. Import matching quality — small but durable.** External-ID-first matching
across Trakt, IMDb, Letterboxd, Goodreads and CAT, with no bad merges. Dull
grunt work that most competitors do badly. Users notice it once and stay. Not a
moat by itself; it is a reason to switch.

**5. Agent / tool layer — the only real wedge.** Per-user scoped tokens, MCP at
`POST /v1/mcp`, App Intents, and plan-then-approve for anything larger than a
tap. No one in this category has a write-capable personal media layer an outside
assistant can reach safely. If "my media library" becomes something a user's
assistant talks to, being the default endpoint is sticky.

**6. Data gravity — slow.** Library plus the Action journal accumulates over
time. Export undoes it. Takes years to matter.

**Verdict: no strong moat. Aaru is a taste-and-execution product.** The category
is a graveyard of beautiful trackers with no revenue. Item 5 is the only
candidate that is more than a feature, and only if it is treated as the product
rather than a bolt-on.

## Monetisation

Gate what costs money to run, or what power users specifically need. Do not gate
what makes the app usable.

**Free, permanently:** manual add, status, rating, notes, TV progress, lists,
shelves.

**Paid, around £24/yr or £2.99/mo:**

- Trakt OAuth and all CSV imports (import jobs are server compute)
- Capture from text, image or URL (model spend)
- Agent tokens and MCP access
- Unlimited shelves / saved queries

Bring-your-own model key unmeters the agent features at the paid tier. The
pluggable `ModelProviding` design already allows this.

Later, if it is ever warranted: a household plan.

**Do not:** ads, data sale, or streaming affiliate links. All three contradict
the private-first claim, which is the only story Aaru has.

## Expected size

Letterboxd Pro is about £19/yr against a very large audience. Serializd and
Simkl are small. A solo consumer tracker should expect roughly £0–300/mo unless
the agent thesis catches a different wave.

If revenue is the goal, the agent layer sold as infrastructure — "your
assistant's memory for what you watch and read" — is a larger market than the
tracker. That is a different product decision, not a pricing one.

## Open question

Aaru is worth building as an app to want to exist. As a business it needs the
agent thesis picked deliberately and built toward. That choice is not made yet,
and per the repo's own rules it should not be made before strangers have used
the current version.
