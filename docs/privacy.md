# Privacy policy

_Last updated 21 October 2026._

Aaru is a private media library: what you watch and read, kept for you. This page says what
Aaru stores, who else sees any of it, and how to delete it. If anything here stops matching
what Aaru does, this page changes first.

## The short version

- Your library is **private**. There is no public profile and no feed, and your library is
  never shared with other users. If you choose a handle, people who know it can send you a
  friend request; friends see your handle and name, nothing else.
- **Group chats are not end-to-end encrypted.** Messages in a group are stored readable on
  Aaru's server so the group works across your devices; the apps say so in every group.
- **No ads, no tracking.** Aaru does not sell or rent data, has no advertising code, and does
  not follow you across other apps or sites. When something breaks, an error report without your
  name, email or library goes to Sentry; Aaru's server counts a few product events (below) under
  a random account id.
- You can **delete your account** in Settings. That removes your library and account at once.

## What Aaru stores

**Your account.** How you sign in (Apple, Google or email), the identifier that service gives
Aaru, your email address when the service shares it, and a display name if you have one.
Sign-in sessions are stored only as one-way hashes; on the web the session lives in a secure,
HttpOnly cookie. Email sign-in codes are stored hashed and expire after 15 minutes.

**Your library.** The titles you add, their status, whether you own them, ratings, notes,
episode progress, your lists and saved shelves, and a short history of your changes so they
can be undone.

**Imports.** When you import a file (IMDb, Letterboxd, Goodreads, and others), Aaru reads it and
keeps the rows it found with that import so you can review the plan before anything changes.
The uploaded file itself is not kept. If you connect Trakt, Aaru stores Trakt's access tokens
encrypted and uses them only to import your history when you ask; disconnecting revokes them on
Trakt and deletes them here. Aaru uses Trakt but is not endorsed or certified by Trakt.

**Stremio.** If you connect Stremio, Aaru stores the link only as a one-way hash, with its name,
what it may do, and when it was last used. While it is connected, Stremio tells Aaru when you
start, pause and stop playing something, and Aaru keeps that playback session (the title,
episode, position and length) so it can tick off what you finished. Your changes from Stremio
appear in your history like any other. Revoking the link in Settings stops all of it.

**Profile and friends.** If you choose a handle, Aaru stores it. Anyone who types your exact
handle can see it with your name and send you a friend request; nobody can search or browse for
you. Aaru stores pending requests, who your friends are, who you blocked, and any report you
send about another user (the reason and your note). The person you block or report is not
told. Deleting your account removes all of it; a report someone sent about you keeps its reason
but no longer points to you.

**What your friends see.** Your friends, and only your friends, see what you are watching, what
you finished and when, your ratings, the last episode you ticked, and which titles you both have.
They never see your notes. Episodes you imported or restored don't show up as activity. Turn off
"Show my library to friends" in Settings and they see only your name and handle.

**Points, streaks and badges.** Aaru keeps a record of the points you earn (what earned them,
which title, and the day in your time zone), the days you kept a streak, and the badges you
earned. To count days in your time zone, your apps send it with each request and Aaru stores it
with those records. Your friends see your level and badges unless you turn off "Show my badges
and level to friends"; badges about your notes and the things you own are never shown to them.
The weekly friends board is off until you join it, and only friends who joined see you there.
Deleting your account removes all of it.

**Reactions and recommendations.** When you react to a friend's activity, Aaru stores which
emoji, on which of their titles and which day. When you recommend a title, Aaru stores it with
your note until your friend adds or dismisses it. Only the two of you see a recommendation;
your friend and their other friends see reactions on their rows.

**Invite links.** When you make an invite link, Aaru stores it with the title you attached (if
any), when it expires, and, once used, who opened it. Anyone holding the link sees your name,
your handle and that title, and nothing from your library. A link works once, for two weeks,
and you can revoke it. Deleting your account removes your links.

**Groups.** If you create or join a group, Aaru stores the group's name, its channels, who is in
it and with what role, invites waiting for an answer, and where you last read in each channel.
Every message you send in a group is stored as you wrote it, with who you tagged, and the other
members of that group can read it. Group messages are **not end-to-end encrypted**: Aaru's
server can read them. Nobody outside the group can find it or see anything in it. Deleting a
message empties it straight away. Deleting your account empties every message you sent in any
group and removes you from them; a group you owned passes to another member, or goes if nobody
else was in it. The export includes your groups and the messages you wrote.

In a channel about one title, Aaru uses your own progress in that title to hide messages that
would spoil what you have not watched yet, and to mark what you write so it is hidden from
people who are behind you. Nobody sees that mark but you. Your progress itself is shown to the
group only if you switch on "Share my progress" for that group; it is off until you do. Titles
added to a shared shelf show who added them. A watch party shows who is ready, and "Mark
watched" changes only your own library.

**Aaru in groups.** If you tag @aaru in a group, Aaru sends Anthropic (below) the last 30
messages of that channel, what the channel is about, and, only when it helps answer you, titles
from your own library with their status and progress. It never sends another member's library
or progress. Aaru's answer is posted in the channel like any message. Aaru keeps a count of how
many questions you asked each day and how much text they used, to keep the service fair.

**Importing your Stremio history.** If you choose to, you approve a code on stremio.com (your
Stremio password never reaches Aaru). Aaru then reads your Stremio library once, signs that
session out at once, and does not keep Stremio's session key. What it read becomes an import you
review like any other.

**Notifications.** If you turn on new-episode, group mention or group invite alerts, Aaru stores
your device's push token and those settings, and which groups you muted. A mention alert names who
tagged you and in which group and channel, never what they wrote. In a browser, it stores the subscription your browser hands over: an address at your
browser's push service (Google, Mozilla, Apple or Microsoft) and the keys that encrypt each alert so
only your browser can read it. Turning alerts off in that browser, or deleting your account, removes
it.

**Concerts.** If you choose a city for "Concerts near", Aaru stores its name, region, country and
a position rounded to about a kilometre, until you remove it in Settings. "Use my location"
asks your device for an approximate position once; it is rounded the same way, used for that
one search, and never stored or logged. To find concerts by your artists, Aaru looks up the
artists of the albums in your library; that list is catalog data, not about you.

**Error reports.** When the app, the website, the browser extension or Aaru's server hits an
error or crashes, it sends a report to Sentry: what failed, where in Aaru's code, the device or
browser type and app version, and the page address without anything after the `?`. It never
includes your name, email, what is in your library or what you wrote. On Netflix, Disney+ and
Prime Video the extension reports only the site, never the page you were on.

**Product counts.** Aaru's server notes a few events so the developer can see which parts of Aaru
are used: an account was created and how (Apple, Google or email), an import finished and from
where, a title was added or changed and by whom (you, an agent, an import or a player), a list or
group was created, a friend was added, an agent's request was approved or declined. Each event
carries only those words and your account's random id, never a title, a name, an email, text or
your IP address, and no profile is built from them. They go to PostHog. The apps and the website
send nothing of this kind themselves.

**Catalog data** (titles, posters, episode lists) is shared by everyone and is not about you.

## Who else is involved

Aaru only uses these services, and only for the purpose listed:

- **Hetzner** (Germany) runs Aaru's server and database and holds encrypted backups.
- **Cloudflare** serves the website at aaruapp.com and its DNS.
- **Apple** for Sign in with Apple and push notifications; **Google** for Sign in with Google.
- **Your browser's push service** (Google, Mozilla, Apple or Microsoft) carries browser alerts. It
  sees an encrypted message and when it was sent, never its text.
- **Resend** sends sign-in emails, so it receives your email address and that email.
- **Trakt**, only if you connect it, for importing your history.
- **Anthropic**, only when someone tags @aaru in a group, to write Aaru's answer. It receives
  what is described under "Aaru in groups" above, through its API, and does not train on it.
- **Stremio**, only if you connect it. Your Stremio app asks Aaru for your rows and reports
  what you play. If you import your Stremio history, Aaru's server reads your Stremio library
  once with the code you approved, then signs out. Aaru also asks Stremio's public catalog
  (Cinemeta) for a show's episode list by its IMDb id, never who you are.
- **TMDB, TVmaze, AniList, Open Library, MusicBrainz and ListenBrainz** provide catalog data.
  Aaru's server sends them what you search for and catalog ids, never who you are.
- **Ticketmaster** lists concerts. Aaru's server sends it an area of about 5 km around your
  city or approximate position, a distance, and artist names from albums people have added,
  never who you are. Tickets are bought on Ticketmaster's site, under its own terms.
- **Open-Meteo** turns the city you type for "Concerts near" into a place. It receives that
  text only.
- **Sentry** (Germany) receives the error reports described above.
- **PostHog** (European Union) receives the product counts described above, from Aaru's server
  only.

## How long it is kept

Everything stays until you delete it or delete your account. Deleting your account removes
it from the live database immediately. Encrypted backups are kept for 30 days, and one
backup a month is kept for 12 months, so a deleted account is fully gone from backups
within a year. Error reports are deleted within 90 days and product counts within a year.

## Your choices

- **Delete your account:** Settings → Delete account, in the app or on the web.
- **Export:** Settings → Export your data, in the app or on the web. JSON has everything; CSV
  opens in a spreadsheet and imports back into Aaru.
- **Questions or requests:** privacy@aaruapp.com.

Aaru is run by an individual developer based in the European Union. You have the rights the
GDPR gives you: access, correction, deletion, portability and objection.
