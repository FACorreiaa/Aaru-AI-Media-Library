# Owl: roadmaps that answer, chats that do not bleed, chat history (ASK-011)

Owner, 2026-11-10. Builds on `2026-11-04-assistant-design.md` (ASK-009) and GRAPH-003.

## Why

Three faults seen on the iPhone:

1. "Show me what I need to read to prepare for Secret Wars" got "I don't want to guess a
   roadmap", where another assistant gives a staged list.
2. Reopening the owl on a title page showed the earlier chat, and "What are critics saying about
   VisionQuest?" was answered with an apology about the earlier roadmap.
3. Chats are stored but there is nowhere to read them again.

The owl also had no source for how a title is rated.

## What was wrong

- The system prompt said "never invent an answer" and "check the order with title_relations
  first, and keep the roadmap consistent with it". Relations are empty for most franchises, so a
  careful model refused.
- A roadmap had to be written twice, as text and as the `plan_title_list` call, in 2,048 output
  tokens and four rounds. An answer that ran out of room dropped the call and was stored as done.
- A film or show sent without a year could never match, and a list sent without a name lost its
  steps.
- The card received only an import id, so a roadmap was a "Review the import" button.
- A chat is kept for 15 minutes on any screen and its last 12 turns are replayed; nothing told the
  model the latest question stands on its own.
- The API had no route to list, read or delete one chat.

## Decisions (owner)

| Question | Decision |
| --- | --- |
| When does the owl start a fresh chat? | The 15-minute rule stays. A **New chat** button is added |
| Where is history? | In the owl card, and a Chats list in Settings |
| Reviews and ratings | Provider audience scores: TMDB (films, shows) and AniList (anime, manga). No web search, no critics |
| Model for roadmaps | Stay on Haiku 5.5; a turn that asks for a list gets more room |

## Goals

- Asking for a roadmap, a reading or watch order, or a list of editions shows the list in the
  reply, in its steps, on iPhone, Mac and web. The user reviews it and saves it as a list.
- A new question in a chat is answered on its own.
- Past chats can be reopened, continued and deleted one at a time.
- "Is it good?" gets the audience score, credited, or an honest "I can't see that yet".

## Not goals

Web search, critics' reviews, a comics kind (comics stay collected editions of type book), chat
rename or search, changing the 15-minute rule, any recommendation outside the assistant.

## Must not happen

- A title added without the user's review. A roadmap stays a capture import the user approves.
- A made-up score or review.
- Two titles merged because their names are alike. A yearless film matches only when exactly one
  film has that exact name.
- A stranger's review text steering a write. A turn that read reviews makes every write a plan.

## Server

**History.** `GET /v1/chats` (30 a page, cursor on `(updated_at, id)`, chats with no turn left
out), `GET /v1/chats/{id}` (the latest 200 turns, each agent turn's components read again as they
are now), `DELETE /v1/chats/{id}`. Another user's chat is 404 to read and untouched by a delete.

**One question at a time.** When a chat has earlier turns the system prompt says they are
background only: do not return to, correct or continue an earlier reply unless asked.

**Roadmaps.**
- The prompt lets the model build a roadmap, an order or a list of editions from what it knows.
  `title_relations` confirms an order where the catalog has one; an empty answer is never a reason
  to refuse. The list goes in the tool call only, and the reply is one or two sentences.
- `plan_title_list` asks for a year on every film and show and always a list name; a list sent
  without one is named after the question.
- The components frame carries `roadmap`: the list name and its steps, each with a heading, a note
  and its titles as the model named them (title, type, year, author, note, optional, pair). It is
  stored with the turn, so history shows it. `importId` beside it is where it is reviewed.
- The scope gate also says whether the turn asks for several titles at once. Such a turn runs
  with effort `medium`, 8,192 output tokens and six rounds. Other turns are unchanged.
- An answer that runs out of room inside a tool call fails the turn. One that runs out in its
  text says "That answer was cut short."
- A captured film or show with no year and no id matches by its exact name: one such title
  matches, several wait for a pick by hand.
- An approved import says which list it made (`ImportDetail.listId`).

**Scores.** `title_scores` reads `catalog.ScoreService`: TMDB's vote average, count and the
start of up to three user reviews; AniList's average score and popularity. Cached six hours in
memory, never stored. Reviews are fenced, come with the spoiler guard, and taint the turn.

## Clients (web, iPhone, Mac)

- Card header: **New chat** and **History**. History lists chats (title, when); a tap loads its
  turns and continues it; one can be deleted.
- Settings: the same list, delete one, delete all.
- `RoadmapCard` in a turn: the list name, numbered steps with heading and note, titles under each
  with Optional and side-by-side marks, and "Review and save", which opens the import review.
- The import review groups rows by step when they carry one, and links to the saved list after
  approval.

## Calls I made (owner: check these)

- The roadmap is shown from the tool call, not written out by the model, so it is paid for once
  and cannot be cut in half.
- The web's Settings surface for chats is the list inside Your data, not a new route.
- Scores are labelled as audience scores from their source; the owl never calls them reviews by
  critics.
- A chat reopened from history restarts its 15-minute clock.
- History reads a turn's titles and plan as they are now; a deleted import's link is dropped and
  its roadmap stays as text.
